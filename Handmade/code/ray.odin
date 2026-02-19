package main

import "base:intrinsics"
import os "core:os/os2"
import os_old "core:os"
import "core:simd"
import "core:time"
import "core:math"

import img "vendor:stb/image"

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
    emit:    lane_v3,
    reflect: lane_v3,
    scatter: f32, // 0 = mirror like, 1 = chalk like
    
    brdf:    BrdfTable,
}

Plane :: struct {
    normal, tangent, binormal: lane_v3,
    center: lane_v3,
    radius: lane_f32,
    material: u32,
}

Sphere :: struct {
    center:   lane_v3,
    radius:   f32,
    material: u32,
}

World :: struct {
    spheres:   [dynamic] Sphere,
    planes:    [dynamic] Plane,
    all_brdf_values: [dynamic] v3,
    materials: [] Material,
    
    bounces_computed: u64,
    loops_computed:   u64,
    tiles_retired:    u32,
    pixels_done:      u32,
    
    ray_per_pixel:    u32,
    max_bounce_count: u32,
}

Camera :: struct {
    x, y, z: lane_v3,
    p:       lane_v3,
}

Ray :: struct {
    o, d: v3,
}

main :: proc() {
    init_spall()
    
    core_count := cast(i32) os_old.processor_core_count() - 1
    
    world: World
    world.ray_per_pixel = 2048
    world.max_bounce_count = 8

    world.materials = {
        { emit    = { .3 , .4 , .5 },              },
        { reflect = { .5 , .5 , .5 }, scatter = .1 },
        { reflect = { .7 , .5 , .3 }, scatter = 1. },
        { emit    = { 3.5 , 2.0 ,  .5 }, scatter = 1. },
        { reflect = { .2 , .8 , .2 }, scatter = .3 },
        { reflect = { .65, .1 , .7 }, scatter = .9 },
        { reflect = { .9 , .9 , .8 }, scatter = .6 },
    
    }
    
    load_brdf_merl("",                                         &world.materials[0].brdf, &world.all_brdf_values)
    load_brdf_merl("./BRDFDatabase/brdfs/gray-plastic.binary", &world.materials[1].brdf, &world.all_brdf_values)
    load_brdf_merl("./BRDFDatabase/brdfs/brass.binary",        &world.materials[2].brdf, &world.all_brdf_values)
    load_brdf_merl("./BRDFDatabase/brdfs/gold-paint.binary",   &world.materials[3].brdf, &world.all_brdf_values)
    load_brdf_merl("./BRDFDatabase/brdfs/green-latex.binary",  &world.materials[4].brdf, &world.all_brdf_values)
    load_brdf_merl("./BRDFDatabase/brdfs/purple-paint.binary", &world.materials[5].brdf, &world.all_brdf_values)
    load_brdf_merl("./BRDFDatabase/brdfs/white-marble.binary", &world.materials[6].brdf, &world.all_brdf_values)
    
    append(&world.planes,  Plane  { normal = {0,0,1}, center = { 0, 0, 0}, radius = PositiveInfinity, material = 6 })
    append(&world.planes,  Plane  { normal = {1,0,0}, center = {-2, 0, 0}, radius = 6, material = 4 })
    
    append(&world.spheres, Sphere { center = { 0, 0, 0}, radius = 1, material = 2 })
    append(&world.spheres, Sphere { center = { 3,-2, 0.4}, radius = .1, material = 3 })
    append(&world.spheres, Sphere { center = {-2,-1, 2}, radius = 1, material = 1 })
    append(&world.spheres, Sphere { center = { 1,-1, 3}, radius = 1, material = 5 })
    append(&world.spheres, Sphere { center = {-2, 3, 0}, radius = 2, material = 6 })
    
    
    camera: Camera
    camera.p = lane_v3{0, -7, 1}
    camera.z = normalize_or_zero(camera.p)
    camera.x = normalize_or_zero(cross(lane_v3{0, 0, 1}, camera.z))
    camera.y = normalize_or_zero(cross(camera.z, camera.x))
    
    
    image: Image
    image.width  = 1920
    image.height = 1080
    image.data = make([]Color, image.width * image.height)
    
    tile_size: v2i = image.width / core_count
    
    tile_cols := (image.width  + tile_size.x - 1) / tile_size.x
    tile_rows := (image.height + tile_size.y - 1) / tile_size.y
    tile_count := tile_cols * tile_rows
    
    print("Configuration: % cores with % %x% (%/tile) tiles and lane width of % \n", core_count, tile_count, tile_size.x, tile_size.y, view_memory_size(tile_size.x * tile_size.y * size_of(Color)), LaneWidth)
    print("Quality: % rays per pixel with a maximum of % bounces\n", world.ray_per_pixel, world.max_bounce_count)
    
    
    Work :: struct {
        world:   ^World,
        camera:  Camera,
        image:   Image, 
        rect:    Rectangle2i, 
        entropy: RandomSeries,
    }
    
    work_queue: WorkQueue
    create_infos := make([] CreateThreadInfo, core_count)
    init_work_queue(&work_queue, create_infos[:])
    
    works := make([]Work, tile_count)
    work_index: u32
    
    start := time.now()
    for row in 0..<tile_rows {
        for col in 0..<tile_cols {
            rect := rectangle_min_dimension(tile_size * {col, row}, tile_size)
            rect = get_intersection(rect, rectangle_min_dimension(i32(0), 0, image.width, image.height))
            
            work := &works[work_index]
            work_index += 1
            work ^= { 
                &world, 
                camera, 
                image, 
                rect, 
                seed_random_series(1842098778 + row * 984612097 + col * 237711 + cast(i32) work_index),
            }
            
            enqueue_work_or_do_immediatly(&work_queue, proc(work: ^Work) {
                render_tile(work.world, work.camera, work.image, work.rect, &work.entropy)
            }, work)
        }
    }
    
    {
        total_pixels := image.width * image.height
        for work_queue.completion_count != work_queue.completion_goal {
            print_to_console("                                 \r % %% done", view_percentage_ratio(cast(f32) world.pixels_done / cast(f32) (total_pixels)), console = os_old.stderr)
        }
        print_to_console("\n", console = os_old.stderr)
    }
    complete_all_work(&work_queue)
    end := time.now()
    
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
    
    output_path := "./render.bmp"
    img.write_bmp(ctprint("%", output_path), image.width, image.height, 4, &image.data[0])
    cwd, _ := os.get_working_directory(context.temp_allocator)
    print("Wrote ouput to %/%", cwd, output_path)
    
    close_work_queue_and_wait_for_threads(&work_queue)
}

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
    
    if !invalid {
        dest.count, data = (cast(^uv3) &data[0])^, data[size_of(uv3):]
        
        total_count := dest.count[0] * dest.count[1] * dest.count[2]
        temp_values := (cast([^]f64) &data[0])[:total_count * len(v3)]
        // :BelowHorizon we currently check and handle negative values in the raytracer by defaulting to no color , but this could be handled here right?
        
        file_size := cast(umm) &data[0] + auto_cast len(data)
        read_size := cast(umm) &temp_values[0] + auto_cast len(temp_values) * size_of(f64)
        assert(file_size == read_size)
        
        dest.values_index = cast(u32) len(all_brdf_values)
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
        dest.values_index = cast(u32) len(all_brdf_values)
        dest.values_count = 1
        
        dest.count = 1
        append(all_brdf_values, v3{1,1,1})
    }
}

