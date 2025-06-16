package main

import "core:fmt"
import "core:time"

import img "vendor:stb/image"

Color :: [4]u8

Image:: struct {
    data:          []Color,
    width, height: i32,
}

Material :: struct {
    emit:    v3,
    reflect: v3,
    scatter: f32, // 0 = mirror like, 1 = chalk like
}

Plane :: struct {
    n: v3,
    d: f32,
    m: Material,
}

Sphere :: struct {
    p: v3,
    r: f32,
    m: Material,
}

World :: struct {
    no_hit:  Material,
    spheres: [dynamic]Sphere,
    planes:  [dynamic]Plane,
    
    entropy: RandomSeries,
    
    bounces_computed: u64,
    tiles_retired:    u32,
    
    ray_per_pixel: u32,
    max_bounce_count: u32,
}

Camera :: struct {
    x,y,z: v3,
    p:     v3,
}

Ray :: struct {
    o, d: v3,
}

main :: proc() {
    
    world: World
    world.no_hit = { emit = {.3, .4, .8} }
    world.entropy = seed_random_series(123)
    world.ray_per_pixel = 256
    world.max_bounce_count = 8
    
    
    append(&world.planes,  Plane  { n = {0,0,1},  d = 0, m = { reflect = {.2, .2, .2}, scatter = 1. } })
    append(&world.planes,  Plane  { n = {1,0,0},  d = 3, m = { reflect = {1., 1., 1.}, scatter = 1. } })
    
    append(&world.spheres, Sphere { p = {0,0,1},   r = 0.4, m = { emit    = {5., 5., .0}, scatter = 1. } })
    append(&world.spheres, Sphere { p = {3,-2,0},  r = 1,   m = { reflect = {.9, .0, .0}, scatter = 1. } })
    append(&world.spheres, Sphere { p = {-2,-3,1}, r = 1.3, m = { reflect = {.3, .7, .4}, scatter = .7 } })
    append(&world.spheres, Sphere { p = {0,1,3},   r = 2,   m = { reflect = {.4, .7, .7}, scatter = .3 } })
    append(&world.spheres, Sphere { p = {2,4,0},   r = 3,   m = { reflect = {.4, .7, .7}, scatter = .03 } })
    
    camera: Camera
    camera.p = v3{0, -10, 1}
    camera.z = normalize_or_zero(camera.p)
    camera.x = normalize_or_zero(cross(v3{0, 0, 1}, camera.z))
    camera.y = normalize_or_zero(cross(camera.z, camera.x))
    
    image: Image
    image.width  = 1920
    image.height = 1080
    image.data = make([]Color, image.width * image.height)
        
    core_count :i32: 12 // os.core_count or something
    tile_size :[2]i32= image.width / core_count
    
    tile_cols := (image.width  + tile_size.x - 1) / tile_size.x
    tile_rows := (image.height + tile_size.y - 1) / tile_size.y
    tile_count := tile_cols * tile_rows
    
    println("Configuration: % cores with % %x% (% %/tile) tiles ", core_count, tile_count, tile_size.x, tile_size.y, format_memory_size(tile_size.x * tile_size.y * size_of(Color)))
    println("Quality: % rays per pixel with a maximum of % bounces", world.ray_per_pixel, world.max_bounce_count)
    
    Work :: struct {
        world: ^World,
        camera: Camera,
        image: Image, 
        rect: Rectangle2i, 
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
            work ^= { &world, camera, image, rect}
            
            enqueue_work_or_do_immediatly(&work_queue, proc(using work: ^Work) {
                render_tile(world, camera, image, rect)
            }, work)
        }
    }
    complete_all_work(&work_queue)
    end := time.now()
    
    total_time := time.diff(start, end)
    bounces_computed := volatile_load(&world.bounces_computed)
    nanoseconds := time.duration_nanoseconds(total_time) / cast(i64) bounces_computed
    println("\nRaycasting time: % - total rays cast % % - time per ray %", total_time, format_order_of_magnitude(bounces_computed), cast(time.Duration) nanoseconds)
    
    img.write_bmp("./render.bmp", image.width, image.height, 4, &image.data[0])
    
    println("Done")
}

