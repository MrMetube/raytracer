package main

import os "core:os/os2"
import "core:math"
import "core:simd"

Material :: struct {
    emit:    v3,
    reflect: v3,
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
    a, b, c: v3,
    material: u32,
}

lane_Node_Index :: #simd [LaneWidth] Node_Index

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
            final_color, bounces_computed_now, loops_computed_now := cast_rays(world, film_p, entropy, pixel_size, half_film_size, film_center, camera, rays_per_pixel, max_bounce_count)
            bounces_computed += bounces_computed_now
            loops_computed   += loops_computed_now
            
            final_color = linear_to_srgb(final_color)
            final_color *= 255
            pixel := V4(final_color, 255)
            
            pixel_index := (image.height - 1 - py) * image.width + px
            #no_bounds_check p := &image.data[pixel_index]
            p ^= round(u8, pixel)
        }
        atomic_add(&world.pixels_done, auto_cast get_dimension(rect).x)
    }
    
    atomic_add(&world.bounces_computed, bounces_computed)
    atomic_add(&world.loops_computed, loops_computed)
    atomic_add(&world.tiles_retired, 1)
}

cast_rays :: proc (world: ^World, init_film_p: lane_v2, entropy: ^RandomSeries,  pixel_size: lane_v2, half_film_size: lane_v2, film_center: lane_v3, camera: Camera, rays_per_pixel, max_bounce_count: u32) -> (final_color: v3, bounces_computed, loops_computed: u64) {
    final_color_lanes: lane_v3
    bounces_computed_lanes: lane_u32
    loops_computed_lanes: lane_u32
    
    lane_ray_count := rays_per_pixel / LaneWidth
    sample_contribution_factor := 1.0 / cast(f32) rays_per_pixel
    
    camera_p := vec_cast(lane_f32, camera.p)
    camera_x := vec_cast(lane_f32, camera.x)
    camera_y := vec_cast(lane_f32, camera.y)
    
    backing_values: [4096] lane_Node_Index
    values := backing_values[:]
    
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
            closest_t := cast(lane_f32) +Infinity
            
            hit_material_index: lane_u32
            did_hit: lane_u32
            
            next_o: lane_v3
            
            normal:   lane_v3
            tangent:  lane_v3
            binormal: lane_v3
            
            bounces_computed_lanes += 1 & lane_mask
            loops_computed_lanes   += 1
            
            ////////////////////////////////////////////////
            
            for &plane in world.planes {
                tolerance :: 0.00001
                
                plane_normal   := vec_cast(lane_f32, plane.normal)
                plane_tangent  := vec_cast(lane_f32, plane.tangent)
                plane_binormal := vec_cast(lane_f32, plane.binormal)
                
                center := vec_cast(lane_f32, plane.center)
                radius := cast(lane_f32) plane.radius
                
                denom := dot(plane_normal, ray_d)
                denom_mask := ~approximate_equal(denom, 0, tolerance)
                if denom_mask == lane_false do continue
                
                t := dot(plane_normal, center - ray_o) / denom
                t_mask := greater_than(t, min_t) & less_than(t, closest_t)
                if t_mask == lane_false do continue
                
                hit_point := ray_o + t * ray_d
                local_hit := hit_point - center
                t_mask &= less_than(absolute(local_hit.x), radius)
                t_mask &= less_than(absolute(local_hit.y), radius)
                t_mask &= less_than(absolute(local_hit.z), radius)
                if t_mask == lane_false do continue
                
                hit_mask := denom_mask & t_mask
                
                conditional_assign(hit_mask, &closest_t, t)
                conditional_assign(hit_mask, &did_hit, lane_true)
                
                conditional_assign(hit_mask, &hit_material_index, plane.material)
                
                conditional_assign(hit_mask, &next_o, ray_o + t*ray_d)
                
                conditional_assign(hit_mask, &normal,   normalize_or_zero(plane_normal))
                conditional_assign(hit_mask, &tangent,  plane_tangent)
                conditional_assign(hit_mask, &binormal, plane_binormal)
            }
            
            ////////////////////////////////////////////////
            
            if Use_Octtree {
                values_len: lane_u32
                local_nil_value_lanes_tested: [8] u32
                nodes := world.triangle_nodes[:]
                
                traverse_tree_and_collect_values(values, &values_len, nodes, ray_o, ray_d, min_t, closest_t, world)
                
                triangle_tests: u32
                for {
                    values_len = simd.saturating_sub(values_len, 1)
                    if values_len == 0 do break
                    
                    value_index := lane_gather(lane_index_wide(values, values_len), greater_than(values_len, 0), cast(lane_Node_Index) Nil_Index)
                    assert(value_index != 0, "should not have been appended")
                    
                    node     := lane_index(nodes, cast(lane_u32) value_index)
                    as_value := lane_member(node, "value", Oct_Value(Triangle))
                    value    := lane_member(as_value, "value", Triangle)
                    
                    hit_triangle(value, ray_o, ray_d, min_t, &closest_t, &did_hit, &hit_material_index, &next_o, &normal, &tangent, &binormal)
                    
                    empties := horizontal_add(1 & equal(value_index, 0))
                    assert(empties != 8)
                    #no_bounds_check local_nil_value_lanes_tested[empties] += 1
                    
                    present := horizontal_add(1 & not_equal(value_index, 0))
                    triangle_tests += 8
                }
                
                for i in 0..<len(local_nil_value_lanes_tested) {
                    atomic_add(&world.nil_value_lanes_tested[i], local_nil_value_lanes_tested[i])
                }
                
                atomic_add(&world.triangle_tests, triangle_tests)
            } else {
                // @note(viktor): skip nil triangle
                for index in 1 ..< cast(u32) len(world.triangles) {
                    triangle := lane_index(world.triangles, index)
                    hit_triangle(triangle, ray_o, ray_d, min_t, &closest_t, &did_hit, &hit_material_index, &next_o, &normal, &tangent, &binormal)
                }
                
                atomic_add(&world.triangle_tests, (cast(u32) len(world.triangles)-1) * LaneWidth)
            }
            atomic_add(&world.max_triangle_tests, (cast(u32) len(world.triangles)-1) * LaneWidth)
            
            ////////////////////////////////////////////////
            
            if Use_Octtree {
                values_len: lane_u32
                local_nil_value_lanes_tested: [8] u32
                
                nodes := world.sphere_nodes[:]
                traverse_tree_and_collect_values(values, &values_len, nodes, ray_o, ray_d, min_t, closest_t, world)
                
                for {
                    values_len = simd.saturating_sub(values_len, 1)
                    if values_len == 0 do break
                    
                    value_index := lane_gather(lane_index_wide(values, values_len), greater_than(values_len, 0), cast(lane_Node_Index) Nil_Index)
                    assert(value_index != 0, "should not have been appended")
                    
                    node     := lane_index(nodes, cast(lane_u32) value_index)
                    as_value := lane_member(node, "value", Oct_Value(Sphere))
                    value    := lane_member(as_value, "value", Sphere)
                    
                    hit_sphere(value, ray_o, ray_d, min_t, &closest_t, &did_hit, &hit_material_index, &next_o, &normal, &tangent, &binormal)
                    
                    empties := horizontal_add(1 & equal(value_index, 0))
                    assert(empties != 8)
                    #no_bounds_check local_nil_value_lanes_tested[empties] += 1
                }
                
                for i in 0..<len(local_nil_value_lanes_tested) {
                    atomic_add(&world.nil_value_lanes_tested[i], local_nil_value_lanes_tested[i])
                }
            } else {
                // @note(viktor): skip nil sphere
                for index in 1 ..< cast(u32) len(world.spheres) {
                    sphere := lane_index(world.spheres, index)
                    hit_sphere(sphere, ray_o, ray_d, min_t, &closest_t, &did_hit, &hit_material_index, &next_o, &normal, &tangent, &binormal)
                }
            }
            
            ////////////////////////////////////////////////
            
            materials_ok := less_than(hit_material_index, cast(lane_u32) len(world.materials))
            assert(materials_ok == lane_true)
            
            hit_emit    := lane_gather_v(lane_member(lane_index(world.materials, hit_material_index), "emit",    type_of(Material{}.emit)))
            hit_reflect := lane_gather_v(lane_member(lane_index(world.materials, hit_material_index), "reflect", type_of(Material{}.reflect)))
            hit_scatter := lane_gather(  lane_member(lane_index(world.materials, hit_material_index), "scatter", type_of(Material{}.scatter)))
            
            // only allow world.no_hit on the first time we didnt hit anything
            hit_emit.r *= cast(lane_f32) (1 & lane_mask)
            hit_emit.g *= cast(lane_f32) (1 & lane_mask)
            hit_emit.b *= cast(lane_f32) (1 & lane_mask)
            
            // Color Accumulation
            sample += attenuation * hit_emit
            
            lane_mask &= did_hit
            if lane_mask == lane_false do break
            
            // Bounce
            pure_bounce   := reflect(ray_d, normal)
            random_bounce := normalize_or_zero(normal + random_bilateral(entropy, lane_v3))
            
            next_d := linear_blend(pure_bounce, random_bounce, hit_scatter)
            
            reflectance := brdf_lookup(world.all_brdf_values[:], world.materials[:], hit_material_index, -ray_d, normal, tangent, binormal, next_d)
            reflectance *= hit_reflect
            conditional_assign(did_hit, &attenuation, attenuation * reflectance)
            
            ray_o = next_o
            ray_d = next_d
        }
        
        final_color_lanes += sample_contribution_factor * sample
    }
    
    final_color.r = horizontal_add(final_color_lanes.r)
    final_color.g = horizontal_add(final_color_lanes.g)
    final_color.b = horizontal_add(final_color_lanes.b)
    
    bounces_computed = cast(u64) horizontal_add(bounces_computed_lanes)
    loops_computed   = cast(u64) horizontal_add(loops_computed_lanes)
    
    return final_color, bounces_computed, loops_computed
}

