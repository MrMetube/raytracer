#+feature dynamic-literals
package main

import "base:intrinsics"
import os "core:os/os2"
import "core:simd"
import "core:time"

import img "vendor:stb/image"

Color :: [4]u8

Image:: struct {
    data:          []Color,
    width, height: i32,
}

BrdfTable :: struct {
    count:  [3]u32,
    values: []v3,
}

Material :: struct {
    emit:    lane_v3,
    reflect: lane_v3,
    scatter: f32, // 0 = mirror like, 1 = chalk like
    
    brdf:    BrdfTable,
}

Plane :: struct {
    normal, tangent, binormal: lane_v3,
    d: f32,    
    material: u32,
}

Sphere :: struct {
    center:   lane_v3,
    radius:   f32,
    material: u32,
}

World :: struct {
    spheres:   [dynamic]Sphere,
    planes:    [dynamic]Plane,
    materials: [dynamic]Material,
    
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
    world.ray_per_pixel = 1024
    world.max_bounce_count = 8

    world.materials = {
        { emit    = { .3 , .4 , .5 },               },
        { reflect = { .5 , .5 , .5 }, scatter = 1.  },
        { reflect = { .7 , .5 , .3 }, scatter = 1.  },
        { emit    = {50. , 10 ,  5 }, scatter = 1.  },
        { reflect = { .2 , .8 , .2 }, scatter = .3  },
        { reflect = { .4 , .8 , .9 }, scatter = .15 },
        { reflect = { .95, .95, .95}, scatter = .1  },
    }
    
    load_brdf_merl("", &world.materials[0].brdf)
    load_brdf_merl(`.\BRDFDatabase\brdfs\gray-plastic.binary`, &world.materials[1].brdf)
    load_brdf_merl(`.\BRDFDatabase\brdfs\chrome.binary`,       &world.materials[2].brdf)
    // load_brdf_merl(`.\BRDFDatabase\brdfs\`, &m[3].brdf)
    // load_brdf_merl(`.\BRDFDatabase\brdfs\`, &m[4].brdf)
    // load_brdf_merl(`.\BRDFDatabase\brdfs\`, &m[5].brdf)
    // load_brdf_merl(`.\BRDFDatabase\brdfs\`, &m[6].brdf)
    
    core_count :: 12 // os.core_count or something
    append(&world.planes,  Plane  { normal = {0,0,1},  d = 0, material = 1 })
    // append(&world.planes,  Plane  { normal = {1,0,0},  d = 2, material = 1 })
    
    append(&world.spheres, Sphere { center = {0,0,0},   radius = 1, material = 2 })
    // append(&world.spheres, Sphere { center = {3,-2,0},  radius = 1, material = 3 })
    // append(&world.spheres, Sphere { center = {-2,-1,2}, radius = 1, material = 4 })
    // append(&world.spheres, Sphere { center = {1,-1,3},  radius = 1, material = 5 })
    // append(&world.spheres, Sphere { center = {-2,3,0},  radius = 2, material = 6 })
    
    
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

load_brdf_merl :: proc (filename: string, dest: ^BrdfTable) {
    if filename == "" {
        dest.count = 1
        dest.values = make([]v3, 1)
    } else {
        data, err := os.read_entire_file(filename, context.temp_allocator)
        all_data := data
        defer delete(all_data, context.temp_allocator)
        
        if err != nil {
            println("Unable to open MERL binary %", filename)
            return
        }
        
        dest.count = (cast(^[3]u32) &data[0])^
        cursor := size_of(dest.count)
        data = data[cursor:]
        
        total_count := dest.count[0] * dest.count[1] * dest.count[2]
        temp_values := (cast([^]f64) &data[0])[:total_count*3]
        
        foo := len(data) * size_of(u8) / (size_of(f64) * 3)
        file_size := cast(umm) &data[0] + auto_cast len(data)
        read_size := cast(umm) &temp_values[0] + auto_cast len(temp_values) * size_of(f64)
        assert(file_size == read_size)
        
        dest.values = make([]v3, total_count)
        for i in 0..<total_count {
            dest.values[i].x = cast(f32) temp_values[i + total_count * 0]
            dest.values[i].y = cast(f32) temp_values[i + total_count * 1]
            dest.values[i].z = cast(f32) temp_values[i + total_count * 2]
        }
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
                
                t := ( -plane.d - dot(plane.normal, ray_o)) / denom
                t_mask     := greater_than(t, min_t) & less_than(t, closest_t)
                
                if t_mask == 0 do continue
                
                hit_mask   := denom_mask & t_mask
                
                conditional_assign(hit_mask, &closest_t, t)
                conditional_assign(hit_mask, &did_hit, 0xffffffff)
                
                conditional_assign(hit_mask, &hit_mat_index, plane.material)
                
                conditional_assign(hit_mask, &next_o, ray_o + t*ray_d)
                
                conditional_assign(hit_mask, &normal,    plane.normal)
                conditional_assign(hit_mask, &tangent,   plane.tangent)
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
                
                t_pos := (-b + root) / 2 * a
                t_neg := (-b - root) / 2 * a
                
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
                
                s_tangent   := cross(lane_v3{0,0,1}, normal)
                s_binormal := cross(normal, tangent)
                
                s_tangent   = normalize_or_zero(s_tangent)
                s_binormal = normalize_or_zero(s_binormal)
                
                conditional_assign(hit_mask, &tangent,   s_tangent)
                conditional_assign(hit_mask, &binormal, s_binormal)
            }
            
            
            gather :: proc (materials: []Material, index: lane_u32, $member: string, $T: typeid) -> (result: T) {
                mask: lane_u32 = 0xffffffff
                
                array  := cast(lane_umm) &materials[0]
                member := offset_of_by_string(Material, member)
                index  := cast(lane_umm) index * size_of(Material)
                when T == lane_v3 {
                    channel :umm= size_of(lane_f32)
                    result.r = simd.gather(cast(lane_pmm) (array + index + member + channel * 0), lane_f32(0), mask)
                    result.g = simd.gather(cast(lane_pmm) (array + index + member + channel * 1), lane_f32(0), mask)
                    result.b = simd.gather(cast(lane_pmm) (array + index + member + channel * 2), lane_f32(0), mask)
                } else when T == lane_f32 {
                    result   = simd.gather(cast(lane_pmm) (array + index + member), lane_f32(0), mask)
                } else do #panic("unhandled")
                
                return result
            }
            
            hit_emit    := gather(world.materials[:], hit_mat_index, "emit",    lane_v3)
            hit_reflect := gather(world.materials[:], hit_mat_index, "reflect", lane_v3)
            hit_scatter := gather(world.materials[:], hit_mat_index, "scatter", lane_f32)
            // only allow world.no_hit on the first time we didnt hit anything
            (cast(^lane_u32) &hit_emit.r)^ &= lane_mask
            (cast(^lane_u32) &hit_emit.g)^ &= lane_mask
            (cast(^lane_u32) &hit_emit.b)^ &= lane_mask
            
            // Color Accumulation
            sample += attenuation * hit_emit
            
            lane_mask &= did_hit
            if lane_mask == 0 {
                break
            } else {
                // Bounce
                pure_bounce   := reflect(ray_d, normal)
                random_bounce := normalize_or_zero(normal + random_bilateral(entropy, lane_v3))
                
                next_d := linear_blend(pure_bounce, random_bounce, hit_scatter)
                
                reflectance := brdf_lookup(world.materials[:], hit_mat_index, -ray_d, normal, tangent, binormal, next_d)
                conditional_assign(did_hit, &attenuation, attenuation * reflectance)
                
                ray_o = next_o
                
                ray_d = next_d
            }
        }
        
        final_color_lanes += contribution_factor * sample
    }
    
    final_color.r = horizontal_add(final_color_lanes.r)
    final_color.g = horizontal_add(final_color_lanes.g)
    final_color.b = horizontal_add(final_color_lanes.b)
    
    return final_color, cast(u64) horizontal_add(bounces_computed_lanes), cast(u64) horizontal_add(loops_computed_lanes)
}

