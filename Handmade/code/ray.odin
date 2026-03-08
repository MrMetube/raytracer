package main

import "core:os"
import "core:math"
import "core:simd"

Material :: struct {
    emit:    v3,
    reflect: v3,
    emit_factor: f32,
    scatter: f32, // 0 = mirror like, 1 = chalk like
    
    brdf: BrdfTable,
}

BrdfTable :: struct {
    count: [3] u32,
    // @note(viktor): a view into the World.all_brdf_values array
    values_index: u32,
    values_count: u32,
}

Plane :: struct {
    normal, tangent, binormal: v3,
    center:   v3,
    radius:   f32,
    material: u32,
}

Triangle :: struct {
    a: v3,
    b: v3,
    c: v3,
    material: u32,
}

lane_Node_Index  :: #simd [LaneWidth] Node_Index
lane_Value_Index :: #simd [LaneWidth] Value_Index

////////////////////////////////////////////////

load_brdf_merl :: proc (filename: string, dest: ^BrdfTable, all_brdf_values: ^[dynamic] v3) {
    invalid := false
    data: [] u8
    if filename == "" {
        invalid = true
    } else {
        err: os.Error
        data, err = os.read_entire_file(filename, context.temp_allocator)
        if err != nil {
            invalid = true
            print("Unable to open MERL binary %\n", filename)
        }
    }
    
    dest.values_index = cast(u32) len(all_brdf_values)
    if !invalid {
        dest.count, data = (cast(^uv3) &data[0])^, data[size_of(uv3):]
        
        total_count := dest.count[0] * dest.count[1] * dest.count[2]
        temp_values := (cast([^]f64) &data[0])[:total_count * len(v3)]
        // :BelowHorizon we currently check and handle negative values in the raytracer by defaulting to no color , but this could be handled here right?
        
        file_size := cast(umm) &data[0] + auto_cast len(data)
        read_size := cast(umm) &temp_values[0] + auto_cast len(temp_values) * size_of(f64)
        assert(file_size == read_size)
        
        dest.values_count = total_count
        
        start := dest.values_index
        reserve(all_brdf_values, start + total_count)
        
        for i in 0..<total_count {
            result: v3
            result.r = cast(f32) temp_values[i + total_count * 0]
            result.g = cast(f32) temp_values[i + total_count * 1]
            result.b = cast(f32) temp_values[i + total_count * 2]
            
            // @note(viktor): a value of -1 indicates that the reflection would be below the horizon :BelowHorizon
            result = vec_max(result, 0)
            
            // @note(viktor): prescale the values per channel
            BRDF_Scale :: v3 {
                1.00/1500.0, 
                1.15/1500.0, 
                1.66/1500.0,
            }
            result *= BRDF_Scale
            
            append(all_brdf_values, result)
        }
        
        assert(len(all_brdf_values) == auto_cast(start + total_count))
        assert(len(all_brdf_values) == cap(all_brdf_values))
    } else {
        dest.values_count = 1
        
        dest.count = 1
        append(all_brdf_values, v3{1,1,1})
    }
}

////////////////////////////////////////////////

Debug_View := 0
Triangle_Threshold : f32 = 500
Rectangle_Threshold : f32 = 1000

