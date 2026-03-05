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

Sphere :: struct {
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

Debug_View := 1
Test_Threshold : f32 = 2000

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
            
            color, bounces_now, loops_now, tests_now := cast_rays(world, film_p, entropy, pixel_size, half_film_size, film_center, camera, rays_per_pixel, max_bounce_count)
            
            bounces_computed += bounces_now
            loops_computed   += loops_now
            
            color = linear_to_srgb(color)
            if Debug_View == 1 {
                tests := cast(f32) tests_now / LaneWidth
                color = tests / Test_Threshold
                if tests > Test_Threshold {
                    color = v3{1, 0, 0}
                }
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

cast_rays :: proc (world: ^World, init_film_p: lane_v2, entropy: ^RandomSeries,  pixel_size: lane_v2, half_film_size: lane_v2, film_center: lane_v3, camera: Camera, rays_per_pixel, max_bounce_count: u32) -> (final_color: v3, bounces_computed, loops_computed, triangles_tested: u64) {
    spall_proc()
    final_color_lanes: lane_v3
    
    bounces_computed_lanes: lane_u32
    loops_computed_lanes:   lane_u32
    triangles_tested_lanes: lane_u32
    
    lane_ray_count := rays_per_pixel / LaneWidth
    sample_contribution_factor := 1.0 / cast(f32) rays_per_pixel
    
    camera_p := vec_cast(lane_f32, camera.p)
    camera_x := vec_cast(lane_f32, camera.x)
    camera_y := vec_cast(lane_f32, camera.y)
    
    backing_values: [4096] [LaneWidth] Value_Index
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
                values_len := traverse_tree_and_collect_values(values[:], nodes[:], ray_o, ray_d, min_t, hit.closest_t)
                
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
                    for n in 0..<LaneWidth {
                        t := extract(lane_hit.closest_t, n)
                        if min_closest_t > t {
                            min_closest_t = t
                            min_lane = n
                        }
                    }
                    
                    if min_lane != -1 {
                        replace(&hit.closest_t,   lane, extract(lane_hit.closest_t, min_lane))
                        replace(&hit.did_hit,     lane, extract(lane_hit.did_hit, min_lane))
                        replace(&hit.material,    lane, extract(lane_hit.material, min_lane))
                        replace_v3(&hit.next_o,   lane, extract_v3(lane_hit.next_o, min_lane))
                        replace_v3(&hit.normal,   lane, extract_v3(lane_hit.normal, min_lane))
                        replace_v3(&hit.tangent,  lane, extract_v3(lane_hit.tangent, min_lane))
                        replace_v3(&hit.binormal, lane, extract_v3(lane_hit.binormal, min_lane))
                    }
                }
                
                spall_end()
                
                // @speed this is a serial dependency chain on hit, measure if this is relevant.
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
                
                local_nil_value_lanes_tested[0] += min_len
                
                for i in 0..<len(world.nil_value_lanes_tested) {
                    atomic_add(&world.nil_value_lanes_tested[i], local_nil_value_lanes_tested[i])
                }
                spall_end()
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
            
            if Use_Tree {
                local_nil_value_lanes_tested: [LaneWidth] u32
                
                nodes := world.sphere_nodes
                values_len := traverse_tree_and_collect_values(values[:], nodes[:], ray_o, ray_d, min_t, hit.closest_t)
                
                for lane in 0..<LaneWidth {
                    values_len := extract(values_len, lane)
                    for values_len != 0 {
                        values_len -= 1
                        
                        value_index := values[values_len][lane]
                        value := &world.spheres[value_index]
                        hit_sphere(to_lane(value), ray_o, ray_d, min_t, &hit)
                    }
                }
                
                for i in 0..<len(local_nil_value_lanes_tested) {
                    atomic_add(&world.nil_value_lanes_tested[i], local_nil_value_lanes_tested[i])
                }
            } else {
                spheres := to_lane(world.spheres) // @cleanup
                for index in 0 ..< cast(u32) len(world.spheres) {
                    sphere := lane_index(spheres, index)
                    hit_sphere(sphere, ray_o, ray_d, min_t, &hit)
                }
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
    
    final_color.r = horizontal_add(final_color_lanes.r)
    final_color.g = horizontal_add(final_color_lanes.g)
    final_color.b = horizontal_add(final_color_lanes.b)
    
    bounces_computed = cast(u64) horizontal_add(bounces_computed_lanes)
    loops_computed   = cast(u64) horizontal_add(loops_computed_lanes)
    triangles_tested = cast(u64) horizontal_add(triangles_tested_lanes)
    
    atomic_add(&world.all_triangle_tests.count, all_triangle_tests.count)
    atomic_add(&world.all_triangle_tests.sum,   all_triangle_tests.sum)
    atomic_add(&world.triangle_tests.count, triangle_tests.count)
    atomic_add(&world.triangle_tests.sum,   triangle_tests.sum)
    
    return final_color, bounces_computed, loops_computed, triangles_tested
}

////////////////////////////////////////////////

traverse_tree_and_collect_values :: proc (values: [] [LaneWidth] Value_Index, nodes: [] Tree_Node, ray_o, ray_d: lane_v3, min_t, max_t: lane_f32) -> (values_len: lane_u32) {
    if tree_is_empty(nodes) do return
    spall_proc()
    
    nodes  := to_lane(nodes)
    values := to_lane(values)
    
    inv_d := 1 / ray_d
    neg_inv_o := -(ray_o * inv_d)
    
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
        min  := lane_gather_v(lane_member(node, "bounds", "min", v3))
        max  := lane_gather_v(lane_member(node, "bounds", "max", v3))
        
        // @todo(viktor): ensure there is no gap between the subnode bounds, otherwise we need to add an epsilon here
        hit_mask, _ := hit_rectangle(neg_inv_o, inv_d, min, max, min_t, max_t)
        if hit_mask == lane_false do continue
        
        first_subnode := lane_gather(lane_member(node, "first_subnode", Node_Index))
        
        append_mask := hit_mask
        append_mask &= not_equal(cast(lane_u32) first_subnode, Nil_Index)
        if append_mask != lane_false {
            x0 := lane_index(lane_index(stack, stack_count+0), lane_offset)
            x1 := lane_index(lane_index(stack, stack_count+1), lane_offset)
            lane_scatter(x0, first_subnode+0, append_mask)
            lane_scatter(x1, first_subnode+1, append_mask)
            conditional_assign(append_mask, &stack_count, stack_count+2)
        }
        
        first_value := lane_gather_mask(lane_member(node, "first_value", Value_Index), hit_mask, 0)
        value_count := lane_gather_mask(lane_member(node, "value_count", u16), hit_mask, 0)
        
        value_index := first_value
        end         := first_value + cast(lane_Value_Index) value_count
        
        for {
            value_mask := less_than(value_index, end)
            if value_mask == 0 do break
            
            values_end := lane_index(values, values_len)
            lane_scatter(values_end, lane_offset, value_index, value_mask)
            
            conditional_assign(value_mask, &values_len,  values_len+1)
            conditional_assign(value_mask, &value_index, value_index+1)
        }
    }
    
    return values_len
}

////////////////////////////////////////////////

hit_rectangle :: proc (neg_inv_o, inv_d: lane_v3, min, max: lane_v3, t_min_init, t_max_init: lane_f32) -> (lane_u32, lane_f32) {
    spall_proc()
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
    
    result := less_equal(tmin, tmax)
    
    return result, tmax
}

hit_triangle :: proc (not_nil_mask: lane_u32, triangle: Lane(Triangle), ray_o, ray_d: lane_v3, min_t: lane_f32, hit: ^Hit_Info) {
    spall_proc()
    
    Check :: false
    when Check do assert(not_nil_mask != lane_false)
    
    a        := lane_gather_v(lane_member(triangle, "a", v3), not_nil_mask, lane_v3{})
    b        := lane_gather_v(lane_member(triangle, "b", v3), not_nil_mask, lane_v3{})
    c        := lane_gather_v(lane_member(triangle, "c", v3), not_nil_mask, lane_v3{})
    material := lane_gather(  lane_member(triangle, "material", u32), not_nil_mask, lane_u32{})
    
    // @speed pre-compute ab and ac? 
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
    if u_mask== lane_false do return
    
    s_cross_ab := cross(s, ab)
    v := inv_determinant * dot(ray_d, s_cross_ab)
    
    v_mask := greater_equal(v, 0) & less_equal(u + v, 1)
    v_mask &= u_mask
    if v_mask == lane_false do return
    
    t := inv_determinant * dot(ac, s_cross_ab)
    hit_mask := greater_than(t, min_t) & less_than(t, hit.closest_t)
    hit_mask &= v_mask
    if hit_mask == lane_false do return
    
    // @note(viktor): Assuming counter-clockwise winding order
    normal   := normalize_or_zero(cross(ab, ac))
    tangent  := normalize_or_zero(ab)
    binormal := normalize_or_zero(cross(normal, tangent))
    
    update_hit(hit, hit_mask, t, material, ray_o + t*ray_d, normal, tangent, binormal)
}

hit_sphere :: proc (sphere: Lane(Sphere), ray_o, ray_d: lane_v3, min_t: lane_f32, hit: ^Hit_Info) {
    // @note(viktor): if sphere_index == 0 its the Nil sphere
    // then the root will be NaN making the t_mask zero, so no hit can be registered
    center   := lane_gather_v(lane_member(sphere, "center",   v3))
    radius   := lane_gather(  lane_member(sphere, "radius",   f32))
    material := lane_gather(  lane_member(sphere, "material", u32))
    
    local_origin := ray_o - center
    a := dot(ray_d, ray_d)
    b := 2 * dot(local_origin, ray_d)
    c := dot(local_origin, local_origin) - square(radius)
    root_term := square(b) - 4*a*c
    root := square_root(root_term)
    root_mask := greater_equal(root_term, 0)
    if root_mask == lane_false do return
    
    t_pos := (-b + root) / (2 * a)
    t_neg := (-b - root) / (2 * a)
    
    t := t_pos
    pick_mask := greater_than(t_neg, min_t) & less_than(t_neg, t)
    conditional_assign(pick_mask, &t, t_neg)
    
    hit_mask := greater_than(t, min_t) & less_than(t, hit.closest_t)
    hit_mask &= root_mask
    if hit_mask == lane_false do return
    
    next_o := ray_o + t*ray_d
    normal   := normalize_or_zero(next_o - center)
    tangent  := normalize_or_zero(cross(lane_v3{0, 0, 1}, normal))
    binormal := cross(normal, tangent)
    
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
    spall_proc()
    
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