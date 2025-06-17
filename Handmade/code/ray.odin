package main

import "base:intrinsics"
import "core:time"

import img "vendor:stb/image"

Color :: [4]u8

Image:: struct {
    data:          []Color,
    width, height: i32,
}

Material :: struct {
    emit:    lane_v3,
    reflect: lane_v3,
    scatter: f32, // 0 = mirror like, 1 = chalk like
}

Plane :: struct {
    n: lane_v3,
    d: f32,
    m: Material,
}

Sphere :: struct {
    p: lane_v3,
    r: f32,
    m: Material,
}

World :: struct {
    no_hit:  Material,
    spheres: [dynamic]Sphere,
    planes:  [dynamic]Plane,
    
    bounces_computed: u64,
    loops_computed:   u64,
    tiles_retired:    u32,
    
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
    world: World
    world.no_hit = { emit = {.3, .4, .8} }
    world.ray_per_pixel = 512
    world.max_bounce_count = 8
    
    core_count :: 12 // os.core_count or something
    
    append(&world.planes,  Plane  { n = {0,0,1},  d = 0, m = { reflect = {.2, .2, .2}, scatter = 1. } })
    // append(&world.planes,  Plane  { n = {1,0,0},  d = 3, m = { reflect = {1., 1., 1.}, scatter = 1. } })
    
    append(&world.spheres, Sphere { p = {0,0,1},   r = 0.4, m = { emit    = {5., 5., .0}, scatter = 1. } })
    append(&world.spheres, Sphere { p = {3,-2,0},  r = 1,   m = { reflect = {.9, .0, .0}, scatter = 1. } })
    append(&world.spheres, Sphere { p = {-2,-3,1}, r = 1.3, m = { reflect = {.3, .7, .4}, scatter = .7 } })
    append(&world.spheres, Sphere { p = {0,1,3},   r = 2,   m = { reflect = {.4, .7, .7}, scatter = .3 } })
    append(&world.spheres, Sphere { p = {2,4,0},   r = 3,   m = { reflect = {.4, .7, .7}, scatter = .03 } })
    
    
    camera: Camera
    camera.p = lane_v3{0, -10, 1}
    camera.z = normalize_or_zero(camera.p)
    camera.x = normalize_or_zero(cross(lane_v3{0, 0, 1}, camera.z))
    camera.y = normalize_or_zero(cross(camera.z, camera.x))
    
    
    image: Image
    image.width  = 1920
    image.height = 1080
    image.data = make([]Color, image.width * image.height)
    
    tile_size: [2]i32 = image.width / core_count
    
    tile_cols := (image.width  + tile_size.x - 1) / tile_size.x
    tile_rows := (image.height + tile_size.y - 1) / tile_size.y
    tile_count := tile_cols * tile_rows
    
    println("Configuration: % cores with % %x% (% %/tile) tiles and lane width of % ", core_count, tile_count, tile_size.x, tile_size.y, format_memory_size(tile_size.x * tile_size.y * size_of(Color)), LaneWidth)
    println("Quality: % rays per pixel with a maximum of % bounces", world.ray_per_pixel, world.max_bounce_count)
    
    
    Work :: struct {
        world:  ^World,
        camera: Camera,
        image:  Image, 
        rect:   Rectangle2i, 
        entropy: RandomSeries,
    }
    
    work_queue: WorkQueue
    create_infos: [core_count-1]CreateThreadInfo
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
            
            enqueue_work_or_do_immediatly(&work_queue, proc(using work: ^Work) {
                render_tile(world, camera, image, rect, &entropy)
            }, work)
        }
    }
    complete_all_work(&work_queue)
    end := time.now()
    
    
    total_time := time.diff(start, end)
    bounces_computed := volatile_load(&world.bounces_computed)
    loops_computed   := volatile_load(&world.loops_computed)
    wasted_bounces   := loops_computed - bounces_computed
    nanoseconds := time.duration_nanoseconds(total_time) / cast(i64) bounces_computed
    println("Raycasting time: %\n  bounces % %\n  total bounces % %\n  wasted bounces % % (% %%)\n  time per ray %", 
            total_time, 
            format_order_of_magnitude(bounces_computed), 
            format_order_of_magnitude(loops_computed), 
            format_order_of_magnitude(wasted_bounces), format_percentage(cast(f32) wasted_bounces / cast(f32) loops_computed), 
            cast(time.Duration) nanoseconds)
    
    
    img.write_bmp("./render.bmp", image.width, image.height, 4, &image.data[0])
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
            loops_computed += loops_computed_now
            
            final_color = linear_to_srgb(final_color)
            final_color *= 255
            pixel := V4(final_color, 255)
            
            p := &image.data[(image.height - 1 - py) * image.width + px]
            p ^= round(u8, pixel)
        }
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
    // @todo(viktor): what is this supposed to be?
    contribution_factor: f32 = 1.0 / cast(f32) rays_per_pixel
    
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
            
            hit_emit:    lane_v3
            hit_reflect: lane_v3
            hit_scatter: lane_f32
            
            did_hit: lane_u32
            
            next_o: lane_v3
            next_d: lane_v3
            next_normal: lane_v3
            
            bounces_computed_lanes += 1 & lane_mask
            loops_computed_lanes += LaneWidth
            
            for &plane in world.planes {
                denom := dot(plane.n, ray_d)
                
                tolerance :: 0.00001
                t := ( -plane.d - dot(plane.n, ray_o)) / denom
                denom_mask := less_than(denom, -tolerance) | greater_than(denom, tolerance)
                t_mask     := greater_than(t, min_t) & less_than(t, closest_t)
                hit_mask   := denom_mask & t_mask
                
                conditional_assign(hit_mask, &closest_t, t)
                conditional_assign(hit_mask, &did_hit, 0xffffffff)
                
                conditional_assign(hit_mask, &hit_emit,    plane.m.emit)
                conditional_assign(hit_mask, &hit_reflect, plane.m.reflect)
                conditional_assign(hit_mask, &hit_scatter, plane.m.scatter)
                
                conditional_assign(hit_mask, &next_o, ray_o + t*ray_d)
                conditional_assign(hit_mask, &next_normal, plane.n)
            }
            
            for &sphere in world.spheres {
                locale_origin := ray_o - sphere.p
                
                a := dot(ray_d, ray_d)
                b := 2 * dot(locale_origin, ray_d)
                c := dot(locale_origin, locale_origin) - square(sphere.r) 
                
                root := square_root(square(b) - 4*a*c)
                tolerance :: 0.00001
                root_mask := greater_equal(root, 0)
                
                t_pos := (-b + root) / 2 * a
                t_neg := (-b - root) / 2 * a
                
                t := t_pos
                pick_mask := greater_than(t_neg, min_t) & less_than(t_neg, t)
                conditional_assign(pick_mask, &t, t_neg)
                
                t_mask   := greater_than(t, min_t) & less_than(t, closest_t)
                hit_mask := root_mask & t_mask
                
                conditional_assign(hit_mask, &closest_t, t)
                conditional_assign(hit_mask, &did_hit, 0xffffffff)
                
                conditional_assign(hit_mask, &hit_emit,    sphere.m.emit)
                conditional_assign(hit_mask, &hit_reflect, sphere.m.reflect)
                conditional_assign(hit_mask, &hit_scatter, sphere.m.scatter)
                
                // @todo(viktor): reuse the next_origin calculation
                conditional_assign(hit_mask, &next_o, ray_o + t*ray_d)
                conditional_assign(hit_mask, &next_normal, next_o - sphere.p)
            }
            
            
            // Color Accumulation
            emit := world.no_hit.emit
            // only allow world.no_hit on the first time we didnt hit anything
            (cast(^lane_u32) &emit.r)^ &= lane_mask
            (cast(^lane_u32) &emit.g)^ &= lane_mask
            (cast(^lane_u32) &emit.b)^ &= lane_mask
            
            conditional_assign(did_hit, &emit, hit_emit)
            
            sample += attenuation * emit
            
            angle_attenuation := dot(-ray_d, next_normal)
            angle_attenuation = maximum(angle_attenuation, 0)
            conditional_assign(did_hit, &attenuation, attenuation * angle_attenuation * hit_reflect)
            
            // Bounce
            pure_bounce   := reflect(ray_d, next_normal)
            scatter       := random_bilateral(entropy, lane_v3)
            random_bounce := normalize_or_zero(next_normal + scatter)
            
            ray_d = linear_blend(pure_bounce, random_bounce, hit_scatter)
            ray_o = next_o
            
            lane_mask &= did_hit
            if lane_mask == 0 do break
        }
        
        final_color_lanes += contribution_factor * sample
    }
    
    final_color.r = horizontal_add(final_color_lanes.r)
    final_color.g = horizontal_add(final_color_lanes.g)
    final_color.b = horizontal_add(final_color_lanes.b)
    
    return final_color, cast(u64) horizontal_add(bounces_computed_lanes), cast(u64) horizontal_add(loops_computed_lanes)
}