render_tile :: proc(world: ^World, camera: Camera, image: Image, rect: Rectangle2i, entropy: ^RandomSeries, rays_per_pixel, max_bounce_count: u32) {
    film_distance :: 1
    film_center := vec_cast(lane_f32, camera.p - film_distance * camera.z)
    
    film_size := cast(v2) 1
    
    image_size := vec_cast(f32, image.width, image.height)
    if image_size.x > image_size.y {
        film_size.x = film_size.y * image_size.x / image_size.y
    } else if image_size.x < image_size.y {
        film_size.y = film_size.x * image_size.y / image_size.x
    }
    
    half_film_size := vec_cast(lane_f32, .5 * film_size)
    pixel_size := 1. / vec_cast(lane_f32, image_size)
    
    bounces_computed, loops_computed: u64
    for py in rect.min.y ..< rect.max.y {
        film_y := -1 + 2 * cast(f32) py / image_size.y
        for px in rect.min.x ..< rect.max.x {
            film_x := -1 + 2 * cast(f32) px / image_size.x
            film_p := vec_cast(lane_f32, film_x, film_y)
            
            cast_info := cast_rays(world, film_p, entropy, pixel_size, half_film_size, film_center, camera, rays_per_pixel, max_bounce_count)
            
            bounces_computed += cast_info.bounces_computed
            loops_computed   += cast_info.loops_computed
            
            color := cast_info.final_color
            triangle_color  := (cast(f32) cast_info.triangles_tested  / LaneWidth) / Triangle_Threshold
            rectangle_color := (cast(f32) cast_info.rectangles_tested / LaneWidth) / Rectangle_Threshold
            color = linear_to_srgb(color)
            if Debug_View == 1 {
                color = triangle_color
                if triangle_color > 1 do color = v3{1, 0, 0}
            } else if Debug_View == 2 {
                color = rectangle_color
                if rectangle_color > 1 do color = v3{1, 0, 0}
            } else if Debug_View == 3 {
                color.r = triangle_color
                color.g = 0
                color.b = rectangle_color
                if max(triangle_color, rectangle_color) > 1 do color = v3{1, 1, 1}
            }
            
            pixel := color_to_u8(color)
            
            pixel_index := (image.height - 1 - py) * image.width + px
            #no_bounds_check {
                image.data[pixel_index] = pixel
            }
        }
        atomic_add(&world.pixels_done, auto_cast rectangle_get_dimension(rect).x)
    }
    
    atomic_add(&world.bounces_computed, bounces_computed)
    atomic_add(&world.loops_computed, loops_computed)
    atomic_add(&world.tiles_retired, 1)
}

Hit_Info :: struct {
    closest_t: lane_f32,
    did_hit:   lane_u32,
    material:  lane_u32,
    next_o:    lane_v3,
    normal:    lane_v3,
    tangent:   lane_v3,
    binormal:  lane_v3,
}

Cast_Info :: struct {
    final_color: v3, 
    bounces_computed, loops_computed, triangles_tested, rectangles_tested: u64,
}

