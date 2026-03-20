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

// @todo(viktor): lane_Transform?
lane_Camera :: struct {
    x,y,z,p: lane_v3,
}

////////////////////////////////////////////////

Debug_View_Kind :: enum {
    Color,
    Triangle_Tests,
    Rectangle_Tests,
    Both_Tests,
    Normals,
    Tangents,
    Binormals,
}
Debug_View: Debug_View_Kind
Triangle_Threshold  : f32 = 500
Rectangle_Threshold : f32 = 500

Collect_Stats :: true

render_tile :: proc(render: ^Render, camera: lane_Camera, rect: Rectangle2i, entropy: ^RandomSeries) {
    image            := render.image
    models           := render.models
    materials        := render.materials
    brdf_data        := render.brdf_data
    render_stats     := &render.stats
    rays_per_pixel   := render.rays_per_pixel
    max_bounce_count := render.max_bounce_count
    
    film_distance :: 1
    film_center := camera.p - film_distance * camera.z
    
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
    pixels: for py in rect.min.y ..< rect.max.y {
        film_y := linear_blend(cast(f32) -1, 1, cast(f32) py / image_size.y)
        for px in rect.min.x ..< rect.max.x {
            if render.canceled do break pixels
            
            film_x := linear_blend(cast(f32) -1, 1, cast(f32) px / image_size.x)
            film_p := vec_cast(lane_f32, film_x, film_y)
            
            cast_result := cast_rays(models, materials, brdf_data, film_p, entropy, pixel_size, half_film_size, film_center, camera, rays_per_pixel, max_bounce_count)
            
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
            if Debug_View == .Triangle_Tests {
                color = triangle_color
                if triangle_color > 1 do color = v3{1, 0, 0}
            } else if Debug_View == .Rectangle_Tests {
                color = rectangle_color
                if rectangle_color > 1 do color = v3{1, 0, 0}
            } else if Debug_View == .Both_Tests {
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

cast_rays :: proc (models: [] MModel, materials: [] Material, brdf_data: [] v3, init_film_p: lane_v2, entropy: ^RandomSeries,  pixel_size: lane_v2, half_film_size: lane_v2, film_center: lane_v3, camera: lane_Camera, rays_per_pixel, max_bounce_count: u32) -> Cast_Result {
    final_color_lanes: lane_v3
    
    bounces_computed_lanes:  lane_u32
    loops_computed_lanes:    lane_u32
    result: Cast_Result
    
    lane_ray_count := rays_per_pixel / LaneWidth
    sample_contribution_factor := 1.0 / cast(f32) rays_per_pixel
    
    min_t :: cast(lane_f32) 0.0001
    
    for _ in 0..<lane_ray_count {
        spall_begin("ray generate")
        jitter := random_unilateral(entropy, lane_v2)
        offset := init_film_p + jitter * pixel_size
        film_p := film_center + (offset.x * camera.x * half_film_size.x + offset.y * camera.y * half_film_size.y) 
        
        // @todo(viktor): depth blur can be added here by jittering the ray_o
        ray_o := camera.p
        ray_d := normalize_or_zero(film_p - camera.p)
        spall_end()
        
        attenuation := cast(lane_v3) 1
        lane_mask   := lane_true
        sample: lane_v3
        
        bounces: for _ in 0..<max_bounce_count {
            bounces_computed_lanes += 1 & lane_mask
            loops_computed_lanes   += 1
            
            ////////////////////////////////////////////////
            
            hits: [LaneWidth] Hit_Info
            model_index: lane_u32
            
            lane_hits := to_lane_wide(&hits)
            lane_scatter(lane_member(lane_hits, "closest_t", f32), cast(lane_f32) +Infinity)
            
            spall_begin("hit models")
            for model, index in models {
                spall_begin("world to model")
                model_ray_o := apply_transform(model.inverse, ray_o, 1)
                model_ray_d := apply_transform(model.inverse, ray_d, 0)
                spall_end()
                
                hit_mask, tests := hit_tree(model.triangles, model.tree, model_ray_o, model_ray_d, min_t, &hits)
                conditional_assign(hit_mask, &model_index, cast(lane_u32) index)
                
                when Collect_Stats {
                    result.triangles   += tests.triangles
                    result.rectangles  += tests.rectangles
                    result.empty_lanes += tests.empty_lanes
                }
            }
            spall_end()
            
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
            hit_emit  *= cast(lane_f32) (1 & lane_mask)
            lane_mask &= hit_did_hit
            
            sample = fused_mul_add(attenuation, hit_emit, sample)
            
            spall_end()
            if lane_mask == lane_false do break bounces
            
            ////////////////////////////////////////////////
            spall_scope("ray reflection")
            
            spall_begin("model to world")
            // @cleanup
            hit_normal: lane_v3
            hit_tangent: lane_v3
            hit_binormal: lane_v3
            {
                triangle_index := lane_gather(lane_member(lane_hits, "triangle", u32))
                triangles: Lane(Ray_Triangle)
                for lane in 0..<LaneWidth {
                    index := extract(triangle_index, lane)
                    model := lane_extract(model, lane)
                    triangle := &model.triangles[index]
                    replace(&triangles.p, lane, cast(umm) triangle)
                }
                
                ab := lane_gather_v(lane_member(triangles, "ab", v3))
                ac := lane_gather_v(lane_member(triangles, "ac", v3))
                
                forward := lane_member(model, "forward", Transform)
                tx := lane_gather_v(lane_member(forward, "x", v3))
                ty := lane_gather_v(lane_member(forward, "y", v3))
                tz := lane_gather_v(lane_member(forward, "z", v3))
                tt := lane_gather_v(lane_member(forward, "t", v3))
                
                ab = apply_transform(lane_Transform{tx, ty, tz, tt}, ab, 1)
                ac = apply_transform(lane_Transform{tx, ty, tz, tt}, ac, 1)
                
                // @todo(viktor): interpolate the vertex normals
                // @note(viktor): Assuming counter-clockwise winding order
                hit_normal   = normalize_or_zero(cross(ab, ac))
                hit_tangent  = normalize_or_zero(ab)
                hit_binormal = normalize_or_zero(cross(hit_normal, hit_tangent))
            }
            spall_end()
            
            #partial switch Debug_View {
            case  .Normals:  sample = abs_vec(hit_normal);   break bounces
            case .Tangents:  sample = abs_vec(hit_tangent);  break bounces
            case .Binormals: sample = abs_vec(hit_binormal); break bounces
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
            hit_t := lane_gather(lane_member(lane_hits, "closest_t", f32))
            ray_o = fused_mul_add(ray_d, hit_t, ray_o)
            ray_d = next_d
        }
        
        final_color_lanes = fused_mul_add(sample, sample_contribution_factor, final_color_lanes)
    }
    
    result.final_color.r = horizontal_add(final_color_lanes.r)
    result.final_color.g = horizontal_add(final_color_lanes.g)
    result.final_color.b = horizontal_add(final_color_lanes.b)
    
    result.bounces_computed  = cast(u64) horizontal_add(bounces_computed_lanes)
    result.loops_computed    = cast(u64) horizontal_add(loops_computed_lanes)
    
    return result
}

apply_transform :: proc (m: $Transform, v: $V/[$N] $E, w: E) -> V {
    result := w * m.t
    result = fused_mul_add(m.x, v.x, result)
    result = fused_mul_add(m.y, v.y, result)
    result = fused_mul_add(m.z, v.z, result)
    
    return result
}

////////////////////////////////////////////////

hit_tree :: proc (triangles: [] Ray_Triangle, tree: Tree, ray_o, ray_d: lane_v3, min_t: lane_f32, hits: ^[LaneWidth] Hit_Info) -> (lane_u32, Test_Info) {
    spall_proc()
    
    lane_hits := to_lane_wide(hits)
    closest_t := lane_gather(lane_member(lane_hits, "closest_t", f32))
    
    inv_d     := 1 / ray_d
    neg_inv_o := -ray_o * inv_d
    
    model_hit_mask: lane_u32
    info:           Test_Info
    {
        spall_scope("tree test root")
        root := tree[Root_Index]
        min := vec_cast(lane_f32, root.bounds.min)
        max := vec_cast(lane_f32, root.bounds.max)
        
        model_hit_mask = hit_rectangle(min, max, neg_inv_o, inv_d, min_t, closest_t)
        when Collect_Stats {
            info.rectangles += LaneWidth
        }
    }
    
    if model_hit_mask == lane_false do return model_hit_mask, info
    ////////////////////////////////////////////////
    
    triangles := to_lane(triangles)
    tree_lane := to_lane(tree)
    tree_lane = lane_index_offset(tree_lane, lane_offset)
    
    backing: [Tree_Max_Depth] Node_Index
    stack := backing[:]
    
    spall_scope("tree test nodes")
    for lane in 0..<LaneWidth {
        if extract(model_hit_mask, lane) == 0 do continue
        
        hit := &hits[lane]
        lane_ray_o     := vec_cast(lane_f32, extract_v3(ray_o, lane))
        lane_ray_d     := vec_cast(lane_f32, extract_v3(ray_d, lane))
        lane_inv_d     := vec_cast(lane_f32, extract_v3(inv_d, lane))
        lane_neg_inv_o := vec_cast(lane_f32, extract_v3(neg_inv_o, lane))
        
        stack[0]     = Root_Index
        stack_count := cast(u32) 1
        
        traversal: for stack_count != 0 {
            stack_count -= 1
            it_index := stack[stack_count]
            node     := &tree[it_index]
            
            spall_begin("node branch")
            if node.value_count == 0 {
                spall_end()
                spall_scope("subnodes")
                
                subnodes := lane_index(tree_lane, cast(lane_u32) node.first.subnode)
                
                node_min := lane_member(subnodes, "bounds", "min", v3)
                node_max := lane_member(subnodes, "bounds", "max", v3)
                
                min := lane_gather_v(node_min)
                max := lane_gather_v(node_max)
                
                bounds_hit_mask := hit_rectangle(min, max, lane_neg_inv_o, lane_inv_d, min_t, hit.closest_t)
                when Collect_Stats {
                    info.rectangles += Subnodes_Per_Node
                }
                if bounds_hit_mask == lane_false do continue traversal
                
                // @note(viktor): the last tests showed that the sorting overhead was not worth the gains it should have provided
                subnode_indices := cast(lane_u32) node.first.subnode + lane_offset
                // @note(viktor): this will be a loop unless AVX-512 is available, where it is one instruction with a few cycles of latency
                simd.masked_compress_store(&stack[stack_count], subnode_indices, bounds_hit_mask)
                stack_count += horizontal_add(1 & bounds_hit_mask)
            } else {
                spall_end()
                spall_scope("triangles")
                
                end := cast(u32) node.first.value + node.value_count
                full_end := end - (node.value_count % LaneWidth)
                
                values: for value_index := cast(u32) node.first.value; value_index < full_end; value_index += LaneWidth {
                    triangle_index := value_index + lane_offset
                    triangle := lane_index(triangles, triangle_index)
                    
                    triangle_hit_mask, triangle_t := hit_triangle(lane_true, triangle, lane_ray_o, lane_ray_d, min_t, hit.closest_t)
                    if triangle_hit_mask == lane_false do continue values
                    
                    closest_t, closest_lane := get_closest_lane(triangle_hit_mask, triangle_t)
                    hit.closest_t = closest_t
                    hit.did_hit   = 0xffff_ffff
                    hit.triangle  = value_index + closest_lane
                }
                
                tail: if value_index := full_end; value_index < end {
                    triangle_index := value_index + lane_offset
                    mask     := less_than(triangle_index, cast(lane_u32) end)
                    triangle := lane_index(triangles, triangle_index)
                    
                    triangle_hit_mask, triangle_t := hit_triangle(mask, triangle, lane_ray_o, lane_ray_d, min_t, hit.closest_t)
                    if triangle_hit_mask == lane_false do break tail
                    
                    closest_t, closest_lane := get_closest_lane(triangle_hit_mask, triangle_t)
                    hit.closest_t = closest_t
                    hit.did_hit   = 0xffff_ffff
                    hit.triangle  = value_index + closest_lane
                }
                
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
    
    t_after := lane_gather(lane_member(lane_hits, "closest_t", f32))
    model_hit_mask &= less_than(t_after, closest_t)
    
    return model_hit_mask, info
}

get_closest_lane :: proc (triangle_hit_mask: lane_u32, triangle_t: lane_f32) -> (f32, u32) {
    // @waste should just return Infinity? but what about the last calculation of t?
    masked_t   := simd.select(triangle_hit_mask, triangle_t, cast(lane_f32) +Infinity)
    closest_t  := simd.reduce_min(masked_t)
    is_closest := equal(triangle_t, cast(lane_f32) closest_t) & triangle_hit_mask
    high_bits  := transmute(u8) simd.extract_msbs(is_closest)
    closest_lane := cast(u32) simd.count_trailing_zeros(high_bits)
    
    return closest_t, closest_lane
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

hit_triangle :: proc (not_nil_mask: lane_u32, triangle: Lane(Ray_Triangle), ray_o, ray_d: lane_v3, min_t: lane_f32, max_t: lane_f32) -> (lane_u32, lane_f32) {
    Check :: false
    when Check do assert(not_nil_mask != lane_false)
    
    a  := lane_gather_v(lane_member(triangle, "a",  v3), not_nil_mask, lane_v3{})
    ab := lane_gather_v(lane_member(triangle, "ab", v3), not_nil_mask, lane_v3{})
    ac := lane_gather_v(lane_member(triangle, "ac", v3), not_nil_mask, lane_v3{})
    
    ray_cross_ac := cross(ray_d, ac)
    determinant  := dot(ab, ray_cross_ac)
    
    hit_mask := not_nil_mask
    hit_t    := cast(lane_f32) +Infinity
    
    hit_mask &= greater_than(absolute(determinant), 1e-6)
    if hit_mask == lane_false do return hit_mask, hit_t
    
    s := (ray_o - a) / determinant
    u := dot(s, ray_cross_ac)
    
    hit_mask &= greater_equal(u, 0) & less_equal(u, 1)
    if hit_mask == lane_false do return hit_mask, hit_t
    
    s_cross_ab := cross(s, ab)
    v := dot(s_cross_ab, ray_d)
    hit_mask &= greater_equal(v, 0) & less_equal(u + v, 1)
    if hit_mask == lane_false do return hit_mask, hit_t
    
    hit_t = dot(s_cross_ab, ac)
    hit_mask &= greater_than(hit_t, min_t) & less_than(hit_t, max_t)
    
    return hit_mask, hit_t
}