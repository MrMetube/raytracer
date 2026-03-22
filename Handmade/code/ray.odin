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
    triangle_uv: v2,
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

render_tile :: proc(render: ^Render, camera: lane_Transform, rect: Rectangle2i, entropy: ^RandomSeries) {
    image            := render.image
    triangles        := render.triangles
    normals          := render.normals
    trees            := render.trees
    models           := render.models
    materials        := render.materials
    brdf_data        := render.brdf_data
    render_stats     := &render.stats
    rays_per_pixel   := render.rays_per_pixel
    max_bounce_count := render.max_bounce_count
    
    film_distance :: 1
    film_center := camera.t - film_distance * camera.z
    
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
    shift :: 2
    pixels: for oy in cast(i32) 0..<shift {
        for ox in cast(i32) 0..<shift {
            for y := oy; y < rect.max.y - rect.min.y; y += shift {
                py := rect.min.y + y
                film_y := linear_blend(cast(f32) -1, 1, cast(f32) py / image_size.y)
                for x := ox; x < rect.max.x - rect.min.x; x += shift {
                    px := rect.min.x + x
                    if render.canceled do break pixels
            
                    film_x := linear_blend(cast(f32) -1, 1, cast(f32) px / image_size.x)
                    film_p := vec_cast(lane_f32, film_x, film_y)
                    
                    cast_result := cast_rays(triangles, normals, trees, models, materials, brdf_data, film_p, entropy, pixel_size, half_film_size, film_center, camera, rays_per_pixel, max_bounce_count)
                    
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
                atomic_add(&render_stats.pixels_done, auto_cast rectangle_get_dimension(rect).x / shift)
            }
        }
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

cast_rays :: proc (triangles: [] Ray_Triangle, normals: [] Normals, trees: [] Tree_Node, models: [] RenderModel, materials: [] Material, brdf_data: [] v3, init_film_p: lane_v2, entropy: ^RandomSeries,  pixel_size: lane_v2, half_film_size: lane_v2, film_center: lane_v3, camera: lane_Transform, rays_per_pixel, max_bounce_count: u32) -> Cast_Result {
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
        ray_o := camera.t
        ray_d := normalize_or_zero(film_p - camera.t)
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
            
            lane_hits := to_lane(&hits)
            lane_scatter(lane_member(lane_hits, "closest_t", f32), cast(lane_f32) +Infinity)
            
            spall_begin("hit models")
            for model, index in models {
                model_triangles := triangles[model.triangle_offset : model.triangle_offset + model.triangle_count]
                model_tree      := trees[    model.tree_offset     : model.tree_offset     + model.tree_count]
                
                model_ray_o := transform_mul_1(model.lane_inverse, ray_o)
                model_ray_d := transform_mul_0(model.lane_inverse, ray_d)
                
                model_max_t := lane_gather(lane_member(lane_hits, "closest_t", f32))
                
                hit_mask, hit_t, hit_triangle, hit_uv, tests := hit_tree(model_triangles, model_tree, model_ray_o, model_ray_d, min_t, model_max_t)
                for lane in 0..<LaneWidth {
                    if extract(hit_mask, lane) != 0 {
                        hits[lane].did_hit     = 0xffff_ffff
                        hits[lane].closest_t   = extract(hit_t, lane)
                        hits[lane].triangle    = extract(hit_triangle, lane)
                        hits[lane].triangle_uv = extract(hit_uv, lane)
                    }
                }
                conditional_assign(hit_mask, &model_index, cast(lane_u32) index)
                
                when Collect_Stats {
                    result.triangles   += tests.triangles
                    result.rectangles  += tests.rectangles
                    result.empty_lanes += tests.empty_lanes
                }
            }
            spall_end()
            
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
            hit_normal:   lane_v3
            hit_tangent:  lane_v3
            hit_binormal: lane_v3
            {
                triangle_index := lane_gather(lane_member(lane_hits, "triangle", u32))
                uv := lane_gather_v(lane_member(lane_hits, "triangle_uv", v2))
                triangle_normals := lane_index(to_lane(normals), lane_gather(lane_member(model, "triangle_offset", u32)) + triangle_index)
                
                n0 := lane_gather_v(lane_index(triangle_normals, 0))
                n1 := lane_gather_v(lane_index(triangle_normals, 1))
                n2 := lane_gather_v(lane_index(triangle_normals, 2))
                
                ix := lane_gather_v(lane_member(model, "inverse", "x", v3))
                iy := lane_gather_v(lane_member(model, "inverse", "y", v3))
                iz := lane_gather_v(lane_member(model, "inverse", "z", v3))
                // @note(viktor): no translation
                
                t := lane_Transform{ix, iy, iz, 0}
                t = transform_transpose(t)
                
                hit_normal = normalize_or_zero((1-uv.x-uv.y) * n0 + uv.x * n1 + uv.y * n2)
                hit_normal = transform_mul_0(t, hit_normal)
                hit_normal = normalize_or_zero(hit_normal)
                
                up_mask := approximate_equal(absolute(dot(hit_normal, lane_v3{0,0,1})), 1)
                hit_tangent  = normalize_or_zero(ternary(up_mask, cross(hit_normal, lane_v3{0,1,0}), cross(hit_normal, lane_v3{0,0,1})))
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
            
            next_d := normalize_or_zero(linear_blend(pure_bounce, random_bounce, hit_scatter))
            
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

transform_transpose :: proc (m: $Transform) -> Transform {
    result: Transform
    result.x.x = m.x.x
    result.y.x = m.x.y
    result.z.x = m.x.z
    result.x.y = m.y.x
    result.y.y = m.y.y
    result.z.y = m.y.z
    result.x.z = m.z.x
    result.y.z = m.z.y
    result.z.z = m.z.z
    result.t = 0
    return result
}

transform_mul_1 :: proc (m: $Transform, v: $V) -> V {
    result := m.t
    result  = fused_mul_add(m.x, v.x, result)
    result  = fused_mul_add(m.y, v.y, result)
    result  = fused_mul_add(m.z, v.z, result)
    
    return result
}

transform_mul_0 :: proc (m: $Transform, v: $V) -> V {
    result := m.x * v.x
    result  = fused_mul_add(m.y, v.y, result)
    result  = fused_mul_add(m.z, v.z, result)
    
    return result
}

////////////////////////////////////////////////

hit_tree :: proc (triangles: [] Ray_Triangle, tree: Tree, ray_o, ray_d: lane_v3, min_t, max_t: lane_f32) -> (lane_u32, lane_f32, lane_u32, lane_v2, Test_Info) {
    spall_proc()
    
    inv_d     := 1 / ray_d
    neg_inv_o := -ray_o * inv_d
    
    total_hit_mask: lane_u32
    info:           Test_Info
    {
        root := tree[Root_Index]
        min := vec_cast(lane_f32, root.bounds.min)
        max := vec_cast(lane_f32, root.bounds.max)
        
        total_hit_mask = hit_rectangle(min, max, neg_inv_o, inv_d, min_t, max_t)
        when Collect_Stats {
            info.rectangles += LaneWidth
        }
    }
    
    if total_hit_mask == lane_false do return lane_false, +Infinity, 0, 0, info
    ////////////////////////////////////////////////
    
    triangles := to_lane(triangles)
    tree_lane := to_lane(tree)
    tree_lane = lane_index_offset(tree_lane, lane_offset)
    
    backing: [Tree_Max_Depth] Node_Index
    stack := backing[:]
    
    model_hit_mask: lane_u32
    model_hit_t: lane_f32 = max_t
    model_hit_triangle: lane_u32
    model_hit_uv: lane_v2
    for lane in 0..<LaneWidth {
        if extract(total_hit_mask, lane) == 0 do continue
        
        closest_t_hit := extract(model_hit_t, lane)
        did_hit: bool
        triangle_hit: u32
        hit_uv: v2
        
        lane_ray_o     := vec_cast(lane_f32, extract(ray_o, lane))
        lane_ray_d     := vec_cast(lane_f32, extract(ray_d, lane))
        lane_inv_d     := vec_cast(lane_f32, extract(inv_d, lane))
        lane_neg_inv_o := vec_cast(lane_f32, extract(neg_inv_o, lane))
        
        stack[0]     = Root_Index
        stack_count := cast(u32) 1
        
        traversal: for stack_count != 0 {
            stack_count -= 1
            it_index := stack[stack_count]
            node     := &tree[it_index]
            
            if node.value_count == 0 {
                subnodes := lane_index(tree_lane, cast(lane_u32) node.first.subnode)
                
                node_min := lane_member(subnodes, "bounds", "min", v3)
                node_max := lane_member(subnodes, "bounds", "max", v3)
                
                min := lane_gather_v(node_min)
                max := lane_gather_v(node_max)
                
                bounds_hit_mask := hit_rectangle(min, max, lane_neg_inv_o, lane_inv_d, min_t, closest_t_hit)
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
                end := cast(u32) node.first.value + node.value_count
                full_end := end - (node.value_count % LaneWidth)
                
                values: for value_index := cast(u32) node.first.value; value_index < full_end; value_index += LaneWidth {
                    triangle_index := value_index + lane_offset
                    triangle := lane_index(triangles, triangle_index)
                    
                    triangle_hit_mask, triangle_t, triangle_uv := hit_triangle(lane_true, triangle, lane_ray_o, lane_ray_d, min_t, closest_t_hit)
                    if triangle_hit_mask == lane_false do continue values
                    
                    closest_t, closest_lane := get_closest_lane(triangle_hit_mask, triangle_t)
                    closest_t_hit = closest_t
                    did_hit       = true
                    triangle_hit  = value_index + closest_lane
                    hit_uv        = extract(triangle_uv, closest_lane)
                }
                
                tail: if value_index := full_end; value_index < end {
                    triangle_index := value_index + lane_offset
                    mask     := less_than(triangle_index, cast(lane_u32) end)
                    triangle := lane_index(triangles, triangle_index & mask)
                    
                    triangle_hit_mask, triangle_t, triangle_uv := hit_triangle(mask, triangle, lane_ray_o, lane_ray_d, min_t, closest_t_hit)
                    if triangle_hit_mask == lane_false do break tail
                    
                    closest_t, closest_lane := get_closest_lane(triangle_hit_mask, triangle_t)
                    closest_t_hit = closest_t
                    did_hit       = true
                    triangle_hit  = value_index + closest_lane
                    hit_uv        = extract(triangle_uv, closest_lane)
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
        
        if did_hit {
            replace(&model_hit_t,        lane, closest_t_hit)
            replace(&model_hit_mask,     lane, 0xffff_ffff)
            replace(&model_hit_triangle, lane, triangle_hit)
            replace(&model_hit_uv,       lane, hit_uv)
        }
    }
    
    // @cleanup
    assert(less_than(model_hit_t, max_t) == model_hit_mask)
    
    return model_hit_mask, model_hit_t, model_hit_triangle, model_hit_uv, info
}

get_closest_lane :: proc (triangle_hit_mask: lane_u32, triangle_t: lane_f32) -> (f32, u32) {
    // @waste should just return Infinity? but what about the last calculation of t?
    // its either larger than max_t, or smaller than min_t
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

hit_triangle :: proc (not_nil_mask: lane_u32, triangle: Lane(Ray_Triangle), ray_o, ray_d: lane_v3, min_t: lane_f32, max_t: lane_f32) -> (lane_u32, lane_f32, lane_v2) {
    Check :: false
    when Check do assert(not_nil_mask != lane_false)
    
    a  := lane_gather_v(lane_member(triangle, "a",  v3), not_nil_mask, lane_v3{})
    ab := lane_gather_v(lane_member(triangle, "ab", v3), not_nil_mask, lane_v3{})
    ac := lane_gather_v(lane_member(triangle, "ac", v3), not_nil_mask, lane_v3{})
    
    ray_cross_ac := cross(ray_d, ac)
    determinant  := dot(ab, ray_cross_ac)
    
    hit_mask := not_nil_mask
    hit_t    := cast(lane_f32) +Infinity
    hit_uv: lane_v2
    hit_mask &= greater_than(absolute(determinant), 1e-6)
    if hit_mask == lane_false do return hit_mask, hit_t, hit_uv
    
    s := (ray_o - a)
    inv_determinant := 1 / determinant
    u := dot(s, ray_cross_ac) * inv_determinant
    
    hit_mask &= greater_equal(u, 0) & less_equal(u, 1)
    if hit_mask == lane_false do return hit_mask, hit_t, hit_uv
    
    s_cross_ab := cross(s, ab)
    v := dot(s_cross_ab, ray_d) * inv_determinant
    hit_mask &= greater_equal(v, 0) & less_equal(u + v, 1)
    if hit_mask == lane_false do return hit_mask, hit_t, hit_uv
    
    hit_t = dot(s_cross_ab, ac) * inv_determinant
    hit_mask &= greater_than(hit_t, min_t) & less_than(hit_t, max_t)
    hit_uv = lane_v2{u, v}
    
    return hit_mask, hit_t, hit_uv
}