////////////////////////////////////////////////

traverse_tree_and_collect_values :: proc (values: [] lane_Node_Index, values_len: ^lane_u32, nodes: [] Oct_Node($Value), ray_o, ray_d: lane_v3, min_t, max_t: lane_f32, world: ^World) {
    inv_d := 1 / normalize_or_zero(ray_d)
    
    stacks_: [64] lane_Node_Index
    stacks := stacks_[:]
    stacks[0] = Root_Index
    counts: lane_u32 = 1
    
    Check :: false
    
    // @note(viktor): currently the stacks grow and shrink in lockstep
    // lanes without valid work, work on the nil node and nil values
    #assert(Todo, "measure wasted lanes here as well")
    for counts != 0 {
        counts -= 1
        
        when Check do assert(greater_equal(counts, 0) & less_than(counts, cast(lane_u32) len(stacks)) == lane_true)
        it_index := cast(lane_u32) lane_gather(lane_index_wide(stacks, counts))
        when Check do assert(it_index != 0, "should not have been appended")
        
        it := lane_index(nodes, it_index)
        
        node := lane_member(it, "node", Oct_Node_X)
        it_bounds := lane_member(node, "bounds", Rectangle3)
        b_min := lane_gather_v(lane_member(it_bounds, "min", v3))
        b_max := lane_gather_v(lane_member(it_bounds, "max", v3))
        
        // @todo(viktor): should this update closest_t?
        hit_mask := hit_rectangle(ray_o, inv_d, b_min, b_max, min_t, max_t)
        
        first_value   := lane_gather(lane_member(node, "first_value", Node_Index))
        first_subnode := lane_gather(lane_member(node, "first_subnode", Node_Index))
        
        // @speed What order should they be appended? along the ray direction probably, then also update the closest_t/max_t for all bounds
        
        // @note(viktor): only if all lanes are zero do not push onto the stack, otherwise keep counts in sync and push zeros
        append_first_subnode := greater_than(first_subnode, 0)
        append_first_subnode &= hit_mask
        if append_first_subnode != lane_false {
            for i in cast(u32) 0..<Subnodes_Per_Node {
                lane_scatter(lane_index_wide(stacks, counts+i), first_subnode + cast(Node_Index) i, append_first_subnode)
            }
            counts += Subnodes_Per_Node
        }
        
        // @speed what is a better data layout for the values, we spend a lot of time in here, a lot of the time many lanes are emtpy
        link := first_value & cast(lane_Node_Index) hit_mask
        for link != 0 {
            length := values_len^
            
            mask := not_equal(link, 0)
            lane_scatter(lane_index_wide(values, length), link, mask)
            conditional_assign(mask, values_len, length+1)
            when Check do assert(less_than(length, auto_cast len(values)) == lane_true)
            
            value := lane_member(lane_index(nodes, cast(lane_u32) link), "value", Oct_Value(Value))
            link   = lane_gather(lane_member(value, "next_value", Node_Index)) 
        }
    }
}

