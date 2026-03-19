package main

import "base:intrinsics"
import "core:simd"

Triangle :: struct {
    a: v3,
    b: v3,
    c: v3,
}

Ray_Triangle :: struct {
    a, ab, ac: v3,
}

Cast_Result :: struct {
    final_color: v3, 
    bounces_computed, loops_computed: u64,
    
    using tests: Test_Info,
}

Test_Info :: struct {
    rectangles: u64,
    triangles:  u64,
    empty_lanes: [LaneWidth] u32,
}

Hit_Info :: struct {
    closest_t: f32,
    did_hit:   u32,
    triangle:  u32,
}

lane_Node_Index :: #simd [LaneWidth] Node_Index

////////////////////////////////////////////////

Debug_View := 0
Triangle_Threshold  : f32 = 500
Rectangle_Threshold : f32 = 500

Collect_Stats :: true

render_tile :: proc(render: ^Render, camera: Camera, rect: Rectangle2i, entropy: ^RandomSeries) {
    image            := render.image
    models           := render.models
    materials        := render.materials
    brdf_data        := render.brdf_data
    render_stats     := &render.stats
    rays_per_pixel   := render.rays_per_pixel
    max_bounce_count := render.max_bounce_count
    
    
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
    
    total: Test_Info
    bounces_computed, loops_computed: u64
    loop: for py in rect.min.y ..< rect.max.y {
        film_y := -1 + 2 * cast(f32) py / image_size.y
        for px in rect.min.x ..< rect.max.x {
            if render.canceled do break loop
            
            film_x := -1 + 2 * cast(f32) px / image_size.x
            film_p := vec_cast(lane_f32, film_x, film_y)
            
            cast_result := cast_rays(render_stats, models, render.normals, materials, brdf_data, film_p, entropy, pixel_size, half_film_size, film_center, camera, rays_per_pixel, max_bounce_count)
            
            when Collect_Stats {
                total.triangles   += cast_result.triangles
                total.rectangles  += cast_result.rectangles
                total.empty_lanes += cast_result.empty_lanes
            }
            
            bounces_computed += cast_result.bounces_computed
            loops_computed   += cast_result.loops_computed
            
            color := cast_result.final_color
            triangle_color  := (cast(f32) cast_result.triangles  / LaneWidth) / Triangle_Threshold
            rectangle_color := (cast(f32) cast_result.rectangles / LaneWidth) / Rectangle_Threshold
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
            image.data[pixel_index] = pixel
        }
        atomic_add(&render_stats.pixels_done, auto_cast rectangle_get_dimension(rect).x)
    }
    
    atomic_add(&render.stats.triangles,  total.triangles)
    atomic_add(&render.stats.rectangles, total.rectangles)
    for i in 0..<LaneWidth {
        atomic_add(&render_stats.empty_lanes[i], total.empty_lanes[i])
    }
    
    atomic_add(&render_stats.bounces_computed, bounces_computed)
    atomic_add(&render_stats.loops_computed, loops_computed)
    atomic_add(&render_stats.tiles_retired, 1)
}

