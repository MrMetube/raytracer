package main

import "core:fmt"
import "core:math"
import "core:math/linalg"
import "core:os"
import "core:thread"
import "core:time"
import rl "vendor:raylib"


////////////////////////////////////////////////
// @todo(viktor): 
// smarted threading with smaller regions and work stealing
// SIMD (again?)

samples_per_pixel :: 8
max_depth :: 20

////////////////////////////////////////////////

main :: proc() {
    init_spall()
    
    context.random_generator = seed_random_generator(123)
    
	rl.SetTraceLogLevel(.WARNING)
	
	thread_count := cast(i32) os.processor_core_count()
	width: i32 = 80 * thread_count
	height := i32(f32(width) / (16. / 9.))

	camera: Camera
    hh := make([dynamic] Hitable, 0, 4096, context.allocator)
    hh.allocator = {}
    append_nothing(&hh) // nil
    append_nothing(&hh) // world
    
    world := &hh[Root_Index]
    world.bounds = center_dimension(0, 2000)
    
	// camera = blur_scene(&hh)
	camera = random_scene(&hh, 11)
    
    stack := make([dynamic] Hitable_Index, context.temp_allocator)
    
    sphere_end := len(hh)
    // @note(viktor): reverse here, so that the value linked lists are in ascending order
	#reverse for &it, i in hh[2:sphere_end] {
        it_index := cast(Hitable_Index) i + 2
        
        if it.is_sphere {
            if !tree_append(&stack, &hh, it_index) {
                assert(false, "couldnt insert sphere")
            }
        } else {
			assert(false, "nesting not allowed")
		}
    } 
    
    image := render_image(hh[:], width, height, thread_count, camera)
    defer delete(image)
    
    for y in 0..<height/2 {
        top := y
        bot := height-1-y
        for x in 0..<width {
            swap(&image[top * width + x], &image[bot * width + x])
        }
    }
        
    rl_image := rl.Image {
        data = raw_data(image), 
        width = width,
        height = height,
        mipmaps = 1,
        format = .UNCOMPRESSED_R8G8B8A8,
    }
    
    rl.InitWindow(width, height, "Raytracer in a Weekend")
    defer rl.CloseWindow()
    
    rl.SetTargetFPS(15)
    
    texture := rl.LoadTextureFromImage(rl_image)
    for !rl.WindowShouldClose() {
        rl.BeginDrawing()
        
        rl.ClearBackground({0, 0, 0, 0})
        rl.DrawTexture(texture, 0, 0, rl.WHITE)
        
        rl.EndDrawing()
    }
}

////////////////////////////////////////////////

render_image :: proc(hh: [] Hitable, width, height, thread_count: i32, camera: Camera) -> []rl.Color {
    spall_proc()
	image := make([]v3, height * width)
    
    args := make([]Args, thread_count)
    threads := make([]^thread.Thread, thread_count)
    fmt.println("Start render")
    spall_begin("render")
    start_time := time.now()
    
    length := height / thread_count
    for i in 0 ..< thread_count {
        start := i32(i) * length
        
        args[i].hh    = hh[:]
        args[i].image = image
        args[i].total = {width, height}
        args[i].offset = start
        args[i].extent = length
        args[i].camera = camera
        args[i].thread_index = i+1
        threads[i] = thread.create_and_start_with_poly_data(&args[i], render_into_image)
    }
    thread.join_multiple(..threads)
    
    spall_end()
    fmt.println("Finish render:", time.since(start_time))
    
    spall_scope("copy image")
	rl_image := make([] rl.Color, height * width)
    for i in 0..<len(rl_image) {
        rl_image[i] = to_rl_color(image[i], 1)
    }
    delete(image)
    
	return rl_image
}

Args :: struct {
    hh:             [] Hitable,
    image:          [] v3,
    total:          [2] i32,
    offset, extent: i32,
    camera:         Camera,
    thread_index:   i32,
}

render_into_image :: proc(args: ^Args) {
    context.user_index = auto_cast args.thread_index
    init_spall_thread()
    
    hitable_stack_1 := make([dynamic] Hitable_Index, 0, 100, context.temp_allocator)
    hitable_stack_2 := make([dynamic] Hitable_Index, 0, 100, context.temp_allocator)
    color_stack     := make([dynamic] v3, 0, max_depth, context.temp_allocator)
    
    dx := 1.0 / (cast(f32) args.total.x - 1)
    dy := 1.0 / (cast(f32) args.total.y - 1)
    
    
    for y in args.offset ..< args.offset + args.extent {
        for x in 0 ..< args.total.x {
            color: v3
            
            rays: [samples_per_pixel] Ray
            for &ray in rays {
                u := (cast(f32) x + random_unilateral()) * dx
                v := (cast(f32) y + random_unilateral()) * dy
                
                ray = camera_get_ray(args.camera, u, v)
            }
            
            for ray in rays {
                ray_color := trace_ray(&hitable_stack_1, &hitable_stack_2, &color_stack, args.hh, ray, max_depth)
                color += ray_color
            }
            
            args.image[y * args.total.x + x] = (color / samples_per_pixel)
        }
    }
    fmt.println("Done", args.thread_index)
}

