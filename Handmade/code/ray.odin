package main

Triangle :: struct {
    a: v3,
    b: v3,
    c: v3,
    material: u32,
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
    closest_t: lane_f32,
    did_hit:   lane_u32,
    material:  lane_u32,
    next_o:    lane_v3,
    normal:    lane_v3,
    tangent:   lane_v3,
    binormal:  lane_v3,
}

Hit_Info_Lane :: struct {
    closest_t: f32,
    did_hit:   u32,
    material:  u32,
    next_o:    v3,
    normal:    v3,
    tangent:   v3,
    binormal:  v3,
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
            
            cast_result := cast_rays(render_stats, models, materials, brdf_data, film_p, entropy, pixel_size, half_film_size, film_center, camera, rays_per_pixel, max_bounce_count)
            
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
            #no_bounds_check {
                image.data[pixel_index] = pixel
            }
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

cast_rays :: proc (stats: ^Render_Stats, models: [] Model, materials: [] Material, brdf_data: [] v3, init_film_p: lane_v2, entropy: ^RandomSeries,  pixel_size: lane_v2, half_film_size: lane_v2, film_center: lane_v3, camera: Camera, rays_per_pixel, max_bounce_count: u32) -> Cast_Result {
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
            spall_scope("ray bounce")
            
            bounces_computed_lanes += 1 & lane_mask
            loops_computed_lanes   += 1
            
            ////////////////////////////////////////////////

            hits: [LaneWidth] Hit_Info_Lane
            
            // @cleanup is this what to_lane([LaneWidth] T) should always just be?
            lane_hits := lane_index(to_lane(hits[:]), lane_offset)
            lane_scatter(lane_member(lane_hits, "closest_t", f32), cast(lane_f32) +Infinity)
            
            for model in models {
                spall_scope("hit model")
                
                triangles := model.triangles
                tree      := model.tree[:]
                
                if len(tree) == 0 || len(triangles) == 0 do continue
                
                spall_begin("model translate")
                translation := vec_cast(lane_f32, model.translation)
                model_ray_o := ray_o - translation
                model_ray_d := ray_d
                // @waste
                t_before := lane_gather(lane_member(lane_hits, "closest_t", f32))
                spall_end()
                
                tests := traverse_tree_and_test_triangles(to_lane(triangles), tree, model_ray_o, model_ray_d, min_t, &hits)
                when Collect_Stats {
                    result.triangles   += tests.triangles
                    result.rectangles  += tests.rectangles
                    result.empty_lanes += tests.empty_lanes
                }
                
                
                spall_begin("model translate")
                t_after := lane_gather(lane_member(lane_hits, "closest_t", f32))
                
                update_mask := less_than(t_after, t_before)
                // @cleanup lane_plus_equal?
                lane_next_o := lane_member(lane_hits, "next_o", v3)
                next_o := lane_gather_v(lane_next_o)
                lane_scatter_v(lane_next_o, next_o + translation, update_mask)
                spall_end()
            }
            
            ////////////////////////////////////////////////
            // @todo(viktor): Importance Sampling
            // sort models my material emitance strength / store all materials with emitance separately
            //   model should store a material and before render assign it to every triangle
            // besides the normal ray, also cast a "shadow ray"
            // select a random emitting model and a random triangle in that model (weighting?)
            // select a random point on that triangle and traverse this ray aswell
            //   always keep a shadow ray besides ray_o, ray_d (make a lane_ray struct)
            //   always trace both ray and shadow ray for each model
            // combine contribution of ray and shadow ray(only if next_o == ~triangle pointif it reaches the light?)
            //   scale shadow ray by G = dot(normalize(-ray_d), t_normal) / length_squared(ray_d)
            //   scale by probablity-distribution-function: 1 / (P(model) * P(triangle) * P(area))
            // balance heuristic: 
            //   
            
            // @waste is Hit_Info as a struct really needed anymore?
            hit: Hit_Info
            hit.closest_t = lane_gather(lane_member(lane_hits, "closest_t",  f32))
            hit.did_hit   = lane_gather(lane_member(lane_hits, "did_hit",    u32))
            hit.material  = lane_gather(lane_member(lane_hits, "material",   u32))
            hit.next_o    = lane_gather_v(lane_member(lane_hits, "next_o",   v3))
            hit.normal    = lane_gather_v(lane_member(lane_hits, "normal",   v3))
            hit.tangent   = lane_gather_v(lane_member(lane_hits, "tangent",  v3))
            hit.binormal  = lane_gather_v(lane_member(lane_hits, "binormal", v3))
            
            spall_scope("ray color")
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
    
    result.final_color.r = horizontal_add(final_color_lanes.r)
    result.final_color.g = horizontal_add(final_color_lanes.g)
    result.final_color.b = horizontal_add(final_color_lanes.b)
    
    result.bounces_computed  = cast(u64) horizontal_add(bounces_computed_lanes)
    result.loops_computed    = cast(u64) horizontal_add(loops_computed_lanes)
    
    return result
}