cast_rays :: proc (world: ^World, init_film_p: lane_v2, entropy: ^RandomSeries,  pixel_size: lane_v2, half_film_size: lane_v2, film_center: lane_v3, camera: Camera, rays_per_pixel, max_bounce_count: u32) -> Cast_Info {
    spall_proc()
    final_color_lanes: lane_v3
    
    bounces_computed_lanes:  lane_u32
    loops_computed_lanes:    lane_u32
    triangles_tested_lanes:  lane_u32
    rectangles_tested_lanes: lane_u32
    
    lane_ray_count := rays_per_pixel / LaneWidth
    sample_contribution_factor := 1.0 / cast(f32) rays_per_pixel
    
    camera_p := vec_cast(lane_f32, camera.p)
    camera_x := vec_cast(lane_f32, camera.x)
    camera_y := vec_cast(lane_f32, camera.y)
    
    backing_values: [8192] [LaneWidth] Value_Index
    values := backing_values[:]
    
    triangle_tests: Stat(u32)
    all_triangle_tests: Stat(u32)
    
    for _ in 0..<lane_ray_count {
        jitter := random_unilateral(entropy, lane_v2)
        offset := init_film_p + jitter * pixel_size
        film_p := film_center + (offset.x*camera_x*half_film_size.x + offset.y*camera_y * half_film_size.y) 
        
        // @todo(viktor): depth blur can be added here by jittering the ray_o
        ray_o := camera_p
        ray_d := normalize_or_zero(film_p - camera_p)
        
        min_t       := cast(lane_f32) 0.0001
        attenuation := cast(lane_v3) 1
        lane_mask   := lane_true
        sample: lane_v3
        
        for _ in 0..<max_bounce_count {
            hit: Hit_Info
            hit.closest_t = +Infinity
            
            bounces_computed_lanes += 1 & lane_mask
            loops_computed_lanes   += 1
            
            ////////////////////////////////////////////////
            
            for &plane in world.planes {
                tolerance :: 0.00001
                
                plane_normal   := normalize_or_zero(vec_cast(lane_f32, plane.normal))
                plane_tangent  := vec_cast(lane_f32, plane.tangent)
                plane_binormal := vec_cast(lane_f32, plane.binormal)
                
                center := vec_cast(lane_f32, plane.center)
                radius := cast(lane_f32) plane.radius
                
                denom := dot(plane_normal, ray_d)
                denom_mask := ~approximate_equal(denom, 0, tolerance)
                if denom_mask == lane_false do continue
                
                t := dot(plane_normal, center - ray_o) / denom
                t_mask := greater_than(t, min_t) & less_than(t, hit.closest_t)
                if t_mask == lane_false do continue
                
                hit_point := ray_o + t * ray_d
                local_hit := hit_point - center
                t_mask &= less_than(absolute(local_hit.x), radius)
                t_mask &= less_than(absolute(local_hit.y), radius)
                t_mask &= less_than(absolute(local_hit.z), radius)
                if t_mask == lane_false do continue
                
                hit_mask := denom_mask & t_mask
                
                update_hit(&hit, hit_mask, t, plane.material, ray_o + t*ray_d, plane_normal, plane_tangent, plane_binormal)
            }
            
            ////////////////////////////////////////////////
            
            if Use_Tree {
                local_nil_value_lanes_tested: [LaneWidth] u32
                
                nodes := world.triangle_nodes
                values_len := traverse_tree_and_collect_values(values[:], to_lane(world.triangles), nodes[:], ray_o, ray_d, min_t, hit.closest_t, &hit, &local_nil_value_lanes_tested, &triangles_tested_lanes, &rectangles_tested_lanes)
                
                if Use_Value_Stack {
                    spall_begin("values")
                    min_len := simd.reduce_min(values_len)
                    
                    spall_begin("values flush")
                    triangles := to_lane(world.triangles)
                    stat_update(&triangle_tests, horizontal_add(values_len))
                    stat_update(&all_triangle_tests, simd.reduce_max(values_len) * LaneWidth)
                    
                    // @cleanup there is lots of duplicate code and lots of opportunity to compress
                    counts := values_len - min_len
                    base := min_len
                    values_len -= counts
                    
                    // @note(viktor): reduce each stack to the min_len by testing values x LaneWidth for each lane until all are flush.
                    for lane in 0..<LaneWidth {
                        spall_begin("hit extract")
                        lane_hit: Hit_Info
                        lane_hit.closest_t =    cast(lane_f32) extract(hit.closest_t, lane)
                        lane_hit.did_hit   =    cast(lane_u32) extract(hit.did_hit, lane)
                        lane_hit.material  =    cast(lane_u32) extract(hit.material, lane)
                        lane_hit.next_o    = vec_cast(lane_f32, extract_v3(hit.next_o, lane))
                        lane_hit.normal    = vec_cast(lane_f32, extract_v3(hit.normal, lane))
                        lane_hit.tangent   = vec_cast(lane_f32, extract_v3(hit.tangent, lane))
                        lane_hit.binormal  = vec_cast(lane_f32, extract_v3(hit.binormal, lane))
                        
                        lane_ray_o := vec_cast(lane_f32, extract_v3(ray_o, lane))
                        lane_ray_d := vec_cast(lane_f32, extract_v3(ray_d, lane))
                        spall_end()
                        ////////////////////////////////////////////////
                        
                        
                        count := extract(counts, lane)
                        count_x8  := count / LaneWidth
                        remainder := count % LaneWidth
                        
                        values := to_lane(values)
                        
                        for index in base..<base+count_x8 {
                            lane_value_index := lane_index(lane_index(values, index + lane_offset), cast(lane_u32) lane)
                            
                            value_index := lane_gather(lane_value_index)
                            
                            triangle := lane_index(triangles, cast(lane_u32) value_index)
                            value_mask := not_equal(value_index, 0)
                            triangles_tested_lanes += 1 & value_mask
                            hit_triangle(value_mask, triangle, lane_ray_o, lane_ray_d, min_t, &lane_hit)
                        }
                        local_nil_value_lanes_tested[0] = count_x8
                        
                        ////////////////////////////////////////////////
                        
                        if remainder != 0 {
                            local_nil_value_lanes_tested[LaneWidth-remainder] += 1
                            index := base+count_x8
                            
                            load_mask := less_than(lane_offset, cast(lane_u32) remainder)
                            
                            lane := lane_index(lane_index(values, index + lane_offset), cast(lane_u32) lane)
                            value_index := lane_gather_mask(lane, load_mask, 0)
                            
                            triangle := lane_index(triangles, cast(lane_u32) value_index)
                            value_mask := not_equal(value_index, 0)
                            triangles_tested_lanes += 1 & value_mask
                            hit_triangle(value_mask, triangle, lane_ray_o, lane_ray_d, min_t, &lane_hit)
                        }
                        
                        ////////////////////////////////////////////////
                        
                        min_lane: int = -1
                        min_closest_t := extract(hit.closest_t, lane)
                        if greater_equal(lane_hit.closest_t, cast(lane_f32) min_closest_t) == lane_true do continue
                        
                        spall_begin("hit replace")
                        for n in 0..<LaneWidth {
                            t := extract(lane_hit.closest_t, n)
                            if min_closest_t > t {
                                min_closest_t = t
                                min_lane = n
                            }
                        }
                        
                        replace(&hit.closest_t,   lane, extract(lane_hit.closest_t,   min_lane))
                        replace(&hit.did_hit,     lane, extract(lane_hit.did_hit,     min_lane))
                        replace(&hit.material,    lane, extract(lane_hit.material,    min_lane))
                        replace_v3(&hit.next_o,   lane, extract_v3(lane_hit.next_o,   min_lane))
                        replace_v3(&hit.normal,   lane, extract_v3(lane_hit.normal,   min_lane))
                        replace_v3(&hit.tangent,  lane, extract_v3(lane_hit.tangent,  min_lane))
                        replace_v3(&hit.binormal, lane, extract_v3(lane_hit.binormal, min_lane))
                        spall_end()
                    }
                    
                    spall_end()
                    
                    spall_begin("values x8")
                    for min_len != 0 {
                        min_len -= 1
                        value_index := transmute(lane_Value_Index) values[min_len]
                        triangle := lane_index(triangles, transmute(lane_u32) value_index)
                        value_mask := not_equal(value_index, 0)
                        triangles_tested_lanes += 1 & value_mask
                        hit_triangle(value_mask, triangle, ray_o, ray_d, min_t, &hit)
                    }
                    spall_end()
                    
                    spall_end()
                    local_nil_value_lanes_tested[0] += min_len
                }
                
                for i in 0..<len(world.nil_value_lanes_tested) {
                    atomic_add(&world.nil_value_lanes_tested[i], local_nil_value_lanes_tested[i])
                }
            } else {
                triangles := to_lane(world.triangles) // @cleanup
                for index in 0 ..< cast(Value_Index) len(world.triangles) {
                    triangle := lane_index(triangles, cast(lane_u32) index)
                    hit_triangle(lane_true, triangle, ray_o, ray_d, min_t, &hit)
                }
                stat_update(&triangle_tests, cast(u32) len(world.triangles) * LaneWidth)
                stat_update(&all_triangle_tests, cast(u32) len(world.triangles) * LaneWidth)
            }
            
            ////////////////////////////////////////////////
            
            materials       := to_lane(world.materials)
            all_brdf_values := to_lane(world.all_brdf_values)
            
            material        := lane_index(materials, hit.material)
            hit_emit        := lane_gather_v(lane_member(material, "emit",        type_of(Material{}.emit)))
            hit_reflect     := lane_gather_v(lane_member(material, "reflect",     type_of(Material{}.reflect)))
            hit_scatter     := lane_gather(  lane_member(material, "scatter",     type_of(Material{}.scatter)))
            hit_emit_factor := lane_gather(  lane_member(material, "emit_factor", type_of(Material{}.emit_factor)))
            
            // only allow world.no_hit on the first time we didn't hit anything
            hit_emit.r *= cast(lane_f32) (1 & lane_mask)
            hit_emit.g *= cast(lane_f32) (1 & lane_mask)
            hit_emit.b *= cast(lane_f32) (1 & lane_mask)
            
            // Color Accumulation
            sample += attenuation * (hit_emit * hit_emit_factor)
            
            lane_mask &= hit.did_hit
            if lane_mask == lane_false do break
            
            // Bounce
            pure_bounce   := reflect(ray_d, hit.normal)
            random_bounce := normalize_or_zero(hit.normal + random_bilateral(entropy, lane_v3))
            
            next_d := linear_blend(pure_bounce, random_bounce, hit_scatter)
            
            reflectance := brdf_lookup(all_brdf_values, materials, hit.material, -ray_d, hit.normal, hit.tangent, hit.binormal, next_d)
            reflectance *= hit_reflect
            conditional_assign(hit.did_hit, &attenuation, attenuation * reflectance)
            
            ray_o = hit.next_o
            ray_d = next_d
        }
        
        final_color_lanes += sample_contribution_factor * sample
    }
    
    result: Cast_Info
    result.final_color.r = horizontal_add(final_color_lanes.r)
    result.final_color.g = horizontal_add(final_color_lanes.g)
    result.final_color.b = horizontal_add(final_color_lanes.b)
    
    result.bounces_computed  = cast(u64) horizontal_add(bounces_computed_lanes)
    result.loops_computed    = cast(u64) horizontal_add(loops_computed_lanes)
    result.triangles_tested  = cast(u64) horizontal_add(triangles_tested_lanes)
    result.rectangles_tested = cast(u64) horizontal_add(rectangles_tested_lanes)
    
    atomic_add(&world.all_triangle_tests.count, all_triangle_tests.count)
    atomic_add(&world.all_triangle_tests.sum,   all_triangle_tests.sum)
    atomic_add(&world.triangle_tests.count, triangle_tests.count)
    atomic_add(&world.triangle_tests.sum,   triangle_tests.sum)
    
    return result
}

