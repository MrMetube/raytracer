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
        temp_values := slice_from_parts(f64, &data[0], total_count * len(v3))
        
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
            
            // @note(viktor): a value of -1 indicates that the reflection would be below the horizon
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
Triangle_Threshold  : f32 = 500
Rectangle_Threshold : f32 = 1000

render_tile :: proc(render_stats: ^Render_Stats, models: [] Model, materials: [] Material, brdf_data: [] v3, camera: Camera, image: Image, rect: Rectangle2i, entropy: ^RandomSeries, rays_per_pixel, max_bounce_count: u32) {
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
            
            cast_info := cast_rays(render_stats, models, materials, brdf_data, film_p, entropy, pixel_size, half_film_size, film_center, camera, rays_per_pixel, max_bounce_count)
            
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
        atomic_add(&render_stats.pixels_done, auto_cast rectangle_get_dimension(rect).x)
    }
    
    atomic_add(&render_stats.bounces_computed, bounces_computed)
    atomic_add(&render_stats.loops_computed, loops_computed)
    atomic_add(&render_stats.tiles_retired, 1)
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

cast_rays :: proc (stats: ^Render_Stats, models: [] Model, materials: [] Material, brdf_data: [] v3, init_film_p: lane_v2, entropy: ^RandomSeries,  pixel_size: lane_v2, half_film_size: lane_v2, film_center: lane_v3, camera: Camera, rays_per_pixel, max_bounce_count: u32) -> Cast_Info {
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
            
            for model in models {
                triangles := model.triangles
                nodes     := model.tree
                
                if len(nodes) == 0 || len(triangles) == 0 do continue
                
                if Use_Tree {
                    local_nil_value_lanes_tested: [LaneWidth] u32
                    
                    traverse_tree_and_collect_values(to_lane(triangles), nodes[:], ray_o, ray_d, min_t, &hit, &local_nil_value_lanes_tested, &triangles_tested_lanes, &rectangles_tested_lanes)
                    
                    for i in 0..<len(stats.nil_value_lanes_tested) {
                        atomic_add(&stats.nil_value_lanes_tested[i], local_nil_value_lanes_tested[i])
                    }
                } else {
                    for index in 0 ..< cast(Value_Index) len(triangles) {
                        triangles := to_lane(triangles)
                        triangle := lane_index(triangles, cast(lane_u32) index)
                        hit_triangle(lane_true, triangle, ray_o, ray_d, min_t, &hit)
                    }
                    stat_update(&triangle_tests, cast(u32) len(triangles) * LaneWidth)
                    stat_update(&all_triangle_tests, cast(u32) len(triangles) * LaneWidth)
                }
            }
            
            ////////////////////////////////////////////////
            
            materials := to_lane(materials)
            brdf_data := to_lane(brdf_data)
            
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
            
            reflectance := brdf_lookup(brdf_data, materials, hit.material, -ray_d, hit.normal, hit.tangent, hit.binormal, next_d)
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
    
    atomic_add(&stats.all_triangle_tests.count, all_triangle_tests.count)
    atomic_add(&stats.all_triangle_tests.sum,   all_triangle_tests.sum)
    atomic_add(&stats.triangle_tests.count, triangle_tests.count)
    atomic_add(&stats.triangle_tests.sum,   triangle_tests.sum)
    
    return result
}

////////////////////////////////////////////////