////////////////////////////////////////////////

traverse_tree_and_test_triangles :: proc { traverse_tree_and_test_triangles_xx, traverse_tree_and_test_triangles_yy }
traverse_tree_and_test_triangles_yy :: proc (triangles: Lane_Slice(Triangle), tree: [] Tree_Node, ray_o, ray_d: lane_v3, min_t: lane_f32, hits: ^[LaneWidth] Hit_Info_Lane) -> Test_Info {
    spall_proc()
    
    result: Test_Info
    for &hit, lane in hits {
        ray_d := extract_v3(ray_d, lane)
        ray_o := extract_v3(ray_o, lane)
        
        now := traverse_tree_and_test_triangles_xx(triangles, tree, ray_o, ray_d, min_t, &hit)
        when Collect_Stats {
            result.triangles   += now.triangles
            result.rectangles  += now.rectangles
            result.empty_lanes += now.empty_lanes
        }
    }
    
    return result
}

traverse_tree_and_test_triangles_xx :: proc (triangles: Lane_Slice(Triangle), tree: [] Tree_Node, ray_o, ray_d: v3, min_t: lane_f32, hit: ^Hit_Info_Lane) -> Test_Info {
    spall_proc()
    
    inv_d := 1 / ray_d
    neg_inv_o := -(ray_o * inv_d)
    
    backing: [Tree_Max_Depth] Node_Index
    backing[0] = Root_Index
    
    stack_count := cast(u32) 1
    stack := backing[:]
    
    result: Test_Info
    for stack_count != 0 {
        stack_count -= 1
        it_index := stack[stack_count]
        node := &tree[it_index]
        
        if node.value_count == 0 {
            indices  := cast(lane_u32) node.first.subnode + lane_offset
            subnodes := lane_index(to_lane(tree), indices)
            
            hit_mask := hit_rectangle(subnodes, neg_inv_o, inv_d, min_t, hit.closest_t)
            when Collect_Stats {
                result.rectangles += Subnodes_Per_Node
            }
            
            if hit_mask != lane_false {
                // @note(viktor): the last tests showed that the sorting overhead was not worth the gains it should have provided
                for lane_index in 0..<LaneWidth {
                    if extract(hit_mask, lane_index) != 0 {
                        subindex := node.first.subnode + cast(Node_Index) lane_index
                        stack[stack_count] = subindex
                        stack_count += 1
                    }
                }   
            }
        } else {
            start := cast(u32) node.first.value
            end   := cast(u32) node.first.value + node.value_count
            
            for value_index := start; value_index < end; value_index += LaneWidth {
                index := value_index + lane_offset
                
                mask     := less_than(index, cast(lane_u32) end)
                triangle := lane_index(triangles, index)
                hit_triangle(mask, triangle, ray_o, ray_d, min_t, hit)
            }
            
            when Collect_Stats {
                result.triangles += cast(u64) node.value_count
                
                full      := node.value_count / LaneWidth
                remaining := node.value_count % LaneWidth
                
                result.empty_lanes[0] += full * LaneWidth
                if remaining != 0 do result.empty_lanes[LaneWidth - remaining] += 1
            }
        }
    }
    
    return result
}

////////////////////////////////////////////////