render_tile :: proc(world: ^World, camera: Camera, image: Image, rect: Rectangle2i) {
    film_distance :f32= 1
    film_center := camera.p - film_distance * camera.z
    
    film_w :f32= 1
    film_h :f32= 1
    
    if image.width > image.height {
        film_w = film_h * cast(f32) image.width / cast(f32) image.height
    } else if image.width < image.height {
        film_h = film_w * cast(f32) image.height / cast(f32) image.width
    }
    
    half_film_w :f32= .5 * film_w
    half_film_h :f32= .5 * film_h
    
    half_pixel_size := 0.5 / vec_cast(f32, image.width, image.height)
    
    bounces_computed: u64
    
    for py in rect.min.y ..< rect.max.y {
        film_y := -1 + 2 * cast(f32) py / cast(f32) image.height
        for px in rect.min.x ..< rect.max.x {
            film_x := -1 + 2 * cast(f32) px / cast(f32) image.width
            
            final_color: v3
            
            rays_per_pixel := world.ray_per_pixel
            contribution_factor :f32= 1.0 / cast(f32) rays_per_pixel
            for _ in 0..<rays_per_pixel {
                off := v2{film_x, film_y} + random_bilateral(&world.entropy, v2) * half_pixel_size
                film_p := film_center + (off.x*camera.x*half_film_w + off.y*camera.y * half_film_h) 
                
                ray := Ray {camera.p, normalize_or_zero(film_p - camera.p)}
                
                min_t :f32= 0.0001
                attenuation :v3= 1
                sample: v3
                for _ in 0..<world.max_bounce_count {
                    closest_t := PositiveInfinity
                    hit: Material
                    did_hit: b32
                    next: Ray
                    next_normal: v3
                    
                    for plane in world.planes {
                        denom := dot(plane.n, ray.d)
                        
                        tolerance :: 0.00001
                        if abs(denom) > tolerance {
                            t := ( -plane.d - dot(plane.n, ray.o)) / denom
                            
                            if t > min_t && t < closest_t {
                                closest_t = t
                                hit = plane.m
                                did_hit = true
                                
                                next_normal = plane.n
                                next.o = ray.o + t*ray.d
                            }
                        }
                    }
                    
                    for sphere in world.spheres {
                        locale_origin := ray.o - sphere.p
                        
                        a := dot(ray.d, ray.d)
                        b := 2 * dot(locale_origin, ray.d)
                        c := dot(locale_origin, locale_origin) - square(sphere.r) 
                        
                        root := square_root(square(b) - 4*a*c)
                        tolerance :: 0.00001
                        if root >= 0 {
                            t_pos := (-b + root) / 2 * a
                            t_neg := (-b - root) / 2 * a
                            
                            t := t_pos
                            if t_neg > min_t && t_neg < t {
                                t = t_neg
                            }
                            
                            if t > min_t && t < closest_t {
                                closest_t = t
                                hit = sphere.m
                                did_hit = true
                                
                                next.o = ray.o + t*ray.d
                                next_normal = next.o - sphere.p
                            }
                        }
                    }
                    
                    bounces_computed += 1
                    
                    if did_hit {
                        sample += attenuation * hit.emit
                        angle_attenuation := dot(-ray.d, next_normal)
                        angle_attenuation = max(0, angle_attenuation)
                        attenuation *= angle_attenuation * hit.reflect
                        
                        pure_bounce := reflect(ray.d, next_normal)
                        random_bounce := normalize_or_zero(next_normal + random_bilateral(&world.entropy, v3))
                        
                        next.d = linear_blend(pure_bounce, random_bounce, hit.scatter)
                        
                        ray = next
                    } else {
                        sample += attenuation * world.no_hit.emit
                        break
                    }
                }
                
                final_color += contribution_factor * sample
            }
            
            final_color = linear_to_srgb(final_color)
            final_color *= 255
            pixel := V4(final_color, 255)
            
            p := &image.data[(image.height - 1 - py) * image.width + px]
            p ^= round(u8, pixel)
        }
    }
    
    atomic_add(&world.bounces_computed, bounces_computed)
    atomic_add(&world.tiles_retired, 1)
}

linear_to_srgb :: proc(l: v3) -> (s: v3) {
    l := l
    l = clamp_01(l)
    #unroll for i in 0..<len(l) {
        if l[i] <= 0.0031308 {
            s[i] = 12.92 * l[i]
        } else {
            s[i] = 1.055 * power(l[i], 1./2.4) - 0.055
        }
    }
    
    return s
}