render_tile :: proc(world: ^World, camera: Camera, image: Image, rect: Rectangle2i, entropy: ^RandomSeries) {
    film_distance :: 1
    film_center := camera.p - film_distance * camera.z
    
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
    rays_per_pixel   := world.ray_per_pixel
    
    lane_ray_count := rays_per_pixel / LaneWidth
    sample_contribution_factor := 1.0 / cast(f32) rays_per_pixel
    
    for _ in 0..<lane_ray_count {
        jitter := random_unilateral(entropy, lane_v2)
        off := lane_v2{film_x, film_y} + jitter * pixel_size
        film_p := film_center + (off.x*camera.x*half_film_w + off.y*camera.y * half_film_h) 
        
        ray_o := camera.p
        ray_d := normalize_or_zero(film_p - camera.p)
        
        min_t: lane_f32 = 0.0001
        attenuation: lane_v3 = 1
        lane_mask: lane_u32 = 0xffffffff
        sample: lane_v3
        for _ in 0..<max_bounce_count {
            closest_t: lane_f32 = PositiveInfinity
            
            hit_mat_index: lane_u32
            did_hit: lane_u32
            
            next_o: lane_v3
            
            normal:   lane_v3
            tangent:  lane_v3
            binormal: lane_v3
            
            bounces_computed_lanes += 1 & lane_mask
            loops_computed_lanes += 1
            
            for &plane in world.planes {
                tolerance :: 0.00001
                
                denom := dot(plane.normal, ray_d)
                denom_mask := less_than(denom, -tolerance) | greater_than(denom, tolerance)
                
                if denom_mask == 0 do continue
                
                t := dot(plane.normal, plane.center - ray_o) / denom
                t_mask := greater_than(t, min_t) & less_than(t, closest_t)
                if t_mask == 0 do continue
                
                hit_point := ray_o + t * ray_d
                local_hit := hit_point - plane.center
                t_mask &= less_than(simd.abs(local_hit.x), plane.radius) & less_than(simd.abs(local_hit.y), plane.radius)
                if t_mask == 0 do continue
                
                hit_mask := denom_mask & t_mask
                
                conditional_assign(hit_mask, &closest_t, t)
                conditional_assign(hit_mask, &did_hit, 0xffffffff)
                
                conditional_assign(hit_mask, &hit_mat_index, plane.material)
                
                conditional_assign(hit_mask, &next_o, ray_o + t*ray_d)
                
                conditional_assign(hit_mask, &normal,   plane.normal)
                conditional_assign(hit_mask, &tangent,  plane.tangent)
                conditional_assign(hit_mask, &binormal, plane.binormal)
            }
            
            for &sphere in world.spheres {
                locale_origin := ray_o - sphere.center
                
                a := dot(ray_d, ray_d)
                b := 2 * dot(locale_origin, ray_d)
                c := dot(locale_origin, locale_origin) - square(sphere.radius) 
                
                root := square_root(square(b) - 4*a*c)
                tolerance :: 0.00001
                root_mask := greater_equal(root, 0)
                
                if root_mask == 0 do continue
                
                t_pos := (-b + root) / (2 * a)
                t_neg := (-b - root) / (2 * a)
                
                t := t_pos
                pick_mask := greater_than(t_neg, min_t) & less_than(t_neg, t)
                conditional_assign(pick_mask, &t, t_neg)
                
                t_mask   := greater_than(t, min_t) & less_than(t, closest_t)
                
                if t_mask == 0 do continue
                
                hit_mask := root_mask & t_mask
                
                conditional_assign(hit_mask, &closest_t, t)
                conditional_assign(hit_mask, &did_hit, 0xffffffff)
                
                conditional_assign(hit_mask, &hit_mat_index, sphere.material)
                
                // @todo(viktor): reuse the next_origin calculation
                conditional_assign(hit_mask, &next_o,  ray_o + t*ray_d)
                
                conditional_assign(hit_mask, &normal,    next_o - sphere.center)
                
                s_tangent  := normalize_or_zero(cross(lane_v3{0, 0, 1}, normal))
                s_binormal := cross(normal, s_tangent)
                
                conditional_assign(hit_mask, &tangent,   s_tangent)
                conditional_assign(hit_mask, &binormal, s_binormal)
            }
            
            hit_emit    := gather(world.materials[:], hit_mat_index, "emit",    lane_v3)
            hit_reflect := gather(world.materials[:], hit_mat_index, "reflect", lane_v3)
            hit_scatter := gather(world.materials[:], hit_mat_index, "scatter", lane_f32)
            
            // only allow world.no_hit on the first time we didnt hit anything
            // @todo(viktor): make this a helper I guess
            (cast(^lane_u32) &hit_emit.r)^ &= lane_mask
            (cast(^lane_u32) &hit_emit.g)^ &= lane_mask
            (cast(^lane_u32) &hit_emit.b)^ &= lane_mask
            
            // Color Accumulation
            sample += attenuation * hit_emit
            
            lane_mask &= did_hit
            if lane_mask == 0 {
                break
            }
            // Bounce
            pure_bounce   := reflect(ray_d, normal)
            random_bounce := normalize_or_zero(normal + random_bilateral(entropy, lane_v3))
            
            next_d := linear_blend(pure_bounce, random_bounce, hit_scatter)
            
            reflectance := brdf_lookup(world.all_brdf_values[:], world.materials[:], hit_mat_index, -ray_d, normal, tangent, binormal, next_d)
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

gather :: proc (array: [] $T, index: lane_u32, $member: string, $Result: typeid) -> (result: Result) {
    pointer := array_index_member(array, index, member)
    
    when Result == lane_v3 {
        Element :: type_of(result[0])
        channel :: size_of(Element)
        #unroll for channel_index in cast(umm) 0..<len(result) {
            result[channel_index] = gather_no_mask(cast(lane_pmm) (pointer + channel * channel_index), Element)
        }
    } else when Result == lane_f32 {
        result = gather_no_mask(cast(lane_pmm) pointer, Result)
    } else do #panic("unhandled")
    
    return result
}

gather_no_mask :: proc (pointer: lane_pmm, $T: typeid) -> T {
    result := simd.gather(pointer, cast(T) 0, cast(lane_u32) 0xffffffff)
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
