package main

import "base:intrinsics"
import "core:simd"

Triangle :: struct {
    a:  v3,
    ab: v3,
    ac: v3,
}

lane_Triangle :: struct {
    a:  lane_v3,
    ab: lane_v3,
    ac: lane_v3,
}

Cast_Result :: struct {
    final_color: v3, 
    bounces_computed, loops_computed: u64,
    
    using tests: Test_Info,
}

Test_Info :: struct {
    rectangles: u64,
    triangles:  u64,
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
Triangle_Threshold  : f32 = 2500
Rectangle_Threshold : f32 = 100

Collect_Stats_For_Debug_View :: true

Render_Tile_Info :: struct #all_or_none {
    triangles: [] lane_Triangle,
    normals:   [] Normals,
    trees:     [] Tree_Node,
    models:    [] RenderModel,
    materials: [] Material,
    brdf_data: [] v3,
    
    image: Image,
    camera_x: lane_v3, // scale by film_size
    camera_y: lane_v3, // scale by film_size
    camera_p: lane_v3,
    
    rays_per_pixel:   u32,
    max_bounce_count: u32,
    
    image_size_factor: v2,
    pixel_size :       v2,
    film_center:       v3,
}

render_tile :: proc(render: ^Render, rect: Rectangle2i, entropy: ^RandomSeries, stats: ^Render_Stats, info: Render_Tile_Info) {
    image             := info.image
    image_size_factor := info.image_size_factor
    
    total: Test_Info
    bounces_computed, loops_computed: u64
    shift :: 2
    pixels: for oy in cast(i32) 0..<shift {
        for ox in cast(i32) 0..<shift {
            for y := oy; y < rect.max.y - rect.min.y; y += shift {
                py := rect.min.y + y
                film_y := linear_blend(cast(f32) -1, 1, cast(f32) py * image_size_factor.y)
                
                for x := ox; x < rect.max.x - rect.min.x; x += shift {
                    if render.canceled do break pixels
                    
                    px := rect.min.x + x
                    film_x := linear_blend(cast(f32) -1, 1, cast(f32) px * image_size_factor.x)
                    
                    film_p := vec_cast(lane_f32, film_x, film_y)
                    cast_result := cast_rays(film_p, entropy, info)
                    
                    when Collect_Stats_For_Debug_View {
                        total.triangles   += cast_result.triangles
                        total.rectangles  += cast_result.rectangles
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
                atomic_add(&stats.pixels_done, auto_cast rect_get_dimension(rect).x / shift)
            }
        }
    }
    
    atomic_add(&stats.triangles,  total.triangles)
    atomic_add(&stats.rectangles, total.rectangles)
    
    atomic_add(&stats.bounces_computed, bounces_computed)
    atomic_add(&stats.loops_computed, loops_computed)
    atomic_add(&stats.tiles_retired, 1)
}

cast_rays :: proc (film_p: lane_v2, entropy: ^RandomSeries, info: Render_Tile_Info) -> Cast_Result {
    camera_p := info.camera_p
    camera_x := info.camera_x
    camera_y := info.camera_y
    
    film_center := vec_cast(lane_f32, info.film_center)
    pixel_size  := vec_cast(lane_f32, info.pixel_size)
    
    rays_per_pixel   := info.rays_per_pixel
    max_bounce_count := info.max_bounce_count
    
    lane_ray_count := rays_per_pixel / LaneWidth
    sample_contribution_factor := 1.0 / cast(f32) rays_per_pixel
    
    min_t :: cast(lane_f32) 0.0001
    
    final_color_lanes:      lane_v3
    bounces_computed_lanes: lane_u32
    loops_computed_lanes:   lane_u32
    
    result: Cast_Result
    for _ in 0..<lane_ray_count {
        spall_begin("ray generate")
        ray_o: lane_v3
        ray_d: lane_v3
        {
            jitter := random_unilateral(entropy, lane_v2)
            offset := film_p + jitter * pixel_size
            ray_film_p := film_center + offset.x * camera_x + offset.y * camera_y
            
            // @todo(viktor): depth blur can be added here by jittering the ray_o
            ray_o = camera_p
            ray_d = normalize_or_zero(ray_film_p - camera_p)
        }
        spall_end()
        
        attenuation := cast(lane_v3) 1
        lane_mask   := lane_true
        sample: lane_v3
        
        bounces: for _ in 0..<max_bounce_count {
            spall_scope("ray bounce")
            bounces_computed_lanes += 1 & lane_mask
            loops_computed_lanes   += 1
            
            ////////////////////////////////////////////////
            // Hit Detection
            
            hit_closest_t := cast(lane_f32) +Infinity
            hit_did_hit:        lane_u32
            hit_triangle_index: lane_u32
            hit_triangle_uv:    lane_v2
            hit_model_index:    lane_u32
            
            spall_begin("hit models")
            for model, index in info.models {
                model_triangles := info.triangles[model.triangle_offset : model.triangle_offset + model.triangle_count]
                model_tree      :=     info.trees[model.tree_offset     : model.tree_offset     + model.tree_count]
                
                model_ray_o := transform_mul_1(model.lane_inverse, ray_o)
                model_ray_d := transform_mul_0(model.lane_inverse, ray_d)
                
                hit_mask, hit_t, hit_triangle, hit_uv, tests := hit_tree(model_triangles, model_tree, model_ray_o, model_ray_d, min_t, hit_closest_t)
                
                hit_did_hit |= hit_mask
                conditional_assign(hit_mask, &hit_closest_t,      hit_t)
                conditional_assign(hit_mask, &hit_triangle_index, hit_triangle)
                conditional_assign(hit_mask, &hit_triangle_uv,    hit_uv)
                conditional_assign(hit_mask, &hit_model_index,    cast(lane_u32) index)
                
                when Collect_Stats_For_Debug_View {
                    result.triangles   += tests.triangles
                    result.rectangles  += tests.rectangles
                }
            }
            spall_end()
            
            ////////////////////////////////////////////////
            // Color Accumulation
            
            spall_begin("ray color accumulation")
            
            model          := lane_index(to_lane(info.models), hit_model_index)
            material_index := lane_gather_mask(lane_member(model, "material", Material_Id), hit_did_hit, 0)
            
            materials    := to_lane(info.materials)
            material     := lane_index(materials, material_index)
            hit_emit     := lane_gather_v(lane_member(material, "emit",        v3))
            hit_emission := lane_gather(  lane_member(material, "emission", f32))
            hit_emit     *= hit_emission
            
            // only allow world.no_hit on the first time we didn't hit anything
            hit_emit  *= cast(lane_f32) (1 & lane_mask)
            lane_mask &= hit_did_hit
            
            sample = fused_mul_add(attenuation, hit_emit, sample)
            
            spall_end()
            if lane_mask == lane_false do break bounces
            
            ////////////////////////////////////////////////
            // Reflection
            
            spall_scope("ray reflection and color")
            
            spall_begin("model to world")
            // @cleanup
            hit_normal:   lane_v3
            hit_tangent:  lane_v3
            hit_binormal: lane_v3
            {
                triangle_offset  := lane_gather(lane_member(model, "triangle_offset", u32))
                triangle_normals := lane_index(to_lane(info.normals), triangle_offset + hit_triangle_index)
                
                n0 := lane_gather_v(lane_index(triangle_normals, 0))
                n1 := lane_gather_v(lane_index(triangle_normals, 1))
                n2 := lane_gather_v(lane_index(triangle_normals, 2))
                
                ix := lane_gather_v(lane_member(model, "normal", "x", v3))
                iy := lane_gather_v(lane_member(model, "normal", "y", v3))
                iz := lane_gather_v(lane_member(model, "normal", "z", v3))
                // @note(viktor): no translation
                
                t := lane_Transform{ix, iy, iz, 0}
                
                hit_normal = normalize_or_zero(barycentric_blend(n0, n1, n2, hit_triangle_uv))
                hit_normal = transform_mul_0(t, hit_normal)
                hit_normal = normalize_or_zero(hit_normal)
                
                up_mask := approximate_equal(absolute(dot(hit_normal, lane_v3{0,0,1})), 1)
                axis    := ternary(up_mask, lane_v3{0,1,0}, lane_v3{0,0,1})
                hit_tangent  = normalize_or_zero(cross(hit_normal, axis))
                hit_binormal = normalize_or_zero(cross(hit_normal, hit_tangent))
            }
            spall_end()
            
            #partial switch Debug_View {
            case  .Normals:  sample = vec_abs(hit_normal);   break bounces
            case .Tangents:  sample = vec_abs(hit_tangent);  break bounces
            case .Binormals: sample = vec_abs(hit_binormal); break bounces
            }
            
            ////////////////////////////////////////////////
            
            fresnel:   lane_f32
            refract_d: lane_v3
            {
                spall_scope("refraction")
                
                refract :: proc (incident: $V/ [$N] $E, normal: V, eta_ratio: E) -> V {
                    cos_angle := dot(-incident, normal)
                    k := 1 - square(eta_ratio) * (1 - square(cos_angle))
                    a := incident * eta_ratio
                    b := normal * (eta_ratio * cos_angle + square_root(maximum(k, 0)))
                    root_mask := greater_equal(k, 0)
                    result := (a - b) * cast(lane_f32) (1 & root_mask)
                    return result
                }
                
                schlick_reflectance :: proc (cos_angle, eta_ratio: lane_f32) -> lane_f32 {
                    r := square((1 - eta_ratio) / (1 + eta_ratio))
                    x := 1 - cos_angle
                    result := r + (1 - r) * (x * square(square(x)))
                    return result
                }
                
                hit_angle       := dot(-ray_d, hit_normal)
                front_face_mask := greater_than(hit_angle, 0)
                hit_normal *= ternary(front_face_mask, cast(lane_f32) 1, -1)
                hit_angle   = dot(-ray_d, hit_normal)
                
                air_index_of_refraction :: 1
                hit_index_of_refraction := lane_gather(lane_member(material, "index_of_refraction", f32))
                ior_ratio := hit_index_of_refraction / air_index_of_refraction
                conditional_assign(front_face_mask, &ior_ratio, 1 / ior_ratio)
                
                cos_theta := clamp_01(hit_angle)
                sin_theta := square_root(maximum(1 - square(cos_theta), 0))
                fresnel    = schlick_reflectance(cos_theta, ior_ratio)
                
                total_internal_reflection := greater_than(ior_ratio * sin_theta, 1)
                conditional_assign(total_internal_reflection, &fresnel, 1)
                
                refract_d = refract(ray_d, hit_normal, ior_ratio)
            }
            
            reflect_d := reflect(ray_d, hit_normal)
            diffuse_d := normalize_or_zero(hit_normal + random_bilateral(entropy, lane_v3))
            
            ////////////////////////////////////////////////
            
            // @todo(viktor): i am not satisfied with this, can scatter just be lerped into reflection and refraction in the same way, and the other value just slides between relfection and refraction chance?
            hit_scatter      := lane_gather(lane_member(material, "scatter", f32))
            hit_transmission := lane_gather(lane_member(material, "transmission", f32))
            
            diffuse_weight      := clamp_01(hit_scatter)
            transmission_weight := clamp_01(hit_transmission) * (1 - diffuse_weight)
            specular_weight     := maximum(1 - diffuse_weight - transmission_weight, 0)
            
            reflect_weight := transmission_weight * fresnel + specular_weight
            refract_weight := transmission_weight * (1 - fresnel)
            
            ////////////////////////////////////////////////
            
            diffuse_pdf := maximum(diffuse_weight, 0.00001)
            reflect_pdf := maximum(reflect_weight, 0.00001)
            refract_pdf := maximum(refract_weight, 0.00001)
            
            choice := random_unilateral(entropy)
            
            choose_diffuse := less_than(choice, diffuse_weight)
            choose_refract := less_than(choice, diffuse_weight + refract_weight) & ~choose_diffuse
            choose_reflect := ~choose_diffuse & ~choose_refract
            
            ////////////////////////////////////////////////
            
            next_d := reflect_d
            conditional_assign(choose_diffuse, &next_d, diffuse_d)
            conditional_assign(choose_refract, &next_d, refract_d)
            
            hit_transmit := lane_gather_v(lane_member(material, "transmit", v3))
            hit_reflect  := lane_gather_v(lane_member(material, "reflect", v3))
            hit_diffuse  := hit_reflect
            hit_reflect  *= brdf_lookup(info.brdf_data, material, -ray_d, hit_normal, hit_tangent, hit_binormal, reflect_d)
            hit_diffuse  *= diffuse_weight / Pi
            
            next_attenuation := attenuation
            conditional_assign(hit_did_hit & choose_diffuse, &next_attenuation, attenuation * hit_diffuse  / diffuse_pdf)
            conditional_assign(hit_did_hit & choose_refract, &next_attenuation, attenuation * hit_transmit / refract_pdf)
            conditional_assign(hit_did_hit & choose_reflect, &next_attenuation, attenuation * hit_reflect  / reflect_pdf)
            attenuation = next_attenuation
            
            ////////////////////////////////////////////////
            
            next_o := fused_mul_add(ray_d, hit_closest_t, ray_o)
            next_o += ternary(choose_refract, -hit_normal, hit_normal) * 0.001
            
            ray_o = next_o
            ray_d = next_d
            
            // --- optional absorption ---
            // absorption   := lane_gather_v(lane_member(material, "absorption", v3))
            // attenuation *= exp(-absorption * hit_t)
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

/// target_fps = 30
/// ns_per_ray = 34
/// width  = 1920 / 4
/// height = 1080 / 4
///  width
/// height
/// pixels = width * height
/// ns_per_frame = 1 / target_fps * 1000 * 1000 * 1000
/// rays_per_frame = ns_per_frame / ns_per_ray
/// rays_per_pixel = rays_per_frame / pixels
/// rays_per_pixel

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
    
    result.x = {m.x.x, m.y.x, m.z.x}
    result.y = {m.x.y, m.y.y, m.z.y}
    result.z = {m.x.z, m.y.z, m.z.z}
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

hit_tree :: proc (triangles: [] lane_Triangle, tree: Tree, ray_o, ray_d: lane_v3, min_t, max_t: lane_f32) -> (lane_u32, lane_f32, lane_u32, lane_v2, Test_Info) {
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
        when Collect_Stats_For_Debug_View {
            info.rectangles += LaneWidth
        }
    }
    
    if total_hit_mask == lane_false {
        return lane_false, +Infinity, 0, 0, info
    }
    ////////////////////////////////////////////////
    
    tree_lane := to_lane(tree)
    tree_lane  = lane_index_offset(tree_lane, lane_offset)
    
    backing: [256] Node_Index
    stack := backing[:]
    
    model_hit_t := max_t
    model_hit_mask:     lane_u32
    model_hit_triangle: lane_u32
    model_hit_uv:       lane_v2
    for lane in 0..<LaneWidth {
        if extract(total_hit_mask, lane) == 0 do continue
        
        closest_t := extract(model_hit_t, lane)
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
                spall_scope("subnodes")
                subnodes := lane_index(tree_lane, node.first.subnode)
                
                node_min := lane_member(subnodes, "bounds", "min", v3)
                node_max := lane_member(subnodes, "bounds", "max", v3)
                
                min := lane_gather_v(node_min)
                max := lane_gather_v(node_max)
                
                bounds_hit_mask := hit_rectangle(min, max, lane_neg_inv_o, lane_inv_d, min_t, closest_t)
                when Collect_Stats_For_Debug_View {
                    info.rectangles += Subnodes_Per_Node
                }
                if bounds_hit_mask == lane_false do continue traversal
                
                // @note(viktor): the last tests showed that the sorting overhead was not worth the gains it should have provided
                subnode_indices := cast(lane_u32) node.first.subnode + lane_offset
                
                // @note(viktor): this will be a loop unless AVX-512 is available, where it is one instruction with a few cycles of latency
                simd.masked_compress_store(&stack[stack_count], subnode_indices, bounds_hit_mask)
                stack_count += horizontal_add(1 & bounds_hit_mask)
            } else {
                spall_scope("triangles")
                start := cast(u32) node.first.value / LaneWidth
                end   := start   + node.value_count / LaneWidth
                
                // @note(viktor): a "for i in start..<end" seems to be minutely slower
                for triangle_index := start; triangle_index < end; triangle_index += 1 {
                    #no_bounds_check triangle := &triangles[triangle_index]
                    
                    triangle_hit_mask, triangle_t, triangle_uv := hit_triangle(triangle, lane_ray_o, lane_ray_d, min_t, closest_t)
                    
                    // @note(viktor): The expectation is to not hit any triangle most of the time.
                    if triangle_hit_mask != lane_false {
                        conditional_assign(~triangle_hit_mask, &triangle_t, +Infinity)
                        
                        closest_t   = simd.reduce_min(triangle_t)
                        is_closest := equal(triangle_t, cast(lane_f32) closest_t)
                        high_bits  := cast(u32) transmute(u8) simd.extract_msbs(is_closest)
                        closest_lane := simd.count_trailing_zeros(high_bits)
                        
                        did_hit      = true
                        triangle_hit = triangle_index * LaneWidth + closest_lane
                        hit_uv       = extract(triangle_uv, closest_lane)
                    }
                }
                
                when Collect_Stats_For_Debug_View {
                    info.triangles += cast(u64) node.value_count
                }
            }
        }
        
        if did_hit {
            replace(&model_hit_t,        lane, closest_t)
            replace(&model_hit_mask,     lane, 0xffff_ffff)
            replace(&model_hit_triangle, lane, triangle_hit)
            replace(&model_hit_uv,       lane, hit_uv)
        }
    }
    
    return model_hit_mask, model_hit_t, model_hit_triangle, model_hit_uv, info
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

hit_triangle :: proc (triangle: ^lane_Triangle, ray_o, ray_d: lane_v3, min_t: lane_f32, max_t: lane_f32) -> (lane_u32, lane_f32, lane_v2) {
    a  := triangle.a
    ab := triangle.ab
    ac := triangle.ac
    
    ray_cross_ac := cross(ray_d, ac)
    determinant  := dot(ab, ray_cross_ac)
    
    // @note(viktor): Experimentation revealed that the u-branch is the most crucial.
    // Intuitively we expect to not hit a triangle so u_mask can be predicted to be false.
    // A random ray being parallel to the plane of the triangle is generally not true, so that branch is rarely taken, and though it may save the most work, it will also incur a branch misprediction.
    // The v-branch is generally more helpful than harmful, but does not have the same magnitude as the u-branch.
    
    hit_uv: lane_v2
    hit_t    := cast(lane_f32) +Infinity
    hit_mask := greater_than(absolute(determinant), 1e-6)
    // if hit_mask == lane_false do return hit_mask, hit_t, hit_uv
    
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