////////////////////////////////////////////////

Use_Value_Stack := !false
Use_Lanes := false

traverse_tree_and_collect_values :: proc (_values_stack: [] [LaneWidth] Value_Index, triangles: Lane_Slice(Triangle), nodes: [] Tree_Node, ray_o, ray_d: lane_v3, min_t, max_t: lane_f32, hit: ^Hit_Info, local_nil_value_lanes_tested: ^[LaneWidth] u32, triangles_tested_lanes, rectangles_tested_lanes: ^lane_u32) -> (_values_len: lane_u32) {
    spall_proc()
    
    nodes        := to_lane(nodes)
    _values_stack := to_lane(_values_stack)
    
    inv_d := 1 / ray_d
    neg_inv_o := -(ray_o * inv_d)
    
    // @volatile max tree depth
    backing: [64] [LaneWidth] Node_Index
    backing[0] = Root_Index
    
    stack_count := cast(lane_u32) 1
    stack := to_lane(backing[:])
    
    for stack_count != 0 {
        it_mask := not_equal(stack_count, 0)
        conditional_assign(it_mask, &stack_count, stack_count-1)
        stack_top := lane_index(lane_index(stack, stack_count), lane_offset)
        
        it_index := lane_gather(stack_top, it_mask, cast(lane_Node_Index) Nil_Index)
        
        node := lane_index(nodes, cast(lane_u32) it_index)
        
        // rectangles_tested_lanes^ += 1 & it_mask
        // hit_mask, _ := hit_rectangle(node, neg_inv_o, inv_d, min_t, hit.closest_t)
        hit_mask := not_equal(it_index, Nil_Index)
        if hit_mask == lane_false do continue
        
        node_value_count := lane_gather_mask(lane_member(node, "value_count", u32), hit_mask, 0)
        has_subnodes := equal(node_value_count, 0)
        has_values   := ~has_subnodes
        has_subnodes &= hit_mask
        has_values   &= hit_mask
        
        #assert(offset_of(Tree_Node{}.first.subnode) == offset_of(Tree_Node{}.first.value))
        node_first := cast(Lane(Node_Index)) lane_member(node, "first", type_of(Tree_Node{}.first))
        first := lane_gather(node_first)
        when false do assert(first.p == lane_member(node_first, "value", Value_Index).p)
        
        first_subnode := first & cast(lane_Node_Index)  has_subnodes
        first_value   := cast(lane_u32) first &  has_values
        has_subnodes  &= not_equal(cast(lane_u32) first_subnode, Nil_Index)
        
        if has_subnodes != lane_false {
            index_0 := first_subnode+0
            index_1 := first_subnode+1
            
            node0 := lane_index(nodes, cast(lane_u32) index_0)
            node1 := lane_index(nodes, cast(lane_u32) index_1)
            
            hit0, tmin0 := hit_rectangle(node0, neg_inv_o, inv_d, min_t, hit.closest_t)
            hit1, tmin1 := hit_rectangle(node1, neg_inv_o, inv_d, min_t, hit.closest_t)
            rectangles_tested_lanes^ += 2 & has_subnodes
            
            one_is_near := less_than(tmin1, tmin0)
            node_near := ternary(one_is_near, index_1, index_0)
            node_far  := ternary(one_is_near, index_0, index_1)
            hit_near  := ternary(one_is_near, hit1, hit0)
            hit_far   := ternary(one_is_near, hit0, hit1)
            
            append_near := has_subnodes
            append_far  := has_subnodes
            append_near &= hit_near
            append_far  &= hit_far
            
            x0 := lane_index(lane_index(stack, stack_count+0),            lane_offset)
            x1 := lane_index(lane_index(stack, stack_count+1&append_far), lane_offset)
            lane_scatter(x0, node_far,  append_far)
            lane_scatter(x1, node_near, append_near)
            conditional_assign(append_far,  &stack_count, stack_count + 1)
            conditional_assign(append_near, &stack_count, stack_count + 1)
        }
        
        if has_values != lane_false {
            value_count := first_value + node_value_count
            
            if Use_Value_Stack {
                value_index := first_value
                for {
                    value_mask := less_than(value_index, value_count)
                    if value_mask == 0 do break
                    
                    when true {
                        assert(less_than(_values_len, _values_stack.len) == lane_true) 
                    }
                    values_end := lane_index(_values_stack, _values_len)
                    lane_scatter(values_end, lane_offset, cast(lane_Value_Index) value_index, value_mask)
                    
                    conditional_assign(value_mask, &_values_len, _values_len+1)
                    conditional_assign(value_mask, &value_index, value_index+1)
                }
            } else if !Use_Lanes {
                value_index := first_value
                for {
                    value_mask := less_than(value_index, value_count)
                    if value_mask == 0 do break
                    
                    triangle := lane_index(triangles, value_index)
                    hit_triangle(value_mask, triangle, ray_o, ray_d, min_t, hit)
                    
                    conditional_assign(value_mask, &value_index, value_index+1)
                    
                    empties := horizontal_add(1 & value_mask)
                    local_nil_value_lanes_tested[8 - empties] += 1
                    triangles_tested_lanes^ += 1 & value_mask
                }
            } else {
                for lane in 0..<LaneWidth {
                    first := extract(first_value, lane)
                    count := extract(value_count, lane)
                    if count == 0 do continue
                    
                    ////////////////////////////////////////////////
                    
                    lane_hit: Hit_Info
                    lane_hit.closest_t =     cast(lane_f32) extract(hit.closest_t,   lane)
                    lane_hit.did_hit   =     cast(lane_u32) extract(hit.did_hit,     lane)
                    lane_hit.material  =     cast(lane_u32) extract(hit.material,    lane)
                    lane_hit.next_o    = vec_cast(lane_f32, extract_v3(hit.next_o,   lane))
                    lane_hit.normal    = vec_cast(lane_f32, extract_v3(hit.normal,   lane))
                    lane_hit.tangent   = vec_cast(lane_f32, extract_v3(hit.tangent,  lane))
                    lane_hit.binormal  = vec_cast(lane_f32, extract_v3(hit.binormal, lane))
                    
                    lane_ray_o := vec_cast(lane_f32, extract_v3(ray_o, lane))
                    lane_ray_d := vec_cast(lane_f32, extract_v3(ray_d, lane))
                    
                    ////////////////////////////////////////////////
                    
                    count_x8  := count / LaneWidth
                    remainder := count % LaneWidth
                    for index := first; index < first + count_x8; index += LaneWidth {
                        value_index := index + lane_offset
                        load_mask := less_than(value_index, triangles.len)
                        value_index &= load_mask
                        
                        triangle := lane_index(triangles, value_index)
                        
                        value_mask := not_equal(value_index , 0)
                        triangles_tested_lanes^ += 1 & equal(lane_offset, cast(lane_u32) lane) & value_mask
                        hit_triangle(value_mask, triangle, lane_ray_o, lane_ray_d, min_t, &lane_hit)
                    }
                    local_nil_value_lanes_tested[0] = count_x8
                    
                    if remainder != 0 {
                        local_nil_value_lanes_tested[LaneWidth-remainder] += 1
                        index := first + count_x8
                        
                        value_index := index + lane_offset
                        load_mask := less_than(value_index, triangles.len)
                        value_index &= load_mask
                        
                        triangle := lane_index(triangles, value_index)
                        value_mask := not_equal(value_index, 0) & load_mask
                        triangles_tested_lanes^ += 1 & equal(lane_offset, cast(lane_u32) lane) & value_mask
                        hit_triangle(value_mask, triangle, lane_ray_o, lane_ray_d, min_t, &lane_hit)
                    }
                    if lane_hit.did_hit == lane_false do continue
                    
                    ////////////////////////////////////////////////
                    
                    
                    min_lane: int = -1
                    min_closest_t := extract(hit.closest_t, lane)
                    if greater_equal(lane_hit.closest_t, cast(lane_f32) min_closest_t) == lane_true do continue
                    
                    for n in 0..<LaneWidth {
                        t := extract(lane_hit.closest_t, n)
                        if min_closest_t > t {
                            min_closest_t = t
                            min_lane = n
                        }
                    }
                    
                    replace(&hit.closest_t,   lane, extract(lane_hit.closest_t,   min_lane))
                    replace(&hit.did_hit,     lane, extract(lane_hit.did_hit,     min_lane))
                    replace(&hit.material,    lane, extract(lane_hit.material,    min_lane))
                    replace_v3(&hit.next_o,   lane, extract_v3(lane_hit.next_o,   min_lane))
                    replace_v3(&hit.normal,   lane, extract_v3(lane_hit.normal,   min_lane))
                    replace_v3(&hit.tangent,  lane, extract_v3(lane_hit.tangent,  min_lane))
                    replace_v3(&hit.binormal, lane, extract_v3(lane_hit.binormal, min_lane))
                }
            }
        }
    }
    
    return _values_len
}

