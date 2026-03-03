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
    a: v3,
    b: v3,
    c: v3,
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
            
            color, bounces_now, loops_now := cast_rays(world, film_p, entropy, pixel_size, half_film_size, film_center, camera, rays_per_pixel, max_bounce_count)
            
            bounces_computed += bounces_now
            loops_computed   += loops_now
            
            color = linear_to_srgb(color)
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

cast_rays :: proc (world: ^World, init_film_p: lane_v2, entropy: ^RandomSeries,  pixel_size: lane_v2, half_film_size: lane_v2, film_center: lane_v3, camera: Camera, rays_per_pixel, max_bounce_count: u32) -> (final_color: v3, bounces_computed, loops_computed: u64) {
    spall_proc()
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
        jitter := random_unilateral(entropy, lane_v2) * 0.01
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
                values_len: lane_u32
                local_nil_value_lanes_tested: [8] u32
                
                nodes := world.triangle_nodes
                traverse_tree_and_collect_values(to_lane(values), &values_len, nodes[:], ray_o, ray_d, min_t, hit.closest_t, world)
                
                Check :: false
                for {
                    values_len = simd.saturating_sub(values_len, 1)
                    if values_len == 0 do break
                    
                    values := to_lane(values)
                    value_index := lane_gather(values, values_len, greater_than(values_len, 0), cast(lane_Node_Index) Nil_Index)
                    when Check do assert(value_index != 0, "should not have been appended")
                    
                    // @note(viktor): Test: with and without loading all triangle data, check just the compute work
                    // baseline - nil triangle
                    // 305ms - 115ms
                    // no early outs in hit_triangle
                    // 335ms - 170ms
                    // -> ~46% of the work is loading triangles
                    
                    // pretend_to_read(&value_index)
                    // value_index = 0
                    // pretend_to_write(&value_index)
                    
                    nodes := to_lane(nodes)
                    node  := lane_index(nodes, cast(lane_u32) value_index)
                    value := lane_member(node, "value", "value", Triangle) 
                    
                    hit_triangle(value, ray_o, ray_d, min_t, &hit)
                    
                    empties := horizontal_add(1 & equal(value_index, 0))
                    when Check do assert(empties != 8)
                    #no_bounds_check local_nil_value_lanes_tested[empties] += 1
                }
                
                for i in 0..<len(local_nil_value_lanes_tested) {
                    atomic_add(&world.nil_value_lanes_tested[i], local_nil_value_lanes_tested[i])
                }
            } else {
                triangles := to_lane(world.triangles) // @cleanup
                // @note(viktor): skip nil triangle
                for index in 1 ..< cast(u32) len(world.triangles) {
                    triangle := lane_index(triangles, index)
                    hit_triangle(triangle, ray_o, ray_d, min_t, &hit)
                }
            }
            
            ////////////////////////////////////////////////
            
            if Use_Tree {
                values_len: lane_u32
                local_nil_value_lanes_tested: [8] u32
                
                nodes := world.sphere_nodes
                traverse_tree_and_collect_values(to_lane(values), &values_len, nodes[:], ray_o, ray_d, min_t, hit.closest_t, world)
                
                for {
                    values_len = simd.saturating_sub(values_len, 1)
                    if values_len == 0 do break
                    
                    values := to_lane(values)
                    value_index := lane_gather(values, values_len, greater_than(values_len, 0), cast(lane_Node_Index) Nil_Index)
                    assert(value_index != 0, "should not have been appended")
                    
                    nodes    := to_lane(nodes)
                    node     := lane_index(nodes, cast(lane_u32) value_index)
                    value    := lane_member(node, "value", "value", Sphere) 
                    
                    hit_sphere(value, ray_o, ray_d, min_t, &hit)
                    
                    empties := horizontal_add(1 & equal(value_index, 0))
                    assert(empties != 8)
                    #no_bounds_check local_nil_value_lanes_tested[empties] += 1
                }
                
                for i in 0..<len(local_nil_value_lanes_tested) {
                    atomic_add(&world.nil_value_lanes_tested[i], local_nil_value_lanes_tested[i])
                }
            } else {
                spheres := to_lane(world.spheres) // @cleanup
                // @note(viktor): skip nil sphere
                for index in 1 ..< cast(u32) len(world.spheres) {
                    sphere := lane_index(spheres, index)
                    hit_sphere(sphere, ray_o, ray_d, min_t, &hit)
                }
            }
            
            ////////////////////////////////////////////////
            
            materials       := to_lane(world.materials)
            all_brdf_values := to_lane(world.all_brdf_values)
            
            material    := lane_index(materials, hit.material)
            hit_emit    := lane_gather_v(lane_member(material, "emit",    type_of(Material{}.emit)))
            hit_reflect := lane_gather_v(lane_member(material, "reflect", type_of(Material{}.reflect)))
            hit_scatter := lane_gather(  lane_member(material, "scatter", type_of(Material{}.scatter)))
            
            // only allow world.no_hit on the first time we didn't hit anything
            hit_emit.r *= cast(lane_f32) (1 & lane_mask)
            hit_emit.g *= cast(lane_f32) (1 & lane_mask)
            hit_emit.b *= cast(lane_f32) (1 & lane_mask)
            
            // Color Accumulation
            sample += attenuation * hit_emit
            
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
    
    return final_color, bounces_computed, loops_computed
}

////////////////////////////////////////////////