////////////////////////////////////////////////

hit_rectangle :: proc (ray_o, inv_d: lane_v3, min, max: lane_v3, t_min_init, t_max_init: lane_f32) -> lane_u32 {
    t1 := (min - ray_o) * inv_d
    t2 := (max - ray_o) * inv_d
    
    tin := lane_v3 { minimum(t1.x, t2.x), minimum(t1.y, t2.y), minimum(t1.z, t2.z) }
    tax := lane_v3 { maximum(t1.x, t2.x), maximum(t1.y, t2.y), maximum(t1.z, t2.z) }
    
    tmin := maximum(maximum(t_min_init, tin.x), maximum(tin.y, tin.z))
    tmax := minimum(minimum(t_max_init, tax.x), minimum(tax.y, tax.z))
    
    result := less_equal(tmin, tmax)
    
    return result
}

hit_sphere :: proc (sphere: Lane(Sphere), ray_o, ray_d: lane_v3, min_t: lane_f32, closest_t: ^lane_f32, did_hit, hit_material_index: ^lane_u32, next_o, normal, tangent, binormal: ^lane_v3) {
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
    
    t_mask := greater_than(t, min_t) & less_than(t, closest_t^)
    
    if t_mask == lane_false do return
    
    hit_mask := root_mask & t_mask
    
    conditional_assign(hit_mask, closest_t, t)
    conditional_assign(hit_mask, did_hit, lane_true)
    
    conditional_assign(hit_mask, hit_material_index, material)
    
    // @todo(viktor): reuse the next_origin calculation
    conditional_assign(hit_mask, next_o, ray_o + t*ray_d)
    conditional_assign(hit_mask, normal, normalize_or_zero(next_o^ - center))
    
    s_tangent  := normalize_or_zero(cross(lane_v3{0, 0, 1}, normal^))
    s_binormal := cross(normal^, s_tangent)
    
    conditional_assign(hit_mask, tangent,   s_tangent)
    conditional_assign(hit_mask, binormal, s_binormal)
}