traverse_tree_and_collect_values :: proc (triangles: Lane_Slice(Triangle), tree: [] Tree_Node, ray_o, ray_d: lane_v3, min_t: lane_f32, hit: ^Hit_Info, local_nil_value_lanes_tested: ^[LaneWidth] u32, triangles_tested_lanes, rectangles_tested_lanes: ^lane_u32) {
    spall_proc()
    
    inv_d := 1 / ray_d
    neg_inv_o := -(ray_o * inv_d)
    
    // @volatile max tree depth
    backing: [64] Node_Index
    backing[0] = Root_Index
    
    stack_count := cast(u32) 1
    stack := backing[:]
    
    for lane in 0..<LaneWidth {
        spall_begin("lane extract")
        inv_d     := extract_v3(inv_d, lane)
        neg_inv_o := extract_v3(neg_inv_o, lane)
        lane_inv_d := vec_cast(lane_f32, inv_d)
        lane_neg_inv_o := vec_cast(lane_f32, neg_inv_o)
        
        ray_d     := extract_v3(ray_d, lane)
        ray_o     := extract_v3(ray_o, lane)
        lane_ray_d := vec_cast(lane_f32, ray_d)
        lane_ray_o := vec_cast(lane_f32, ray_o)
        
        lane_hit: Hit_Info
        lane_hit.closest_t =     cast(lane_f32) extract(hit.closest_t, lane)
        lane_hit.did_hit   =     cast(lane_u32) extract(hit.did_hit,   lane)
        lane_hit.material  =     cast(lane_u32) extract(hit.material,  lane)
        lane_hit.next_o    = vec_cast(lane_f32, extract_v3(hit.next_o,    lane))
        lane_hit.normal    = vec_cast(lane_f32, extract_v3(hit.normal,    lane))
        lane_hit.tangent   = vec_cast(lane_f32, extract_v3(hit.tangent,   lane))
        lane_hit.binormal  = vec_cast(lane_f32, extract_v3(hit.binormal,  lane))
        spall_end()
        
        stack[0] = Root_Index
        stack_count = 1
        
        spall_begin("traversal")
        for stack_count != 0 {
            stack_count -= 1
            it_index := stack[stack_count]
            node := &tree[it_index]
            
            if node.value_count == 0 {
                spall_scope("subnodes")
                
                indices  := cast(lane_u32) node.first.subnode + lane_offset
                subnodes := lane_index(to_lane(tree), indices)
                
                // @todo(viktor): is this needed? isnt it already done after hit triangle tests?
                closest_t := simd.reduce_min(lane_hit.closest_t)
                
                hit_mask, tmin := hit_rectangle(subnodes, lane_neg_inv_o, lane_inv_d, min_t, closest_t)
                rectangles_tested_lanes^ += Subnodes_Per_Node
                    
                if hit_mask != lane_false {
                    tt := simd.to_array(tmin)
                    index: [LaneWidth] u32 = max(u32)
                    sorted := cast(lane_f32) +Infinity
                    
                    for t, ti in tt {
                        if extract(hit_mask, ti) != 0 {
                            // t  = 5
                            // at = 2
                            //      2 4 5 8
                            // gt = 1 1 0 0 
                            greater_count := horizontal_add(1 & greater_equal(cast(lane_f32) t, sorted))
                            
                            simd_insert_at :: proc (vector: $V/ #simd[$N] $T, value: T, #any_int index: u32) -> V {
                                rotate :: simd.lanes_rotate_right
                                result := transmute(lane_u32) vector            &    less_than(lane_offset, cast(lane_u32) index) 
                                result |= transmute(lane_u32) (cast(V) value)   &        equal(lane_offset, cast(lane_u32) index)
                                result |= transmute(lane_u32) rotate(vector, 1) & greater_than(lane_offset, cast(lane_u32) index)
                                return transmute(V) result
                            }
                            
                            sorted = simd_insert_at(sorted, t, greater_count)
                            index  = transmute([8] u32) simd_insert_at(transmute(lane_u32) index,  cast(u32) ti, greater_count)
                        }
                    }
                    
                    when false {
                        hit_count := horizontal_add(hit_mask & 1)
                        for i in 0..<LaneWidth-1 {
                            if i < auto_cast hit_count {
                                assert(sorted[i] <= sorted[i+1])
                            }
                        }
                    }
                    
                    for i in index {
                        if i != max(u32) && extract(hit_mask, i) != 0 {
                            subindex := node.first.subnode + cast(Node_Index) i
                            stack[stack_count] = subindex
                            stack_count += 1
                        }
                    }
                }
            } else {
                spall_scope("values")
                
                spall_begin("triangle loop")
                start := cast(u32) node.first.value
                end   := cast(u32) node.first.value + node.value_count
                
                for value_index := start; value_index < (end + LaneWidth); value_index += LaneWidth {
                    index := value_index + lane_offset
                    value_mask := less_than(index, cast(lane_u32) end)
                    triangle := lane_index(triangles, index)
                    hit_triangle(value_mask, triangle, lane_ray_o, lane_ray_d, min_t, &lane_hit)
                }
                spall_end()
                
                spall_begin("triangle reduce")
                closest_t := +Infinity
                closest_triangle_lane := -1
                for x in 0..<LaneWidth {
                    triangle_t := extract(lane_hit.closest_t, x)
                    if closest_t > triangle_t {
                        closest_t = triangle_t
                        closest_triangle_lane = x
                    }
                }
                
                lane_hit.closest_t = extract(lane_hit.closest_t,   closest_triangle_lane)
                lane_hit.did_hit   = extract(lane_hit.did_hit,     closest_triangle_lane)
                lane_hit.material  = extract(lane_hit.material,    closest_triangle_lane)
                lane_hit.next_o    = vec_cast(lane_f32, extract_v3(lane_hit.next_o,   closest_triangle_lane))
                lane_hit.normal    = vec_cast(lane_f32, extract_v3(lane_hit.normal,   closest_triangle_lane))
                lane_hit.tangent   = vec_cast(lane_f32, extract_v3(lane_hit.tangent,  closest_triangle_lane))
                lane_hit.binormal  = vec_cast(lane_f32, extract_v3(lane_hit.binormal, closest_triangle_lane))
                spall_end()
                
                triangles_tested_lanes^ += (node.value_count) & equal(lane_offset, cast(lane_u32) lane)
                local_nil_value_lanes_tested[0] += (node.value_count / LaneWidth) * LaneWidth
                remainder := node.value_count % LaneWidth
                if remainder != 0 {
                    local_nil_value_lanes_tested[8 - remainder] += 1
                }
            }
        }
        spall_end()
        
        min_lane: int = -1
        min_closest_t := extract(hit.closest_t, lane)
        if greater_equal(lane_hit.closest_t, cast(lane_f32) min_closest_t) == lane_true do continue
        
        spall_begin("lane replace")
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
    
    not_parallel_mask := greater_than(absolute(determinant), 1e-6)
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