traverse_tree_and_collect_values :: proc (values: Lane_Slice(Node_Index), values_len: ^lane_u32, nodes: [] Tree_Node($Value), ray_o, ray_d: lane_v3, min_t, max_t: lane_f32, world: ^World) {
    spall_proc()
    if nodes[Root_Index].node.first_value == Nil_Index do return
    nodes := to_lane(nodes)
    
    inv_d := 1 / ray_d
    neg_inv_o := -(ray_o * inv_d)
    
    stacks_: [128] lane_Node_Index
    stacks_[0] = Root_Index
    stacks := to_lane(stacks_[:])
    counts: lane_u32 = 1
    
    Check :: false
    
    // @todo(viktor): measure wasted lanes here as well
    closest_t := max_t
    
    // @note(viktor): currently the stacks grow and shrink in lockstep.
    // lanes without valid work, work on the nil node and nil values.
    for counts != 0 {
        counts -= 1
        
        it_index := cast(lane_u32) lane_gather(stacks, counts)
        when Check do assert(it_index != 0, "should not have been appended")
        
        node        := lane_member(lane_index(nodes, it_index), "node", Tree_Node_X)
        first_value := lane_gather(lane_member(node, "first_value", Node_Index))
        when Check do assert(first_value != Nil_Index)
        
        b_min := lane_gather_v(lane_member(node, "bounds", "min", v3)) 
        b_max := lane_gather_v(lane_member(node, "bounds", "max", v3)) 
        
        // @todo(viktor): should this update closest_t?
        hit_mask, _ := hit_rectangle(neg_inv_o, inv_d, b_min, b_max, min_t, closest_t)
        // @todo(viktor): this requires that the subnodes are appended in the order from nearest to farthest
        // conditional_assign(hit_mask, &closest_t, t)
        
        // @todo(viktor): @important if viewed almost directly along an axis, the bounds seems to make cracks in my triangles
        
        // @speed this feels like a binary search problem, each node splits the search space into two, but there may be holes.and if we do a full bvh child bounds may overlap and then its not
        spall_begin("append subnodes")
        
        first_subnode : lane_Node_Index = lane_gather(lane_member(node, "first_subnode", Node_Index))
        // @note(viktor): only if all lanes are zero do not push onto the stack, otherwise keep counts in sync and push zeros
        append_first_subnode := not_equal(first_subnode, 0)
        append_first_subnode &= hit_mask
        if append_first_subnode != lane_false {
            // @todo(viktor): push the closer subnode first once we also correctly update the closest_t
            added: u32
            
            subnode_0_index := lane_index(nodes, cast(lane_u32) first_subnode+0)
            subnode_1_index := lane_index(nodes, cast(lane_u32) first_subnode+1)
            subnode_0_first_value := lane_gather(lane_member(subnode_0_index, "node", "first_value", Node_Index)) 
            subnode_1_first_value := lane_gather(lane_member(subnode_1_index, "node", "first_value", Node_Index)) 
            
            if subnode_0_first_value != Nil_Index { // @note(viktor): skip if all subnodes are empty
                lane_scatter(stacks, counts+added, first_subnode+0, append_first_subnode)
                added += 1
            }
            if subnode_1_first_value != Nil_Index { // @note(viktor): skip if all subnodes are empty
                lane_scatter(stacks, counts+added, first_subnode+1, append_first_subnode)
                added += 1
            }
            counts += added
        }
        spall_end()
        
        link := first_value & cast(lane_Node_Index) hit_mask
        spall_scope("append values")
        for link != 0 {
            length := values_len^
            
            mask := not_equal(link, 0)
            lane_scatter(values, length, link, mask)
            conditional_assign(mask, values_len, length+1)
            when Check do assert(less_than(length, auto_cast len(values)) == lane_true)
            
            // @todo(viktor): @speed each value can only be in one node, sort the values of each node to appear linearly
            // Then only store the first and count, remove next_value from Tree_Value.
            // That way we avoid needing to load the node here only to get the next_value.
            value_node := lane_index(nodes, cast(lane_u32) link)
            value := lane_member(value_node, "value", "next_value", Node_Index) 
            link   = lane_gather(value)
        }
    }
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

hit_triangle :: proc (triangle: Lane(Triangle), ray_o, ray_d: lane_v3, min_t: lane_f32, hit: ^Hit_Info) {
    spall_proc()
    // @note(viktor): if triangle_index == 0 its the Nil triangle
    // then determinant will be zero, so no hit can be registered
    a        := lane_gather_v(lane_member(triangle, "a", v3))
    b        := lane_gather_v(lane_member(triangle, "b", v3))
    c        := lane_gather_v(lane_member(triangle, "c", v3))
    material := lane_gather(  lane_member(triangle, "material", u32))
    
    // @speed pre-compute ab and ac? 
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
    // @todo(viktor): @important Before indices were interpreted as f32(stride=4), when correcting to v3(stride=12) the color of all surfaces is almost black. is this because i misused the brdfs or picked bad brdfs?
    indices = floor(lane_u32, cast(lane_f32) indices / 3)
    
    values_index := lane_gather(lane_member(brdf, "values_index", u32))
    values_count := lane_gather(lane_member(brdf, "values_count", u32))
    values := lane_slice(all_brdf_values, values_index, values_index+values_count)
    
    value  := lane_index(values, indices)
    result := lane_gather_v(value)
    
    return result
}