hit_rectangle :: proc (node: Lane(Tree_Node), neg_inv_o, inv_d: v3, t_min_init, t_max_init: lane_f32) -> lane_u32 {
    spall_proc()
    node_min := lane_member(node, "bounds", "min", v3)
    node_max := lane_member(node, "bounds", "max", v3)
    min  := lane_gather_v(node_min)
    max  := lane_gather_v(node_max)
    
    // @waste
    inv_d_x := cast(lane_f32) inv_d.x
    inv_d_y := cast(lane_f32) inv_d.y
    inv_d_z := cast(lane_f32) inv_d.z
    neg_inv_o_x := cast(lane_f32) neg_inv_o.x
    neg_inv_o_y := cast(lane_f32) neg_inv_o.y
    neg_inv_o_z := cast(lane_f32) neg_inv_o.z
    
    t1x := fused_mul_add(min.x, inv_d_x, neg_inv_o_x)
    t1y := fused_mul_add(min.y, inv_d_y, neg_inv_o_y)
    t1z := fused_mul_add(min.z, inv_d_z, neg_inv_o_z)
    t2x := fused_mul_add(max.x, inv_d_x, neg_inv_o_x)
    t2y := fused_mul_add(max.y, inv_d_y, neg_inv_o_y)
    t2z := fused_mul_add(max.z, inv_d_z, neg_inv_o_z)
    
    tin := lane_v3 { minimum(t1x, t2x), minimum(t1y, t2y), minimum(t1z, t2z) }
    tax := lane_v3 { maximum(t1x, t2x), maximum(t1y, t2y), maximum(t1z, t2z) }
    
    tmin := maximum(maximum(t_min_init, tin.x), maximum(tin.y, tin.z))
    tmax := minimum(minimum(t_max_init, tax.x), minimum(tax.y, tax.z))
    
    result := less_equal(tmin, tmax)
    return result
}

// @speed precompute normals at construction, or just load them from the model data
// @speed make triangles SOA on { vertices, material, (normals) }
// @speed measure branch mispredictions: do i also have an unpredictable branch in these u/v test, because each part is unpredictable but the whole expression should be predicted as false?
hit_triangle :: proc (not_nil_mask: lane_u32, triangle: Lane(Triangle), ray_o, ray_d: v3, min_t: lane_f32, hit: ^Hit_Info_Lane) {
    spall_proc()
    
    // @waste
    ray_o := vec_cast(lane_f32, ray_o)
    ray_d := vec_cast(lane_f32, ray_d)
    
    Check :: false
    when Check do assert(not_nil_mask != lane_false)
    
    a := lane_gather_v(lane_member(triangle, "a", v3), not_nil_mask, lane_v3{})
    b := lane_gather_v(lane_member(triangle, "b", v3), not_nil_mask, lane_v3{})
    c := lane_gather_v(lane_member(triangle, "c", v3), not_nil_mask, lane_v3{})
    
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
    hit_mask := greater_than(t, min_t) & less_than(t, cast(lane_f32) hit.closest_t)
    hit_mask &= v_mask
    if hit_mask == lane_false do return
    
    // @todo(viktor): interpolate the vertex normals
    // @note(viktor): Assuming counter-clockwise winding order
    normal   := normalize_or_zero(cross(ab, ac))
    tangent  := normalize_or_zero(ab)
    binormal := normalize_or_zero(cross(normal, tangent))
    
    next_o := ray_o + t*ray_d
    
    closest_lane := -1
    closest_t := +Infinity
    // @speed can this be done easier?
    for lane in 0..<LaneWidth {
        lane_t := extract(t, lane)
        if closest_t > lane_t && extract(hit_mask, lane) != 0 {
            closest_t    = lane_t
            closest_lane = lane
        }
    }
    when Check do assert(closest_lane != -1)
    
    material := lane_gather(lane_member(triangle, "material", u32), not_nil_mask, lane_u32{})
    
    hit.closest_t = closest_t
    hit.did_hit   = 0xffff_ffff
    hit.material  = extract(material,    closest_lane)
    hit.next_o    = extract_v3(next_o,   closest_lane)
    hit.normal    = extract_v3(normal,   closest_lane)
    hit.tangent   = extract_v3(tangent,  closest_lane)
    hit.binormal  = extract_v3(binormal, closest_lane)
}