cast_rays :: proc (stats: ^Render_Stats, models: [] Model, normals: [] [] Triangle_Normals, materials: [] Material, brdf_data: [] v3, init_film_p: lane_v2, entropy: ^RandomSeries,  pixel_size: lane_v2, half_film_size: lane_v2, film_center: lane_v3, camera: Camera, rays_per_pixel, max_bounce_count: u32) -> Cast_Result {
    spall_proc()
    final_color_lanes: lane_v3
    
    bounces_computed_lanes:  lane_u32
    loops_computed_lanes:    lane_u32
    result: Cast_Result
    
    lane_ray_count := rays_per_pixel / LaneWidth
    sample_contribution_factor := 1.0 / cast(f32) rays_per_pixel
    
    camera_p := vec_cast(lane_f32, camera.p)
    camera_x := vec_cast(lane_f32, camera.x)
    camera_y := vec_cast(lane_f32, camera.y)
    
    min_t :: cast(lane_f32) 0.0001
    
    for _ in 0..<lane_ray_count {
        spall_begin("ray generate")
        jitter := random_unilateral(entropy, lane_v2)
        offset := init_film_p + jitter * pixel_size
        film_p := film_center + (offset.x*camera_x*half_film_size.x + offset.y*camera_y * half_film_size.y) 
        
        // @todo(viktor): depth blur can be added here by jittering the ray_o
        ray_o := camera_p
        ray_d := normalize_or_zero(film_p - camera_p)
        spall_end()
        
        attenuation := cast(lane_v3) 1
        lane_mask   := lane_true
        sample: lane_v3
        
        for _ in 0..<max_bounce_count {
            bounces_computed_lanes += 1 & lane_mask
            loops_computed_lanes   += 1
            
            ////////////////////////////////////////////////
            
            hits: [LaneWidth] Hit_Info
            model_index: lane_u32
            
            lane_hits := to_lane_wide(&hits)
            lane_scatter(lane_member(lane_hits, "closest_t", f32), cast(lane_f32) +Infinity)
            
            for model, index in models {
                spall_scope("hit model")
                
                translation := vec_cast(lane_f32, model.translation)
                model_ray_o := ray_o - translation
                model_ray_d := ray_d
                
                hit_mask, tests := traverse_tree_and_test_triangles(model.ray_triangles, model.tree, model_ray_o, model_ray_d, min_t, &hits)
                
                conditional_assign(hit_mask, &model_index, cast(lane_u32) index)
                
                when Collect_Stats {
                    result.triangles   += tests.triangles
                    result.rectangles  += tests.rectangles
                    result.empty_lanes += tests.empty_lanes
                }
            }
            
            ////////////////////////////////////////////////
            // @todo(viktor): Importance Sampling
            // sort models my material emitance strength / store all materials with emitance separately
            // besides the normal ray, also cast a "shadow ray"
            // select a random emitting model and a random triangle in that model (weighting?)
            // select a random point on that triangle and traverse this ray aswell
            //   always keep a shadow ray besides ray_o, ray_d
            //   always trace both ray and shadow ray for each model
            // combine contribution of ray and shadow ray(only if next_o == ~triangle point if it reaches the light?)
            //   scale shadow ray by G = dot(normalize(-ray_d), t_normal) / length_squared(ray_d)
            //   scale by probablity-distribution-function: 1 / (P(model) * P(triangle) * P(area))
            // balance heuristic: 
            //   
            spall_begin("ray color accumulation")
            hit_did_hit := lane_gather(lane_member(lane_hits, "did_hit", u32))
            
            model           := lane_index(to_lane(models), model_index)
            material_index  := lane_gather(lane_member(model, "material", u32), hit_did_hit, cast(lane_u32) 0)
            
            materials       := to_lane(materials)
            material        := lane_index(materials, material_index)
            hit_emit        := lane_gather_v(lane_member(material, "emit",        v3))
            hit_emit_factor := lane_gather(  lane_member(material, "emit_factor", f32))
            hit_emit        *= hit_emit_factor
            
            ////////////////////////////////////////////////
            // only allow world.no_hit on the first time we didn't hit anything
            hit_emit *= cast(lane_f32) (1 & lane_mask)
            
            // fma
            sample += attenuation * hit_emit
            
            lane_mask &= hit_did_hit
            spall_end()
            if lane_mask == lane_false do break
            
            ////////////////////////////////////////////////
            spall_scope("ray reflection")
            
            // @cleanup
            hit_normal:   lane_v3
            hit_tangent:  lane_v3
            hit_binormal: lane_v3
            for lane in 0..<LaneWidth {
                triangle_index := hits[lane].triangle
                model_index    := extract(model_index, lane)
                
                it := normals[model_index][triangle_index]
                replace_v3(&hit_normal,   lane, it.normal)
                replace_v3(&hit_tangent,  lane, it.tangent)
                replace_v3(&hit_binormal, lane, it.binormal)
            }
            
            hit_scatter := lane_gather(lane_member(material, "scatter", f32))
            
            pure_bounce   := reflect(ray_d, hit_normal)
            random_bounce := normalize_or_zero(hit_normal + random_bilateral(entropy, lane_v3))
            
            next_d := linear_blend(pure_bounce, random_bounce, hit_scatter)
            
            ////////////////////////////////////////////////
            reflectance := brdf_lookup(brdf_data, material, -ray_d, hit_normal, hit_tangent, hit_binormal, next_d)
            
            ////////////////////////////////////////////////
            hit_reflect := lane_gather_v(lane_member(material, "reflect", v3))
            hit_reflect *= reflectance
            conditional_assign(hit_did_hit, &attenuation, attenuation * hit_reflect)
            
            ////////////////////////////////////////////////
            // @note(viktor): no need to translate the ray back as we only need hit_t, 
            // which is a vector and does not care about translations. Once we have a 
            // full transform with scale and rotation, we only need to apply scaling 
            // to hit_t, as rotation is handle on the forward_transform in the hit tests.
            
            hit_t := lane_gather(lane_member(lane_hits, "closest_t", f32))
            // fma
            ray_o = ray_o + hit_t * ray_d
            ray_d = next_d
        }
        
        // fma
        final_color_lanes += sample_contribution_factor * sample
    }
    
    result.final_color.r = horizontal_add(final_color_lanes.r)
    result.final_color.g = horizontal_add(final_color_lanes.g)
    result.final_color.b = horizontal_add(final_color_lanes.b)
    
    result.bounces_computed  = cast(u64) horizontal_add(bounces_computed_lanes)
    result.loops_computed    = cast(u64) horizontal_add(loops_computed_lanes)
    
    return result
}