brdf_lookup :: proc (materials: []Material, index: lane_u32, view_direction, normal, tangent, binormal, light_direction: lane_v3) -> (result: lane_v3) {
    index := index

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
    diff_x := normalize_or_zero(cross(diff_y, hw))
    
    diff_x_inner := dot(diff_x, lw)
    diff_y_inner := dot(diff_y, lw)
    diff_z_inner := dot(hw, lw)
    
    for lane in 0..<LaneWidth {
        theta_half := acos(extract(hw.z, lane))
        
        theta_diff := acos(extract(diff_z_inner, lane))
        phi_diff   := atan2(extract(diff_y_inner, lane), extract(diff_x_inner, lane))

        if phi_diff < 0 do phi_diff += Pi
        
        table := materials[(cast(^[LaneWidth]u32) &index)[lane]].brdf
        
        f0 := square_root(clamp_01(theta_half / (.5 * Pi)))
        i0 := round(u32, cast(f32) (table.count[0]-1) * f0)
        
        f1 := clamp_01(theta_diff / (.5 * Pi))
        i1 := round(u32, cast(f32) (table.count[1]-1) * f1)
        
        f2 := clamp_01(phi_diff / Pi)
        i2 := round(u32, cast(f32) (table.count[2]-1) * f2)
        
        brdf_index := i2 + i1 * table.count[2] + i0 * table.count[2] * table.count[1]
        
        color := table.values[brdf_index]
        
        (cast(^[LaneWidth]f32) &result.r)[lane] = color.r
        (cast(^[LaneWidth]f32) &result.g)[lane] = color.g
        (cast(^[LaneWidth]f32) &result.b)[lane] = color.b
    }
    
    return result
}