////////////////////////////////////////////////

hit_rectangle :: proc (node: Lane(Tree_Node), neg_inv_o, inv_d: lane_v3, t_min_init, t_max_init: lane_f32) -> (lane_u32, lane_f32) {
    spall_proc()
    node_min := lane_member(node, "bounds", "min", v3)
    node_max := lane_member(node, "bounds", "max", v3)
    min  := lane_gather_v(node_min)
    max  := lane_gather_v(node_max)
    
    t1x := fused_mul_add(min.x, inv_d.x, neg_inv_o.x)
    t1y := fused_mul_add(min.y, inv_d.y, neg_inv_o.y)
    t1z := fused_mul_add(min.z, inv_d.z, neg_inv_o.z)
    t2x := fused_mul_add(max.x, inv_d.x, neg_inv_o.x)
    t2y := fused_mul_add(max.y, inv_d.y, neg_inv_o.y)
    t2z := fused_mul_add(max.z, inv_d.z, neg_inv_o.z)
    
    // @speed check the latency and throughput of min&max and if select would be better due to the duplicated comparison? 
    tin := lane_v3 { minimum(t1x, t2x), minimum(t1y, t2y), minimum(t1z, t2z) }
    tax := lane_v3 { maximum(t1x, t2x), maximum(t1y, t2y), maximum(t1z, t2z) }
    
    tmin := maximum(maximum(t_min_init, tin.x), maximum(tin.y, tin.z))
    tmax := minimum(minimum(t_max_init, tax.x), minimum(tax.y, tax.z))
    
    result     := less_equal(tmin, tmax)
    result_min := ternary(result, tmin, cast(lane_f32) +Infinity)
    
    return result, result_min
}