////////////////////////////////////////////////

traverse_tree_and_test_triangles :: proc (triangles: [] Ray_Triangle, tree: [] Tree_Node, init_ray_o, init_ray_d: lane_v3, min_t: lane_f32, hits: ^[LaneWidth] Hit_Info) -> (lane_u32, Test_Info) {
    spall_proc()
    
    Check :: false
    
    lane_hits := lane_index(to_lane(hits[:]), lane_offset)
    closest_t := lane_gather(lane_member(lane_hits, "closest_t", f32))
    
    // @naming
    init_inv_d     := 1 / init_ray_d
    init_neg_inv_o := -init_ray_o * init_inv_d
    
    hit_mask: lane_u32
    info:     Test_Info
    {
        root := tree[Root_Index]
        min := vec_cast(lane_f32, root.bounds.min)
        max := vec_cast(lane_f32, root.bounds.max)
        
        hit_mask = hit_rectangle(min, max, init_neg_inv_o, init_inv_d, min_t, closest_t)
        when Collect_Stats {
            info.rectangles += LaneWidth
        }
    }
    
    if hit_mask == lane_false do return hit_mask, info
    ////////////////////////////////////////////////
    
    triangles := to_lane(triangles)
    tree_lane := to_lane(tree)
    // @cleanup make this offset a lane_op
    tree_lane.p += cast(lane_umm) lane_offset * size_of(tree[0])
    
    backing: [Tree_Max_Depth] Node_Index
    stack := backing[:]
    
    for lane in 0..<LaneWidth {
        spall_scope("traverse_tree_and_test_triangles lane")
        if extract(hit_mask, lane) == 0 do continue
        
        hit := &hits[lane]
        // @waste
        lane_ray_d     := extract_v3(init_ray_d, lane)
        lane_ray_o     := extract_v3(init_ray_o, lane)
        lane_inv_d     := extract_v3(init_inv_d, lane)
        lane_neg_inv_o := extract_v3(init_neg_inv_o, lane)
        ray_o     := vec_cast(lane_f32, lane_ray_o)
        ray_d     := vec_cast(lane_f32, lane_ray_d)
        inv_d     := vec_cast(lane_f32, lane_inv_d)
        neg_inv_o := vec_cast(lane_f32, lane_neg_inv_o)
        
        backing[0] = Root_Index
        
        stack_count := cast(u32) 1
        for stack_count != 0 {
            stack_count -= 1
            it_index := stack[stack_count]
            node := &tree[it_index]
            
            if node.value_count == 0 {
                indices  := cast(lane_u32) node.first.subnode
                subnodes := lane_index(tree_lane, indices)
                
                // @waste if subnodes are always LaneWidth, why not store min,max of them as lane_v3?
                bounds   := lane_member(subnodes, "bounds", Rectangle3)
                node_min := lane_member(bounds, "min", v3)
                node_max := lane_member(bounds, "max", v3)
                
                min := lane_gather_v(node_min)
                max := lane_gather_v(node_max)
                
                bounds_hit_mask := hit_rectangle(min, max, neg_inv_o, inv_d, min_t, hit.closest_t)
                when Collect_Stats {
                    info.rectangles += Subnodes_Per_Node
                }
                if bounds_hit_mask == lane_false do continue
                
                // @note(viktor): the last tests showed that the sorting overhead was not worth the gains it should have provided
                subnode_indices := cast(lane_u32) node.first.subnode + lane_offset
                // @note(viktor): this will be a loop unless AVX-512 is available, where it is one instruction with a few cycles of latency
                simd.masked_compress_store(&stack[stack_count], subnode_indices, bounds_hit_mask)
                stack_count += horizontal_add(1 & bounds_hit_mask)
            } else {
                end := cast(u32) node.first.value + node.value_count
                full_end := end - (node.value_count % LaneWidth)
                
                spall_begin("values full")
                values: for value_index := cast(u32) node.first.value; value_index < full_end; value_index += LaneWidth {
                    triangle_index := value_index + lane_offset
                    triangle := lane_index(triangles, triangle_index)
                    
                    triangle_hit_mask, triangle_t := hit_triangle(lane_true, triangle, ray_o, ray_d, min_t, cast(lane_f32) hit.closest_t)
                    if triangle_hit_mask == lane_false do continue values
                    
                    // @waste should just return Infinity? but what about the last calculation of t?
                    masked_t   := simd.select(triangle_hit_mask, triangle_t, cast(lane_f32) +Infinity)
                    closest_t  := simd.reduce_min(masked_t)
                    is_closest := equal(triangle_t, cast(lane_f32) closest_t) & triangle_hit_mask
                    high_bits  := cast(u32) transmute(u8) simd.extract_msbs(is_closest)
                    closest_lane := simd.count_trailing_zeros(high_bits)
                    
                    hit.closest_t = closest_t
                    hit.did_hit   = 0xffff_ffff
                    hit.triangle  = value_index + closest_lane
                }
                spall_end()
                
                spall_begin("values masked")
                tail: if value_index := full_end; value_index < end {
                    triangle_index := value_index + lane_offset
                    triangle := lane_index(triangles, triangle_index)
                    mask     := less_than(triangle_index, cast(lane_u32) end)
                    
                    triangle_hit_mask, triangle_t := hit_triangle(mask, triangle, ray_o, ray_d, min_t, cast(lane_f32) hit.closest_t)
                    if triangle_hit_mask == lane_false do break tail
                    
                    // @copypasta from loop
                    // @waste should just return Infinity? but what about the last calculation of t?
                    masked_t   := simd.select(triangle_hit_mask, triangle_t, cast(lane_f32) +Infinity)
                    closest_t  := simd.reduce_min(masked_t)
                    is_closest := equal(triangle_t, cast(lane_f32) closest_t) & triangle_hit_mask
                    high_bits  := cast(u32) transmute(u8) simd.extract_msbs(is_closest)
                    closest_lane := simd.count_trailing_zeros(high_bits)
                    
                    hit.closest_t = closest_t
                    hit.did_hit   = 0xffff_ffff
                    hit.triangle  = value_index + closest_lane
                }
                spall_end()
                
                when Collect_Stats {
                    info.triangles += cast(u64) node.value_count
                    
                    full      := node.value_count / LaneWidth
                    remaining := node.value_count % LaneWidth
                    
                    info.empty_lanes[0] += full * LaneWidth
                    if remaining != 0 do info.empty_lanes[LaneWidth - remaining] += 1
                }
            }
        }
    }
    
    t_after  := lane_gather(lane_member(lane_hits, "closest_t", f32))
    hit_mask &= less_than(t_after, closest_t)
    
    return hit_mask, info
}