trace_ray :: proc(stack1, stack2: ^[dynamic] Hitable_Index, color_stack: ^[dynamic] v3, hh: [] Hitable, ray: Ray, depth: i32) -> v3 {
    spall_proc()
    
    ended_in_sky := true
    clear(color_stack)
    
    ray := ray
    depth := depth
    for depth > 0 {
        record, did_hit := hit_any(stack1, stack2, hh, Root_Index, ray, 0.001, +Infinity)
        if did_hit {
            attenuation, scattered, ok := scatter(record.material, ray, record)
            if ok {
                append(color_stack, attenuation)
                
                ray = scattered
                depth -= 1
                
                continue
            }
            
            ended_in_sky = false
        }
        
        break
    }
    
    result: v3
    if ended_in_sky {
        spall_scope("hit_sky")
        direction_normal := linalg.normalize(ray.direction)
        t := .5 * (direction_normal.y + 1)
        sky :=  (1 - t) * v3{1, 1, 1} + t * v3{.5, .7, 1}
        result = sky
    }
    
    #reverse for &a in color_stack {
        result *= a
    }
    
    return result
}

////////////////////////////////////////////////

to_rl_color :: proc(pixel_color: v3, samples_per_pixel: u32) -> rl.Color {
	result := rl.Color {
        cast(u8) (math.sqrt(clamp(pixel_color.r, 0, 1)) * 255),
        cast(u8) (math.sqrt(clamp(pixel_color.g, 0, 1)) * 255),
        cast(u8) (math.sqrt(clamp(pixel_color.b, 0, 1)) * 255),
        255
    }
    
    return result
}

////////////////////////////////////////////////

blur_scene :: proc(hh: ^[dynamic] Hitable) -> (camera: Camera) {
    material_ground := Lambertian{v3{.0, .5, .2}}
    material_center := Lambertian{v3{.1, .2, .5}}
    material_left   := Dielectric{1.5}
    material_right  := Metal{v3{.8, .6, .2}, 0}
    
    append_sphere(hh, Sphere{{0.0, -100.5, -1.0}, 100.0, material_ground})
    append_sphere(hh, Sphere{{0.0, 0.0, -1.0}, 0.5, material_center})
    append_sphere(hh, Sphere{{-1.0, 0.0, -1.0}, 0.5, material_left})
    append_sphere(hh, Sphere{{-1.0, 0.0, -1.0}, -0.45, material_left})
    append_sphere(hh, Sphere{{1.0, 0.0, -1.0}, 0.5, material_right})
    
    look_from, look_at: v3 : {3, 3, 2}, {0, 0, -1}
    focus_distance := linalg.length(look_from - look_at)
    
    aspect_ratio: f32 : 16.0 / 9.0
    vertical_fov: f32 : 20
    aperture :: 2
    
    camera_init(
        &camera,
        look_from,
        look_at,
        {0, 1, 0},
        vertical_fov,
        aspect_ratio,
        aperture,
        focus_distance,
    )
    
    return camera
}

random_scene :: proc(hh: ^[dynamic] Hitable, max_distance: f32) -> (camera: Camera) {
	ground_material := Lambertian{.5}
	append_sphere(hh, Sphere{v3{0, -1000, 0}, 1000, ground_material})

	for a in -max_distance ..< max_distance {
		for b in -max_distance ..< max_distance {
			center := v3{f32(a) + 0.9 * random_unilateral(), 0.2, f32(b) + 0.9 * random_unilateral()}

			if linalg.length(center - v3{4, 0.2, 0}) > 0.9 {
				sphere_material: Material
				choose_mat := random_unilateral()
				switch {
				case choose_mat < .8: // diffuse
					albedo := random_vector() * random_vector()
					sphere_material := Lambertian{albedo}
					append_sphere(hh, Sphere{center, 0.2, sphere_material})
                    
				case choose_mat < .95: // metal
					albedo := random_vector(.5, 1)
					fuzz := random_range(0, 0.5)
					sphere_material = Metal{albedo, fuzz}
					append_sphere(hh, Sphere{center, 0.2, sphere_material})
                    
				case: // glass
					sphere_material := Dielectric{1.5}
					append_sphere(hh, Sphere{center, 0.2, sphere_material})
				}
			}
		}
	}

	material1 := Dielectric{1.5}
	append_sphere(hh, Sphere{v3{0, 1, 0}, 1.0, material1})

	material2 := Lambertian{{0.4, 0.2, 0.1}}
	append_sphere(hh, Sphere{v3{-4, 1, 0}, 1.0, material2})

	material3 := Metal{v3{0.7, 0.6, 0.5}, 0.0}
	append_sphere(hh, Sphere{v3{4, 1, 0}, 1.0, material3})

	look_from, look_at: v3 : {13, 2, 3}, {0, 0, 0}
	focus_distance :: 10

	aspect_ratio: f32 : 3.0 / 2.0
	vertical_fov: f32 : 20
	aperture :: .1

	camera_init(
		&camera,
		look_from,
		look_at,
		{0, 1, 0},
		vertical_fov,
		aspect_ratio,
		aperture,
		focus_distance,
	)
    
	return camera
}
