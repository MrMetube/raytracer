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
    triangle_hits: u64,
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

Sort_Subnodes := true
Early_Elimination := false

Debug_View: Debug_View_Kind
Triangle_Threshold  := 500
Rectangle_Threshold := 20

Collect_Stats_For_Debug_View :: true

Render_Tile_Info :: struct #all_or_none {
    models:    [] Render_Model,
    materials: [] Material,
    brdf_data: [] v3, 
    
    image: Image,
    camera_x: lane_v3, // scaled by film_size
    camera_y: lane_v3, // scaled by film_size
    camera_p: lane_v3,
    
    rays_per_pixel:   u32,
    max_bounce_count: u32,
    
    image_size_factor: v2,
    pixel_size:        v2,
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
                        total.triangles     += cast_result.triangles
                        total.triangle_hits += cast_result.triangle_hits
                        total.rectangles    += cast_result.rectangles
                    }
                    
                    bounces_computed += cast_result.bounces_computed
                    loops_computed   += cast_result.loops_computed
                    
                    color := cast_result.final_color
                    triangle_color  := (cast(f32) cast_result.triangles  / LaneWidth) / (cast(f32) Triangle_Threshold  * cast(f32) info.rays_per_pixel)
                    rectangle_color := (cast(f32) cast_result.rectangles / LaneWidth) / (cast(f32) Rectangle_Threshold * cast(f32) info.rays_per_pixel)
                    color = linear_to_srgb(color)
                    if Debug_View == Debug_View_Kind.Triangle_Tests {
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
    
    atomic_add(&stats.triangle_hits, total.triangle_hits)
    atomic_add(&stats.triangles,     total.triangles)
    atomic_add(&stats.rectangles,    total.rectangles)
    
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
    
    final_color:      lane_v3
    bounces_computed: lane_u32
    loops_computed:   lane_u32
    
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
        
        bounces: for bounce_index in 0..<max_bounce_count {
            spall_scope("ray bounce")
            
            // @speed @waste can be ~30% and increases with higher max bounce count. 
            // How can we still make use of the lanes, that already did not hit anything?
            // Can they be used for direct light sampling instead? How do we ensure correct
            // weighting of this additional light, so the scene is not too bright?
            // @correctness Rework the material model to ensure correct weighting in general.
            // Minor changes to roughness from .99 to 1.0 give very different images. I would
            // expect it to be a linear relation.
            
            bounces_computed += 1 & lane_mask
            loops_computed   += 1
            
            ////////////////////////////////////////////////
            // Hit Detection
            
            hit_closest_t := cast(lane_f32) +Infinity
            hit_did_hit:        lane_u32
            hit_triangle_index: lane_u32
            hit_triangle_uv:    lane_v2
            hit_model_index:    lane_u32
            
            spall_begin("hit models")
            for model, index in info.models {
                model_ray_o := transform_mul_1(model.inverse, ray_o)
                model_ray_d := transform_mul_0(model.inverse, ray_d)
                
                hit_mask, hit_t, hit_triangle, hit_uv, tests := hit_tree(lane_mask, model.triangles, model.tree, model_ray_o, model_ray_d, min_t, hit_closest_t)
                
                hit_did_hit |= hit_mask
                hit_did_hit &= lane_mask
                conditional_assign(hit_mask, &hit_closest_t,      hit_t)
                conditional_assign(hit_mask, &hit_triangle_index, hit_triangle)
                conditional_assign(hit_mask, &hit_triangle_uv,    hit_uv)
                conditional_assign(hit_mask, &hit_model_index,    cast(lane_u32) index)
                
                when Collect_Stats_For_Debug_View {
                    result.triangles     += tests.triangles
                    result.triangle_hits += tests.triangle_hits
                    result.rectangles    += tests.rectangles
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
            
            sample += attenuation * hit_emit
            
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
            hit_texture_uv: lane_v2
            {
                triangle_normals := lane_member_slice(model, "normals", [] Normals)
                triangle_uvs     := lane_member_slice(model, "uvs", [] UVs)
                
                triangle_normal := lane_index(triangle_normals, hit_triangle_index)
                triangle_uv     := lane_index(triangle_uvs,     hit_triangle_index)
                
                t0 := lane_gather_v(lane_index(triangle_uv, 0))
                t1 := lane_gather_v(lane_index(triangle_uv, 1))
                t2 := lane_gather_v(lane_index(triangle_uv, 2))
                hit_texture_uv = barycentric_blend(t0, t1, t2, hit_triangle_uv)
                
                n0 := lane_gather_v(lane_index(triangle_normal, 0))
                n1 := lane_gather_v(lane_index(triangle_normal, 1))
                n2 := lane_gather_v(lane_index(triangle_normal, 2))
                
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
            
            hit_angle       := dot(-ray_d, hit_normal)
            front_face_mask := greater_than(hit_angle, 0)
            hit_normal *= ternary(front_face_mask, cast(lane_f32) 1, -1)
            hit_angle   = dot(-ray_d, hit_normal)
            
            #partial switch Debug_View {
                case  .Normals:  sample = vec_abs(hit_normal);   break bounces
                case .Tangents:  sample = vec_abs(hit_tangent);  break bounces
                case .Binormals: sample = vec_abs(hit_binormal); break bounces
            }
            spall_end()
            
            ////////////////////////////////////////////////
            
            when true {
                spall_begin("ray reflection")
                reflect_bounce := reflect(ray_d, hit_normal)
                random_bounce  := normalize_or_zero(hit_normal + random_bilateral(entropy, lane_v3))
                
                // @todo(viktor): you really cant do roughness like this.
                // I think the merl brdfs were an interesting experiment but it is now time to move on.
                // Look into computed and not sampled models for brdfs or better bsdfs that are easier
                // to be adjusted by artist. I don't actually need 100% realistic, I just want this to
                // be based on reality and then it can be changed to be interesting.
                
                // In general I want the whole material system to change to using and sampling textures, 
                // which then can assign a value per triangle vertex or just be a 1x1 texture of the 
                // currently singular values. That seems to be the way the industry is already heading
                // and it would make my renderer compatible with those asset pipelines. 
                
                roughness := lane_gather(lane_member(material, "roughness", f32))
                reflect_d := linear_blend(reflect_bounce, random_bounce, roughness)
                
                reflectance  := brdf_lookup(info.brdf_data, material, -ray_d, hit_normal, hit_tangent, hit_binormal, reflect_d)
                reflect_tint := lane_gather_v(lane_member(material, "reflect", v3))
                
                reflect_base := texture_sample(lane_member(model, "data", "base_color", Image), hit_texture_uv)
                
                reflectance *= reflect_base * reflect_tint
                // reflectance *= maximum(dot(hit_normal, reflect_d), 0)
                
                conditional_assign(hit_did_hit, &attenuation, attenuation * reflectance)
                
                choose_refract: lane_u32
                next_d := reflect_d
                spall_end()
            } else {
                refract :: proc (incident: $V/ [$N] $E, normal: V, eta_ratio: E) -> V {
                    cos_angle := dot(-incident, normal)
                    k := 1 - square(eta_ratio) * (1 - square(cos_angle))
                    a := incident * eta_ratio
                    b := normal * (eta_ratio * cos_angle + square_root(maximum(k, 0)))
                    root_mask := greater_equal(k, 0)
                    result := (a - b) * cast(E) (1 & root_mask)
                    return result
                }
                
                schlick_reflectance :: proc (cos_angle, eta_ratio: lane_f32) -> lane_f32 {
                    r := square((1 - eta_ratio) / (1 + eta_ratio))
                    x := 1 - cos_angle
                    result := r + (1 - r) * (x * square(square(x)))
                    return result
                }
                
                air_index_of_refraction :: 1
                hit_index_of_refraction := lane_gather(lane_member(material, "index_of_refraction", f32))
                ior_ratio := hit_index_of_refraction / air_index_of_refraction
                conditional_assign(front_face_mask, &ior_ratio, 1 / ior_ratio)
                
                cos_theta := maximum(hit_angle, 0)
                sin_theta := square_root(1 - square(cos_theta))
                fresnel   := schlick_reflectance(cos_theta, ior_ratio)
                
                total_internal_reflection := greater_than(ior_ratio * sin_theta, 1)
                conditional_assign(total_internal_reflection, &fresnel, 1)
                
                refract_d     := refract(ray_d, hit_normal, ior_ratio)
                refract_value := lane_gather_v(lane_member(material, "transmit", v3))
                refract_pdf   := ternary(~total_internal_reflection, 1 - fresnel, 0)
                
                conditional_assign(total_internal_reflection, &refract_value, 0)
                
                ////////////////////////////////////////////////
                
                reflect_d     := reflect(ray_d, hit_normal)
                reflect_value := brdf_lookup(info.brdf_data, material, -ray_d, hit_normal, hit_tangent, hit_binormal, reflect_d)
                reflect_pdf   := ternary(total_internal_reflection, cast(lane_f32) 1, fresnel)
                
                
                ////////////////////////////////////////////////
                
                // @cleanup see above
                choose_refract := less_than(random_unilateral(entropy), 1 - fresnel) & ~total_internal_reflection
                next_d         := ternary(choose_refract, refract_d, reflect_d)
                
                next_attenuation := attenuation
                conditional_assign(hit_did_hit & ~choose_refract, &next_attenuation, attenuation * reflect_value / reflect_pdf)
                conditional_assign(hit_did_hit &  choose_refract, &next_attenuation, attenuation * refract_value / refract_pdf)
                attenuation = next_attenuation
            }
            
            next_o := fused_mul_add(ray_d, hit_closest_t, ray_o)
            next_o += ternary(choose_refract, -hit_normal, hit_normal) * 1e-3
            ray_o = next_o
            ray_d = normalize_or_zero(next_d)
            
            ////////////////////////////////////////////////
            
            if Early_Elimination {
                // @todo(viktor): retest if this is worth it
                early_termination_start :: cast(u32) 2
                if bounce_index >= early_termination_start {
                    early_termination_epsilon :: 0.05
                    early_termination_min :: cast(lane_f32)      early_termination_epsilon
                    early_termination_max :: cast(lane_f32) (1 - early_termination_epsilon)
                    
                    max_component        := maximum(attenuation.x, maximum(attenuation.y, attenuation.z))
                    survival_probability := clamp(max_component, early_termination_min, early_termination_max)
                    
                    survive_mask := less_than(random_unilateral(entropy, lane_f32), survival_probability)
                    lane_mask &= survive_mask
                    if lane_mask == lane_false do break bounces
                    
                    attenuation = attenuation / survival_probability
                }
            }
        }
        
        final_color = fused_mul_add(sample, sample_contribution_factor, final_color)
    }
    
    result.final_color.r = horizontal_add(final_color.r)
    result.final_color.g = horizontal_add(final_color.g)
    result.final_color.b = horizontal_add(final_color.b)
    
    result.bounces_computed  = cast(u64) horizontal_add(bounces_computed)
    result.loops_computed    = cast(u64) horizontal_add(loops_computed)
    
    return result
}

////////////////////////////////////////////////

texture_sample :: proc (texture: Lane(Image), uv: lane_v2) -> lane_v3 {
    spall_proc()
    width  := lane_gather(lane_member(texture, "width",  i32))
    height := lane_gather(lane_member(texture, "height", i32))
    data   := lane_member_slice(texture, "data", [] Color)
    
    i := uv * vec_cast(lane_f32, width, height)
    s := floor(lane_i32, i)
    f := i - vec_cast(lane_f32, s)
    
    min := lane_iv2{0,0}
    max := lane_iv2{width, height} - 1
    
    sa := clamp(s + {0, 0}, min, max)
    sb := clamp(s + {0, 1}, min, max)
    sc := clamp(s + {1, 0}, min, max)
    sd := clamp(s + {1, 1}, min, max)
    
    ia := sa.x + sa.y * width
    ib := sb.x + sb.y * width
    ic := sc.x + sc.y * width
    id := sd.x + sd.y * width
    
    ca := lane_gather_v(lane_index(data, ia))
    cb := lane_gather_v(lane_index(data, ib))
    cc := lane_gather_v(lane_index(data, ic))
    cd := lane_gather_v(lane_index(data, id))
    
    // @correctness how should alpha be used? should it be premuliplied into the sampled color?
    va := color_from_u8(ca).rgb
    vb := color_from_u8(cb).rgb
    vc := color_from_u8(cc).rgb
    vd := color_from_u8(cd).rgb
    
    result := bilinear_blend(va, vb, vc, vd, f)
    
    return result
}

/// target_fps = 30
/// ns_per_ray = 26
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

transform_mul_1 :: proc (m: $Transform, v: $V/ [$N] $E) -> V {
    result := vec_cast(E, m.t)
    result  = fused_mul_add(vec_cast(E, m.x), v.x, result)
    result  = fused_mul_add(vec_cast(E, m.y), v.y, result)
    result  = fused_mul_add(vec_cast(E, m.z), v.z, result)
    
    return result
}

transform_mul_0 :: proc (m: $Transform, v: $V/ [$N] $E) -> V {
    when type_of(m.x.x) != E {
        result := vec_cast(E, m.x) * v.x
        result  = fused_mul_add(vec_cast(E, m.y), v.y, result)
        result  = fused_mul_add(vec_cast(E, m.z), v.z, result)
    } else {
        result := m.x * v.x
        result  = fused_mul_add(m.y, v.y, result)
        result  = fused_mul_add(m.z, v.z, result)
    }
    
    return result
}

transform_set_scale :: proc (m: Transform, v: $V) -> Transform {
    result := m
    result.x.x = v.x
    result.y.y = v.y
    result.z.z = v.z
    return result
}

transform_invert :: proc (m: $Transform) -> Transform {
    // @todo(viktor): check that the determinant is ok
    determinant := dot(m.x, cross(m.y, m.z))
    inv_x := cross(m.y, m.z) / determinant
    inv_y := cross(m.z, m.x) / determinant
    inv_z := cross(m.x, m.y) / determinant
    
    result: Transform
    result.x = inv_x
    result.y = inv_y
    result.z = inv_z
    result.t = transform_mul_0(result, -m.t)
    return result
}

////////////////////////////////////////////////

hit_tree :: proc (lane_mask: lane_u32, triangles: [] lane_Triangle, tree: [] Tree_Node, ray_o, ray_d: lane_v3, min_t, max_t: lane_f32) -> (lane_u32, lane_f32, lane_u32, lane_v2, Test_Info) {
    spall_proc()
    
    inv_d     := 1 / ray_d
    neg_inv_o := -ray_o * inv_d
    
    total_hit_mask: lane_u32
    info:           Test_Info
    
    root := &tree[Root_Index]
    {
        min := root.bounds_min
        max := root.bounds_max
        
        total_hit_mask, _ = hit_rectangle(min, max, neg_inv_o, inv_d, min_t, max_t)
        total_hit_mask &= lane_mask
        
        when Collect_Stats_For_Debug_View {
            info.rectangles += LaneWidth
        }
    }
    
    if total_hit_mask == lane_false {
        return lane_false, +Infinity, 0, 0, info
    }
    ////////////////////////////////////////////////
    
    spall_scope("traverse tree")
    
    stack: [64] Stack_Entry
    
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
        
        stack_count: u32 = 1
        stack[0] = { extract(root.first, 0), extract(root.count, 0) }
        
        traversal: for stack_count != 0 {
            stack_count -= 1
            node := stack[stack_count]
            
            node_count := node.count
            node_first := node.first
            
            if node_count == 0 {
                spall_scope("subnodes")
                
                subs_index := 1 + (node_first - 1) / Subnodes_Per_Node
                subs := &tree[subs_index]
                
                min := subs.bounds_min
                max := subs.bounds_max
                
                bounds_hit_mask, bounds_hit_t := hit_rectangle(min, max, lane_neg_inv_o, lane_inv_d, min_t, closest_t)
                when Collect_Stats_For_Debug_View {
                    info.rectangles += Subnodes_Per_Node
                }
                
                if bounds_hit_mask == lane_false do continue traversal
                
                append_subnodes(stack[:], &stack_count, subs, bounds_hit_mask, bounds_hit_t)
            } else {
                spall_scope("triangles")
                start :=         node_first / LaneWidth
                end   := start + node_count / LaneWidth
                
                hits_count: lane_u32
                
                for triangle_index := start; triangle_index < end; triangle_index += 1 {
                    #no_bounds_check triangle := &triangles[triangle_index]
                    
                    triangle_hit_mask, triangle_t, triangle_uv := hit_triangle(triangle, lane_ray_o, lane_ray_d, min_t, closest_t)
                    
                    // @note(viktor): The expectation is to not hit any triangle most of the time.
                    if triangle_hit_mask != lane_false {
                        conditional_assign(~triangle_hit_mask, &triangle_t, +Infinity)
                        
                        closest_t     = simd.reduce_min(triangle_t)
                        is_closest   := equal(triangle_t, cast(lane_f32) closest_t)
                        high_bits    := cast(u32) transmute(u8) simd.extract_msbs(is_closest)
                        closest_lane := simd.count_trailing_zeros(high_bits)
                        
                        did_hit      = true
                        triangle_hit = triangle_index * LaneWidth + closest_lane
                        hit_uv       = extract(triangle_uv, closest_lane)
                        
                        when Collect_Stats_For_Debug_View {
                            hits_count += 1 & triangle_hit_mask
                        }
                    }
                }
                
                when Collect_Stats_For_Debug_View {
                    info.triangles += cast(u64) node_count
                    info.triangle_hits += cast(u64) horizontal_add(hits_count)
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

Stack_Entry :: struct {
    first: u32,
    count: u32,
}

append_subnodes :: proc (stack: [] Stack_Entry, stack_count: ^u32, subs: ^Tree_Node, bounds_hit_mask: lane_u32, bounds_hit_t: lane_f32) {
    spall_proc()
    
    index := transmute([Subnodes_Per_Node] u32) lane_offset
    
    #no_bounds_check if Sort_Subnodes {
        spall_begin("sort subnodes")
        t := transmute([Subnodes_Per_Node] f32) bounds_hit_t
        
        swap_if :: #force_inline proc(index: ^[Subnodes_Per_Node] u32, t: ^[Subnodes_Per_Node] f32, i, j: int) {
            #no_bounds_check if t[i] < t[j] { 
                swap(&t[i], &t[j]); 
                swap(&index[i], &index[j])
            }
        }
        
        swap_if(&index, &t, 0, 1)
        swap_if(&index, &t, 2, 3)
        swap_if(&index, &t, 4, 5)
        swap_if(&index, &t, 6, 7)
        
        swap_if(&index, &t, 0, 2)
        swap_if(&index, &t, 1, 3)
        swap_if(&index, &t, 4, 6)
        swap_if(&index, &t, 5, 7)
        
        swap_if(&index, &t, 1, 2)
        swap_if(&index, &t, 5, 6)
        swap_if(&index, &t, 0, 4)
        swap_if(&index, &t, 1, 5)
        swap_if(&index, &t, 2, 6)
        swap_if(&index, &t, 3, 7)
        
        swap_if(&index, &t, 2, 4)
        swap_if(&index, &t, 3, 5)
        
        swap_if(&index, &t, 1, 2)
        swap_if(&index, &t, 3, 4)
        swap_if(&index, &t, 5, 6)
        
        swap_if(&index, &t, 2, 3)
        swap_if(&index, &t, 4, 5)
        
        swap_if(&index, &t, 1, 2)
        swap_if(&index, &t, 3, 4)
        swap_if(&index, &t, 5, 6)
        spall_end()
    }
    
    spall_scope("append subnodes")
    // @speed simd.masked_compress_store would work if it was only one value per entry
    for sub in 0..<Subnodes_Per_Node {
        if extract(bounds_hit_mask, index[sub]) != 0 {
            it: Stack_Entry
            it.first = extract(subs.first, index[sub])
            it.count = extract(subs.count, index[sub])
            
            stack[stack_count^] = it
            stack_count^ += 1
        }
    }
}

////////////////////////////////////////////////

hit_rectangle :: proc (min, max: lane_v3, neg_inv_o, inv_d: lane_v3, t_min_init, t_max_init: lane_f32) -> (lane_u32, lane_f32) {
    spall_proc()
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
    return result, ternary(result, tmin, +Infinity)
}

hit_triangle :: proc (triangle: ^lane_Triangle, ray_o, ray_d: lane_v3, min_t: lane_f32, max_t: lane_f32) -> (lane_u32, lane_f32, lane_v2) {
    spall_proc()
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