////////////////////////////////////////////////

hit_rectangle :: proc (min, max: lane_v3, neg_inv_o, inv_d: lane_v3, t_min_init, t_max_init: lane_f32) -> lane_u32 {
    t1x := fused_mul_add(min.x, inv_d.x, neg_inv_o.x)
    t2x := fused_mul_add(max.x, inv_d.x, neg_inv_o.x)
    
    t1y := fused_mul_add(min.y, inv_d.y, neg_inv_o.y)
    t2y := fused_mul_add(max.y, inv_d.y, neg_inv_o.y)
    
    t1z := fused_mul_add(min.z, inv_d.z, neg_inv_o.z)
    t2z := fused_mul_add(max.z, inv_d.z, neg_inv_o.z)
    
    tin := lane_v3 { minimum(t1x, t2x), minimum(t1y, t2y), minimum(t1z, t2z) }
    tax := lane_v3 { maximum(t1x, t2x), maximum(t1y, t2y), maximum(t1z, t2z) }
    
    tmin := maximum(maximum(t_min_init, tin.x), maximum(tin.y, tin.z))
    tmax := minimum(minimum(t_max_init, tax.x), minimum(tax.y, tax.z))
    
    result := less_equal(tmin, tmax)
    return result
}

// @speed measure branch mispredictions: do i also have an unpredictable branch in these u/v test, because each part is unpredictable but the whole expression should be predicted as false?
hit_triangle :: proc (not_nil_mask: lane_u32, triangle: Lane(Ray_Triangle), ray_o, ray_d: lane_v3, min_t: lane_f32, max_t: lane_f32) -> (lane_u32, lane_f32) {
    Check :: false
    when Check do assert(not_nil_mask != lane_false)
    
    a  := lane_gather_v(lane_member(triangle, "a",  v3), not_nil_mask, lane_v3{})
    ab := lane_gather_v(lane_member(triangle, "ab", v3), not_nil_mask, lane_v3{})
    ac := lane_gather_v(lane_member(triangle, "ac", v3), not_nil_mask, lane_v3{})
    
    ray_cross_ac := cross(ray_d, ac)
    determinant  := dot(ab, ray_cross_ac)
    
    hit_mask := not_nil_mask
    hit_t := cast(lane_f32) +Infinity
    
    hit_mask &= greater_than(absolute(determinant), 1e-6)
    if hit_mask == lane_false do return hit_mask, hit_t
    
    inv_determinant := 1.0 / determinant
    s := ray_o - a
    u := inv_determinant * dot(s, ray_cross_ac)
    
    hit_mask &= greater_equal(u, 0) & less_equal(u, 1)
    if hit_mask == lane_false do return hit_mask, hit_t
    
    s_cross_ab := cross(s, ab)
    v := inv_determinant * dot(ray_d, s_cross_ab)
    
    hit_mask &= greater_equal(v, 0) & less_equal(u + v, 1)
    if hit_mask == lane_false do return hit_mask, hit_t
    
    hit_t = inv_determinant * dot(ac, s_cross_ab)
    hit_mask &= greater_than(hit_t, min_t) & less_than(hit_t, max_t)
    
    return hit_mask, hit_t
}