hit_triangle :: proc (triangle: Lane(Triangle), ray_o, ray_d: lane_v3, min_t: lane_f32, closest_t: ^lane_f32, did_hit, hit_material_index: ^lane_u32, next_o, normal, tangent, binormal: ^lane_v3) {
    // @note(viktor): if triangle_index == 0 its the Nil triangle
    // then determinant will be zero, so no hit can be registered
    a        := lane_gather_v(lane_member(triangle, "a", v3))
    b        := lane_gather_v(lane_member(triangle, "b", v3))
    c        := lane_gather_v(lane_member(triangle, "c", v3))
    material := lane_gather(  lane_member(triangle, "material", u32))
    
    
    ab := b - a
    ac := c - a
    ray_cross_ac := cross(ray_d, ac)
    determinant  := dot(ab, ray_cross_ac)
    
    not_parallel_mask := ~approximate_equal(determinant, 0, 1e-6) 
    if not_parallel_mask == lane_false do return
    
    inv_determinant := 1.0 / determinant
    s := ray_o - a
    u := inv_determinant * dot(s, ray_cross_ac)
    
    u_mask := greater_equal(u, 0) & less_equal(u, 1)
    if u_mask== lane_false do return
    
    s_cross_ab := cross(s, ab)
    v := inv_determinant * dot(ray_d, s_cross_ab)
    
    v_mask := greater_equal(v, 0) & less_equal(u + v, 1)
    if v_mask == lane_false do return
    
    t := inv_determinant * dot(ac, s_cross_ab)
    t_mask := greater_than(t, min_t) & less_than(t, closest_t^)
    if t_mask == lane_false do return
    
    hit_mask := not_parallel_mask & u_mask & v_mask & t_mask
    
    // @note(viktor): Assuming counter-clockwise winding order
    triangle_normal   := normalize_or_zero(cross(ab, ac))
    triangle_tangent  := normalize_or_zero(ab)
    triangle_binormal := normalize_or_zero(cross(triangle_normal, triangle_tangent))
    
    conditional_assign(hit_mask, closest_t, t)
    conditional_assign(hit_mask, did_hit, lane_true)
    
    conditional_assign(hit_mask, hit_material_index, material)
    
    conditional_assign(hit_mask, next_o, ray_o + t*ray_d)
    
    conditional_assign(hit_mask, normal,   triangle_normal)
    conditional_assign(hit_mask, tangent,  triangle_tangent)
    conditional_assign(hit_mask, binormal, triangle_binormal)
}

