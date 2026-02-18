package main

import "base:intrinsics"
import os "core:os/os2"
import os_old "core:os"
import "core:simd"
import "core:time"

import img "vendor:stb/image"

Color :: [4] u8

Image:: struct {
    data:          [] Color,
    width, height: i32,
}

BrdfTable :: struct {
    count:  [3] u32,
    values: [] v3,
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
    core_count := cast(i32) os_old.processor_core_count() - 1
    
    world: World
    world.ray_per_pixel = 1024
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
    
    load_brdf_merl("", &world.materials[0].brdf)
    load_brdf_merl("./BRDFDatabase/brdfs/gray-plastic.binary", &world.materials[1].brdf)
    load_brdf_merl("./BRDFDatabase/brdfs/brass.binary",       &world.materials[2].brdf)
    load_brdf_merl("./BRDFDatabase/brdfs/gold-paint.binary",   &world.materials[3].brdf)
    load_brdf_merl("./BRDFDatabase/brdfs/green-latex.binary",  &world.materials[4].brdf)
    load_brdf_merl("./BRDFDatabase/brdfs/purple-paint.binary", &world.materials[5].brdf)
    load_brdf_merl("./BRDFDatabase/brdfs/white-marble.binary", &world.materials[6].brdf)
    
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
        world:  ^World,
        camera: Camera,
        image:  Image, 
        rect:   Rectangle2i, 
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
            work ^= { &world, camera, image, rect, seed_random_series(1842098778 + row * 984612097 + col * 237711 + cast(i32) work_index)}
            
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
    print("Raycasting time: %\n  bounces %\n  total bounces %\n  wasted bounces % (% %%)\n  time per ray %\n", 
            total_time, 
            view_magnitude(bounces_computed), 
            view_magnitude(loops_computed), 
            view_magnitude(wasted_bounces), view_percentage_ratio(cast(f32) wasted_bounces / cast(f32) loops_computed), 
            cast(time.Duration) nanoseconds)
    
    
    output_path := "./render.bmp"
    img.write_bmp(ctprint("%", output_path), image.width, image.height, 4, &image.data[0])
    cwd, _ := os.get_working_directory(context.temp_allocator)
    print("Wrote ouput to %/%", cwd, output_path)
}

load_brdf_merl :: proc (filename: string, dest: ^BrdfTable) {
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
        dest.count, data = (cast(^[3]u32) &data[0])^, data[size_of([3] u32):]
        
        total_count := dest.count[0] * dest.count[1] * dest.count[2]
        temp_values := (cast([^]f64) &data[0])[:total_count * len(v3)]
        // :BelowHorizon we currently check and handle negative values in the raytracer by defaulting to no color , but this could be handled here right?
        
        file_size := cast(umm) &data[0] + auto_cast len(data)
        read_size := cast(umm) &temp_values[0] + auto_cast len(temp_values) * size_of(f64)
        assert(file_size == read_size)
        
        dest.values = make([] v3, total_count)
        for i in 0..<total_count {
            dest.values[i].r = cast(f32) temp_values[i + total_count * 0]
            dest.values[i].g = cast(f32) temp_values[i + total_count * 1]
            dest.values[i].b = cast(f32) temp_values[i + total_count * 2]
        }
    } else {
        dest.count = 1
        dest.values = make([] v3, 1)
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
            
            // atomic_add(&world.pixels_done, 1)
        }
        atomic_add(&world.pixels_done, auto_cast get_dimension(rect).x)
    }
    
    atomic_add(&world.bounces_computed, bounces_computed)
    atomic_add(&world.loops_computed, loops_computed)
    atomic_add(&world.tiles_retired, 1)
}

cast_rays :: proc (world: ^World, film_x, film_y: f32, entropy: ^RandomSeries,  pixel_size: lane_v2, half_film_w, half_film_h: f32, film_center: lane_v3, camera: Camera) -> (final_color: v3, bounces_computed, loops_computed: u64) {
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
            
            reflectance := brdf_lookup(world.materials[:], hit_mat_index, -ray_d, normal, tangent, binormal, next_d)
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

gather :: proc (materials: [] Material, index: lane_u32, $member: string, $T: typeid) -> (result: T) {
    mask: lane_u32 : 0xffffffff
    
    member_offset :: offset_of_by_string(Material, member)
    
    array  := cast(lane_umm) &materials[0]
    index  := cast(lane_umm) index * size_of(Material)
    
    when T == lane_v3 {
        channel :: size_of(lane_f32)
        result.r = simd.gather(cast(lane_pmm) (array + index + member_offset + channel * 0), cast(lane_f32) 0, mask)
        result.g = simd.gather(cast(lane_pmm) (array + index + member_offset + channel * 1), cast(lane_f32) 0, mask)
        result.b = simd.gather(cast(lane_pmm) (array + index + member_offset + channel * 2), cast(lane_f32) 0, mask)
    } else when T == lane_f32 {
        result   = simd.gather(cast(lane_pmm) (array + index + member_offset), cast(lane_f32) 0, mask)
    } else do #panic("unhandled")
    
    return result
}

brdf_lookup :: proc (materials: [] Material, index: lane_u32, view_direction, normal, tangent, binormal, light_direction: lane_v3) -> (result: lane_v3) {
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
    
    for lane in 0..<LaneWidth {
        theta_half := acos(extract(hw.z, lane))
        
        theta_diff := acos(extract(diff_z_inner, lane))
        phi_diff   := atan2(extract(diff_y_inner, lane), extract(diff_x_inner, lane))

        if phi_diff < 0 do phi_diff += Pi
        
        table := materials[extract(index, lane)].brdf
        
        f0 := square_root(clamp_01(theta_half / (.5 * Pi)))
        i0 := round(u32, f0 * cast(f32) (table.count[0]-1))
        
        f1 := clamp_01(theta_diff / (.5 * Pi))
        i1 := round(u32, f1 * cast(f32) (table.count[1]-1))
        
        f2 := clamp_01(phi_diff / Pi)
        i2 := round(u32, f2 * cast(f32) (table.count[2]-1))
        
        // @todo(viktor): build the indices then do a wide load
        brdf_index := (i2) + (i1 * table.count[2]) + (i0 * table.count[2] * table.count[1])
        
        color := table.values[brdf_index/len(v3)]
        // @note(viktor): a value of -1 indicates that the reflection would be below the horizon :BelowHorizon
        color = max_vec(color, 0)
        
        BRDF_Scale :: v3 {
            1.00/1500.0, 
            1.15/1500.0, 
            1.66/1500.0
        }
        color *= BRDF_Scale
        
        replace_v3(&result, lane, color)
    }
    
    return result
}