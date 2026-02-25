#+vet explicit-allocators
package main

import "base:intrinsics"
import os "core:os/os2"
import os_old "core:os"
import "core:simd"
import "core:time"
import "core:math"

Color :: [4] u8

Image:: struct {
    data:   [] Color,
    width:  i32,
    height: i32,
}

BrdfTable :: struct {
    count:  [3] u32,
    // @note(viktor): a view into the World.all_brdf_values array
    values_index: u32,
    values_count: u32,
}

Material :: struct {
    emit:    v3,
    reflect: v3,
    scatter: f32, // 0 = mirror like, 1 = chalk like
    
    brdf:    BrdfTable,
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

World :: struct {
    spheres:   [dynamic] Sphere,
    triangles: [dynamic] Triangle,
    planes:    [dynamic] Plane,
    materials: [dynamic] Material,
    all_brdf_values: [dynamic] v3,
    
    bounces_computed: u64,
    loops_computed:   u64,
    tiles_retired:    u32,
    pixels_done:      u32,
    
    rays_per_pixel:   u32,
    max_bounce_count: u32,
}

Camera :: struct {
    x, y, z: v3,
    p:       v3,
}

Ray :: struct {
    o, d: v3,
}

////////////////////////////////////////////////

do_one_render :: proc (render_allocator: Allocator, image: Image, core_count: i32, world: ^World, camera: Camera, work_queue: ^WorkQueue, create_infos: [] CreateThreadInfo) {
    init_work_queue(work_queue, create_infos[:])

    start := enqueue_render_work(render_allocator, image, core_count, world, camera, work_queue)
    end := wait_for_one_render_to_end(image, world, work_queue)
    
    close_work_queue_and_wait_for_threads(work_queue)
    
    print_render_results(world, start, end)
}

enqueue_render_work :: proc (render_allocator: Allocator, image: Image, core_count: i32, world: ^World, camera: Camera, work_queue: ^WorkQueue) -> time.Time {
    tile_size: v2i = image.width / core_count
    
    tile_cols  := (image.width  + tile_size.x - 1) / tile_size.x
    tile_rows  := (image.height + tile_size.y - 1) / tile_size.y
    tile_count := tile_cols * tile_rows
    
    // print("Configuration: %x% with % cores and % %x% (%/tile) tiles and lane width of % \n", image.width, image.height, core_count, tile_count, tile_size.x, tile_size.y, view_memory_size(tile_size.x * tile_size.y * size_of(Color)), LaneWidth)
    // print("Quality: % rays per pixel with a maximum of % bounces\n", world.rays_per_pixel, world.max_bounce_count)
    
    Work :: struct {
        world:   ^World,
        camera:  Camera,
        image:   Image, 
        rect:    Rectangle2i, 
        entropy: RandomSeries,
    }
    
    works := make_slice(render_allocator, [] Work, tile_count)
    work_index: u32
    
    start := time.now()
    for row in 0..<tile_rows {
        for col in 0..<tile_cols {
            rect := rectangle_min_dimension(tile_size * {col, row}, tile_size)
            rect  = get_intersection(rect, rectangle_min_dimension(i32(0), 0, image.width, image.height))
            
            entropy := seed_random_series(1842098778 + row * 984612097 + col * 237711 + cast(i32) work_index)
            
            work := &works[work_index]
            work_index += 1
            work ^= { world, camera, image, rect, entropy }
            
            enqueue_work_or_do_immediatly(work_queue, proc(work: ^Work) {
                render_tile(work.world, work.camera, work.image, work.rect, &work.entropy)
            }, work)
        }
    }
    return start
}

wait_for_one_render_to_end :: proc (image: Image, world: ^World, work_queue: ^WorkQueue) -> time.Time {
    {
        total_pixels := image.width * image.height
        for work_queue.completion_count != work_queue.completion_goal {
            print_to_console("                                 \r % %% done", view_percentage_ratio(cast(f32) world.pixels_done / cast(f32) (total_pixels)), console = os_old.stderr)
        }
        print_to_console("\n", console = os_old.stderr)
    }
    complete_all_work(work_queue)
    end := time.now()
    
    return end
}

print_render_results :: proc (world: ^World, start, end: time.Time) {
    total_time := time.diff(start, end)
    bounces_computed := volatile_load(&world.bounces_computed)
    loops_computed   := volatile_load(&world.loops_computed)
    wasted_bounces   := loops_computed - bounces_computed
    nanoseconds := time.duration_nanoseconds(total_time) / cast(i64) bounces_computed
    print("Raycasting time: %s\n  bounces %\n  total bounces %\n  wasted bounces % (% %%)\n  time per ray %\n", 
    time.duration_seconds(total_time), 
    view_magnitude(bounces_computed), 
    view_magnitude(loops_computed), 
    view_magnitude(wasted_bounces), view_percentage_ratio(cast(f32) wasted_bounces / cast(f32) loops_computed), 
    cast(time.Duration) nanoseconds)
}

////////////////////////////////////////////////

load_brdf_merl :: proc (filename: string, dest: ^BrdfTable, all_brdf_values: ^[dynamic] v3) {
    spall_proc()
    
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

render_tile :: proc(world: ^World, camera: Camera, image: Image, rect: Rectangle2i, entropy: ^RandomSeries) {
    film_distance :: 1
    film_center := vec_cast(lane_f32, camera.p - film_distance * camera.z)
    
    film_w: f32 = 1
    film_h: f32 = 1
    
    if image.width > image.height {
        film_w = film_h * cast(f32) image.width / cast(f32) image.height
    } else if image.width < image.height {
        film_h = film_w * cast(f32) image.height / cast(f32) image.width
    }
    
    half_film_w: f32 = .5 * film_w
    half_film_h: f32 = .5 * film_h
    
    pixel_size := 1. / vec_cast(lane_f32, image.width, image.height)
    
    bounces_computed, loops_computed: u64
    
    for py in rect.min.y ..< rect.max.y {
        film_y := -1 + 2 * cast(f32) py / cast(f32) image.height
        for px in rect.min.x ..< rect.max.x {
            film_x := -1 + 2 * cast(f32) px / cast(f32) image.width
            
            final_color, bounces_computed_now, loops_computed_now := cast_rays(world, film_x, film_y, entropy, pixel_size, half_film_w, half_film_h, film_center, camera)
            bounces_computed += bounces_computed_now
            loops_computed   += loops_computed_now
            
            final_color = linear_to_srgb(final_color)
            final_color *= 255
            pixel := V4(final_color, 255)
            
            p := &image.data[(image.height - 1 - py) * image.width + px]
            p ^= round(u8, pixel)
        }
        atomic_add(&world.pixels_done, auto_cast get_dimension(rect).x)
    }
    
    atomic_add(&world.bounces_computed, bounces_computed)
    atomic_add(&world.loops_computed, loops_computed)
    atomic_add(&world.tiles_retired, 1)
}

cast_rays :: proc (world: ^World, film_x, film_y: f32, entropy: ^RandomSeries,  pixel_size: lane_v2, half_film_w, half_film_h: f32, film_center: lane_v3, camera: Camera) -> (final_color: v3, bounces_computed, loops_computed: u64) {
    spall_proc()
    
    final_color_lanes: lane_v3
    bounces_computed_lanes: lane_u32
    loops_computed_lanes: lane_u32
    
    max_bounce_count := world.max_bounce_count
    rays_per_pixel   := world.rays_per_pixel
    
    lane_ray_count := rays_per_pixel / LaneWidth
    sample_contribution_factor := 1.0 / cast(f32) rays_per_pixel
    
    camera_p := vec_cast(lane_f32, camera.p)
    camera_x := vec_cast(lane_f32, camera.x)
    camera_y := vec_cast(lane_f32, camera.y)
    
    for _ in 0..<lane_ray_count {
        jitter := random_unilateral(entropy, lane_v2)
        offset := lane_v2{film_x, film_y} + jitter * pixel_size
        film_p := film_center + (offset.x*camera_x*half_film_w + offset.y*camera_y * half_film_h) 
        
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
                denom_mask := less_than(denom, -tolerance) | greater_than(denom, tolerance)
                
                if denom_mask == lane_false do continue
                
                t := dot(plane_normal, center - ray_o) / denom
                t_mask := greater_than(t, min_t) & less_than(t, closest_t)
                if t_mask == lane_false do continue
                
                hit_point := ray_o + t * ray_d
                local_hit := hit_point - center
                t_mask &= less_than(simd.abs(local_hit.x), radius) 
                t_mask &= less_than(simd.abs(local_hit.y), radius)
                t_mask &= less_than(simd.abs(local_hit.z), radius)
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
            
            for &triangle in world.triangles {
                a := vec_cast(lane_f32, triangle.a)
                b := vec_cast(lane_f32, triangle.b)
                c := vec_cast(lane_f32, triangle.c)
                
                ab := b - a
                ac := c - a
                ray_cross_ac := cross(ray_d, ac)
                determinant  := dot(ab, ray_cross_ac)
                
                not_parallel_mask := ~approximate_equal(determinant, 0, 0.0000001)
                if not_parallel_mask == lane_false do continue
                
                inv_determinant := 1.0 / determinant
                s := ray_o - a
                u := inv_determinant * dot(s, ray_cross_ac)
                
                u_mask := greater_equal(u, 0) & less_equal(u, 1)
                if u_mask == lane_false do continue
                
                s_cross_ab := cross(s, ab)
                v := inv_determinant * dot(ray_d, s_cross_ab)
                
                v_mask := greater_equal(v, 0) & less_equal(u + v, 1)
                if v_mask == lane_false do continue
                
                t := inv_determinant * dot(ac, s_cross_ab)
                t_mask := greater_than(t, min_t) & less_than(t, closest_t)
                if t_mask == lane_false do continue
                
                hit_mask := not_parallel_mask & u_mask & v_mask & t_mask
                
                // @note(viktor): Assuming counter-clockwise winding order
                triangle_normal   := normalize_or_zero(cross(ab, ac))
                triangle_tangent  := normalize_or_zero(ab)
                triangle_binormal := normalize_or_zero(cross(triangle_normal, triangle_tangent))
                
                conditional_assign(hit_mask, &closest_t, t)
                conditional_assign(hit_mask, &did_hit, lane_true)
                
                conditional_assign(hit_mask, &hit_material_index, triangle.material)
                
                conditional_assign(hit_mask, &next_o, ray_o + t*ray_d)
                
                conditional_assign(hit_mask, &normal,   triangle_normal)
                conditional_assign(hit_mask, &tangent,  triangle_tangent)
                conditional_assign(hit_mask, &binormal, triangle_binormal)
            }
            
            for &sphere in world.spheres {
                center := vec_cast(lane_f32, sphere.center)
                locale_origin := ray_o - center
                
                a := dot(ray_d, ray_d)
                b := 2 * dot(locale_origin, ray_d)
                c := dot(locale_origin, locale_origin) - square(sphere.radius) 
                
                root := square_root(square(b) - 4*a*c)
                tolerance :: 0.00001
                root_mask := greater_equal(root, 0)
                
                if root_mask == lane_false do continue
                
                t_pos := (-b + root) / (2 * a)
                t_neg := (-b - root) / (2 * a)
                
                t := t_pos
                pick_mask := greater_than(t_neg, min_t) & less_than(t_neg, t)
                conditional_assign(pick_mask, &t, t_neg)
                
                t_mask   := greater_than(t, min_t) & less_than(t, closest_t)
                
                if t_mask == lane_false do continue
                
                hit_mask := root_mask & t_mask
                
                conditional_assign(hit_mask, &closest_t, t)
                conditional_assign(hit_mask, &did_hit, 0xffffffff)
                
                conditional_assign(hit_mask, &hit_material_index, sphere.material)
                
                // @todo(viktor): reuse the next_origin calculation
                conditional_assign(hit_mask, &next_o, ray_o + t*ray_d)
                conditional_assign(hit_mask, &normal, normalize_or_zero(next_o - center))
                
                s_tangent  := normalize_or_zero(cross(lane_v3{0, 0, 1}, normal))
                s_binormal := cross(normal, s_tangent)
                
                conditional_assign(hit_mask, &tangent,   s_tangent)
                conditional_assign(hit_mask, &binormal, s_binormal)
            }
            
            ////////////////////////////////////////////////
            
            hit_emit    := gather(world.materials[:], hit_material_index, "emit",    type_of(Material{}.emit), lane_v3)
            hit_reflect := gather(world.materials[:], hit_material_index, "reflect", type_of(Material{}.reflect), lane_v3)
            hit_scatter := gather(world.materials[:], hit_material_index, "scatter", type_of(Material{}.scatter), lane_f32)
            
            // only allow world.no_hit on the first time we didnt hit anything
            // @todo(viktor): make this a helper I guess
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

brdf_lookup :: proc (all_brdf_values: [] v3, materials: [] Material, index: lane_u32, view_direction, normal, tangent, binormal, light_direction: lane_v3) -> lane_v3 {
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
    
    // @note(viktor): materials[index].brdf.count
    offset_count :: offset_of(BrdfTable, count)
    table := array_index_member(materials, index, "brdf")
    
    count: lane_uv3
    count[0] = gather_no_mask(cast(lane_pmm) (table + offset_count + size_of(BrdfTable{}.count[0]) * 0), lane_u32)
    count[1] = gather_no_mask(cast(lane_pmm) (table + offset_count + size_of(BrdfTable{}.count[0]) * 1), lane_u32)
    count[2] = gather_no_mask(cast(lane_pmm) (table + offset_count + size_of(BrdfTable{}.count[0]) * 2), lane_u32)
    
    f: lane_v3
    for lane in 0..<LaneWidth {
        // @speed this is the most expensive part of the whole brdf_lookup
        theta_half := acos(extract(hw.z, lane))
        theta_diff := acos(extract(diff_z_inner, lane))
        phi_diff   := atan2(extract(diff_y_inner, lane), extract(diff_x_inner, lane))
        if phi_diff < 0 do phi_diff += Pi
                
        // @note(viktor): after the divide and clamp any NaNs will be zero in the scalar code, but Intels max_ps/min_ps do not work the same way, so we need to filter them out manually.
        if math.is_nan(theta_half) do theta_half = 0
        if math.is_nan(theta_diff) do theta_diff = 0
        
        replace(&f[0], lane, theta_half)
        replace(&f[1], lane, theta_diff)
        replace(&f[2], lane, phi_diff)
    }
    
    f[0] = square_root(clamp_01(f[0] / (.5 * Pi)))
    f[1] =             clamp_01(f[1] / (.5 * Pi))
    f[2] =             clamp_01(f[2] / (     Pi))
    
    round_positive :: proc ($T: typeid, x: $X) -> T {
        result := cast(T) (x + 0.5)
        return result
    }
    
    i: lane_uv3
    i[0] = round_positive(lane_u32, f[0] * cast(lane_f32) (count[0]-1))
    i[1] = round_positive(lane_u32, f[1] * cast(lane_f32) (count[1]-1))
    i[2] = round_positive(lane_u32, f[2] * cast(lane_f32) (count[2]-1))
    
    indices := cast(lane_umm) ((i[2]) + (i[1] * count[2]) + (i[0] * count[2] * count[1]))
    indices *= size_of(f32)
    
    // @note(viktor): materials[index].brdf.values
    offset_values :: offset_of(BrdfTable, values_index)
    values_index  := gather_no_mask(cast(lane_pmm) (table + offset_values), lane_u32)
    
    pointers := array_index(all_brdf_values, values_index) + indices
    
    result: lane_v3
    result.r = gather_no_mask(cast(lane_pmm) (pointers + size_of(f32) * 0), lane_f32)
    result.g = gather_no_mask(cast(lane_pmm) (pointers + size_of(f32) * 1), lane_f32)
    result.b = gather_no_mask(cast(lane_pmm) (pointers + size_of(f32) * 2), lane_f32)
    
    return result
}

gather :: proc (array: [] $T, index: lane_u32, $member: string, $member_type: typeid, $Result: typeid) -> (result: Result) {
    pointer := array_index_member(array, index, member)
    
    when Result == lane_v3 {
        ResultElement :: intrinsics.type_elem_type(Result)
        channel :: size_of(intrinsics.type_elem_type(member_type))
        #unroll for channel_index in cast(umm) 0..<len(result) {
            result[channel_index] = cast(ResultElement) gather_no_mask(cast(lane_pmm) (pointer + channel * channel_index), lane_f32)
        }
    } else when Result == lane_f32 {
        result = cast(Result) gather_no_mask(cast(lane_pmm) pointer, Result)
    } else when Result == lane_u32 {
        result = cast(Result) gather_no_mask(cast(lane_pmm) pointer, Result)
    } else do #panic("unhandled")
    
    return result
}

gather_no_mask :: proc (pointer: lane_pmm, $T: typeid) -> T {
    result := simd.gather(pointer, cast(T) 0, lane_true)
    return result
}

array_index :: proc (array: [] $T, index: lane_u32) -> lane_umm {
    base   := cast(lane_umm) raw_data(array)
    offset := cast(lane_umm) index * size_of(T)
    return base + offset
}

array_index_member :: proc (array: [] $T, index: lane_u32, $member: string) -> lane_umm {
    base   := cast(lane_umm) raw_data(array)
    offset := cast(lane_umm) index * size_of(T)
    member := offset_of_by_string(T, member)
    return base + offset + member
}