////////////////////////////////////////////////

brdf_lookup :: proc (all_brdf_values: [] v3, materials: [] Material, index: lane_u32, view_direction, normal, tangent, binormal, light_direction: lane_v3) -> lane_v3 {
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
    
    // @speed this is the most expensive part of the whole brdf_lookup.
    // we also know the exact allowed ranges for these lookups so we 
    // could craft a specialized approximation that only needs to handle 
    // those. or atleast make a copy and do it wide
    //
    // But the brdf lookup is not even close to being the most expensive 
    // part of a ray cast anymore. 
    f0: lane_f32
    f1: lane_f32
    f2: lane_f32
    if !true {
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
    } else {
        f0 = acos_lane_f32(hw.z)
        f1 = acos_lane_f32(diff_z_inner)
        f2 = fast_atan2_lane_f32(diff_y_inner, diff_x_inner)
        
        // @note(viktor): after the divide and clamp any NaNs will be zero in the scalar code, but Intels max_ps/min_ps do not work the same way, so we need to filter them out manually.
        conditional_assign(is_nan(f0), &f0, 0)
        conditional_assign(is_nan(f1), &f1, 0)
        
        conditional_assign(less_than(f2, 0), &f2, f2 + Pi)
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
    // @todo(viktor): @important Before indices were interpreted as f32(stride=4), when correcting to v3(stride=12) the color of all surfaces is almost black. is this because i misused the brdfs or picked bad brdfs?
    indices = floor(lane_u32, cast(lane_f32) indices / 3)
    
    values_index := lane_gather(lane_member(brdf, "values_index", u32))
    values_count := lane_gather(lane_member(brdf, "values_count", u32))
    assert(less_than(indices, cast(lane_u32) len(all_brdf_values)) == lane_true)
    assert((equal(indices, 0) | less_than(indices, values_count))  == lane_true)
    
    value  := lane_index(lane_slice(all_brdf_values, values_index), indices)
    result := lane_gather_v(value)
    
    return result
}