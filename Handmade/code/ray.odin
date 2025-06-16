package main

import "core:fmt"
import img "vendor:stb/image"

Color :: [4]u8

Image:: struct {
    data: []Color,
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
    no_hit: Material,
    spheres: [dynamic]Sphere,
    planes:  [dynamic]Plane,
    
    entropy: RandomSeries,
}

Ray :: struct {
    o, d: v3,
}

main :: proc() {
    println("Hello Handmade Ray")
    
    image: Image
    image.width  = 1920
    image.height = 1080
    image.data = make([]Color, image.width * image.height)
    
    world: World
    world.no_hit = { emit = {.3, .4, .8} }
    
    world.entropy = seed_random_series(123)
    
    append(&world.planes,  Plane  { n = {0,0,1},  d = 0, m = { reflect = {.2, .2, .2}, scatter = 1. } })
    append(&world.planes,  Plane  { n = {1,0,0},  d = 3, m = { reflect = {1., 1., 1.}, scatter = 1. } })
    
    append(&world.spheres, Sphere { p = {0,0,1},   r = 0.4, m = { emit    = {5., 5., .0}, scatter = 1. } })
    append(&world.spheres, Sphere { p = {3,-2,0},  r = 1,   m = { reflect = {.9, .1, .4}, scatter = 1. } })
    append(&world.spheres, Sphere { p = {-2,-3,1}, r = 1.3, m = { reflect = {.3, .7, .4}, scatter = .7 } })
    append(&world.spheres, Sphere { p = {0,1,3},   r = 2,   m = { reflect = {.4, .7, .7}, scatter = .3 } })
    
    camera_p := v3{0, -10, 1}
    camera_z := normalize_or_zero(camera_p)
    camera_x := normalize_or_zero(cross(v3{0, 0, 1}, camera_z))
    camera_y := normalize_or_zero(cross(camera_z, camera_x))
    
    film_distance :f32= 1
    film_center := camera_p - film_distance * camera_z
    
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
    
    rays_per_pixel :: 16
    
    for py in 0 ..< image.height {
        film_y := -1 + 2 * cast(f32) py / cast(f32) image.height
        
        for px in 0 ..< image.width {
            film_x := -1 + 2 * cast(f32) px / cast(f32) image.width
            p := &image.data[(image.height - 1 - py) * image.width + px]
            
            color: v3
            factor :f32= 1.0 / rays_per_pixel
            for _ in 0..<rays_per_pixel {
                off := v2{film_x, film_y} + random_bilateral(&world.entropy, v2) * half_pixel_size
                film_p := film_center + (off.x*camera_x*half_film_w + off.y*camera_y * half_film_h) 
                ray := Ray {camera_p, normalize_or_zero(film_p - camera_p)}
                
                color += factor * cast_ray(&world, ray)
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
            
            color = linear_to_srgb(color)
            color *= 255
            pixel := V4(color, 255)
            
            p ^= round(u8, pixel)
        }
        
        if py % 64 == 0 do print("\rRaycasting: % %% ...", format_percentage(cast(f32) py / cast(f32) image.height))
    }
    
    println("\nDone")
    
    img.write_bmp("./render.bmp", image.width, image.height, 4, &image.data[0])
}


cast_ray :: proc(world: ^World, ray: Ray) -> (result: v3) {
    attenuation :v3= 1
    ray := ray
    
    min_t :f32= 0.0001
    for _ in 0..<8 {
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
        
        if did_hit {
            result += attenuation * hit.emit
            angle_attenuation := dot(-ray.d, next_normal)
            angle_attenuation = max(0, angle_attenuation)
            attenuation *= angle_attenuation * hit.reflect
            
            pure_bounce := reflect(ray.d, next_normal)
            random_bounce := normalize_or_zero(next_normal + random_bilateral(&world.entropy, v3))
            
            next.d = linear_blend(pure_bounce, random_bounce, hit.scatter)
            
            ray = next
        } else {
            result += attenuation * world.no_hit.emit
            break
        }
    }
    
    return result
}