hit_triangle :: proc (not_nil_mask: lane_u32, triangle: Lane(Triangle), ray_o, ray_d: lane_v3, min_t: lane_f32, hit: ^Hit_Info) {
    spall_proc()
    
    Check :: false
    when Check do assert(not_nil_mask != lane_false)
    
    a        := lane_gather_v(lane_member(triangle, "a", v3), not_nil_mask, lane_v3{})
    b        := lane_gather_v(lane_member(triangle, "b", v3), not_nil_mask, lane_v3{})
    c        := lane_gather_v(lane_member(triangle, "c", v3), not_nil_mask, lane_v3{})
    material := lane_gather(  lane_member(triangle, "material", u32), not_nil_mask, lane_u32{})
    
    // @speed pre-compute ab and ac? but only if compute becomes the bottleneck
    ab := b - a
    ac := c - a
    ray_cross_ac := cross(ray_d, ac)
    determinant  := dot(ab, ray_cross_ac)
    
    not_parallel_mask := ~approximate_equal(determinant, 0, 1e-6) 
    not_parallel_mask &= not_nil_mask
    if not_parallel_mask == lane_false do return
    
    inv_determinant := 1.0 / determinant
    s := ray_o - a
    u := inv_determinant * dot(s, ray_cross_ac)
    
    u_mask := greater_equal(u, 0) & less_equal(u, 1)
    u_mask &= not_parallel_mask
    if u_mask == lane_false do return
    
    s_cross_ab := cross(s, ab)
    v := inv_determinant * dot(ray_d, s_cross_ab)
    
    v_mask := greater_equal(v, 0) & less_equal(u + v, 1)
    v_mask &= u_mask
    if v_mask == lane_false do return
    
    t := inv_determinant * dot(ac, s_cross_ab)
    hit_mask := greater_than(t, min_t) & less_than(t, hit.closest_t)
    hit_mask &= v_mask
    if hit_mask == lane_false do return
    
    // @todo(viktor): interpolate the vertex normals
    // @note(viktor): Assuming counter-clockwise winding order
    normal   := normalize_or_zero(cross(ab, ac))
    tangent  := normalize_or_zero(ab)
    binormal := normalize_or_zero(cross(normal, tangent))
    
    next_o := ray_o + t*ray_d
    update_hit(hit, hit_mask, t, material, next_o, normal, tangent, binormal)
}

update_hit :: proc (hit: ^Hit_Info, hit_mask: lane_u32, t: lane_f32, material: lane_u32, next_o: lane_v3, normal, tangent, binormal: lane_v3) {
    conditional_assign(hit_mask, &hit.closest_t, t)
    conditional_assign(hit_mask, &hit.did_hit, lane_true)
    
    conditional_assign(hit_mask, &hit.material, material)
    
    conditional_assign(hit_mask, &hit.next_o, next_o)
    conditional_assign(hit_mask, &hit.normal, normal)
    
    conditional_assign(hit_mask, &hit.tangent,   tangent)
    conditional_assign(hit_mask, &hit.binormal, binormal)
}

////////////////////////////////////////////////

brdf_lookup :: proc (all_brdf_values: Lane_Slice(v3), materials: Lane_Slice(Material), index: lane_u32, view_direction, normal, tangent, binormal, light_direction: lane_v3) -> lane_v3 {
    half_vector := normalize_or_zero(.5 * (view_direction + light_direction))
    
    lw := lane_v3 {
        dot(light_direction, tangent),
        dot(light_direction, binormal),
        dot(light_direction, normal),
    }
    
    hw := lane_v3 {
        dot(half_vector, tangent),
        dot(half_vector, binormal),
        dot(half_vector, normal),
    }
    
    diff_y := normalize_or_zero(cross(hw, tangent))
    diff_x := cross(diff_y, hw)
    
    diff_x_inner := dot(diff_x, lw)
    diff_y_inner := dot(diff_y, lw)
    diff_z_inner := dot(hw, lw)
    
    // @speed if needed the trancendental functions could be widened
    f0: lane_f32
    f1: lane_f32
    f2: lane_f32
    for lane in 0..<LaneWidth {
        theta_half := acos(extract(hw.z, lane))
        theta_diff := acos(extract(diff_z_inner, lane))
        phi_diff   := atan2(extract(diff_y_inner, lane), extract(diff_x_inner, lane))
        if phi_diff < 0 do phi_diff += Pi
        
        // @note(viktor): after the divide and clamp any NaNs will be zero in the scalar code, but Intels max_ps/min_ps do not work the same way, so we need to filter them out manually.
        if math.is_nan(theta_half) do theta_half = 0
        if math.is_nan(theta_diff) do theta_diff = 0
        
        replace(&f0, lane, theta_half)
        replace(&f1, lane, theta_diff)
        replace(&f2, lane, phi_diff)
    }
    
    f0 = square_root(clamp_01(f0 / (.5 * Pi)))
    f1 =             clamp_01(f1 / (.5 * Pi))
    f2 =             clamp_01(f2 / (     Pi))
    
    round_positive :: proc ($T: typeid, x: $X) -> T {
        result := cast(T) (x + 0.5)
        return result
    }
    
    brdf  := lane_member(lane_index(materials, index), "brdf", BrdfTable)
    count := lane_gather_v(lane_member(brdf, "count", [3] u32))
    
    i0 := round_positive(lane_u32, f0 * cast(lane_f32) (count[0]-1))
    i1 := round_positive(lane_u32, f1 * cast(lane_f32) (count[1]-1))
    i2 := round_positive(lane_u32, f2 * cast(lane_f32) (count[2]-1))
    
    indices := (i2) + (i1 * count[2]) + (i0 * count[2] * count[1])
    // @todo(viktor): is this still relevant with the Lane ensuring some amount of type safety?
    // @todo(viktor): @important Before indices were interpreted as f32(stride=4), when correcting to v3(stride=12) the color of all surfaces is almost black. is this because i misused the brdfs or picked bad brdfs?
    indices = floor(lane_u32, cast(lane_f32) indices / 3)
    
    values_index := lane_gather(lane_member(brdf, "values_index", u32))
    values_count := lane_gather(lane_member(brdf, "values_count", u32))
    values := lane_slice(all_brdf_values, values_index, values_index+values_count)
    
    value  := lane_index(values, indices)
    result := lane_gather_v(value)
    
    return result
}