package main

import "core:fmt"
import "core:math"
import "core:math/linalg"
import "core:math/rand"
import "core:os"
import "core:thread"
import "core:time"
import rl "vendor:raylib"

Infinity :: math.INF_F32

main :: proc() {
    init_spall()
    
    gen := rand.create_u64(123)
    context.random_generator = rand.default_random_generator(&gen)
    
	rl.SetTraceLogLevel(.WARNING)
	
	thread_count := i32(os.processor_core_count())
	width: i32 = 80 * thread_count when !ODIN_DEBUG else 10 * thread_count
	height := i32(f32(width) / (16. / 9.))

	world: Hitable
	camera: Camera
	// world, camera = blur_scene()
	world, camera = random_scene(11)

	ot: HitableOctTree
	binary_tree_init(&ot, 0, 2000)
	for &h in world.(Hitables) {
		switch &v in h {
		case Sphere:
			inserted := binary_tree_append_by_aabb(&ot, &h, Aabb(3){v.center, v.radius})
			// inserted := binary_tree_append_by_position(&ot, &h, v.center)
			assert(auto_cast inserted, "couldnt insert sphere")
		case Hitables, HitableOctTree:
			assert(false, "please no nesting for now")
		}
    } 
    
    world = ot
    image := render_image(width, height, thread_count, world, camera)
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
    
    rl.SetTargetFPS(60)
    
    texture := rl.LoadTextureFromImage(rl_image)
    for !rl.WindowShouldClose() {
        if rl.IsKeyDown(.SPACE) do break
        
        rl.BeginDrawing()
        
        rl.ClearBackground({0, 0, 0, 0})
        rl.DrawTexture(texture, 0, 0, rl.WHITE)
        
        rl.EndDrawing()
    }
}

////////////////////////////////////////////////

ray_color :: proc(ray: Ray, world: Hitable, depth: i32) -> Color {
    as: [128] Color
    as_length: int
    assert(depth < len(as))
    
    ended_in_sky := true
    
    ray := ray
    depth := depth
    for depth > 0 {
        hit_record: HitRecord
        
        if hit_any(world, ray, 0.001, +Infinity, &hit_record) {
            attenuation, scattered, ok := scatter(hit_record.material, ray, hit_record)
            if ok {
                as[as_length] = attenuation
                as_length += 1
                
                ray = scattered
                depth -= 1
                
                continue
            }
            
            ended_in_sky = false
        }
        
        break
    }
    
    result: Color
    if ended_in_sky {
        direction_normal := linalg.normalize(ray.direction)
        t := .5 * (direction_normal.y + 1)
        sky :=  (1 - t) * Color{1, 1, 1} + t * Color{.5, .7, 1}
        result = sky
    }
    
    #reverse for &a, i in as[:as_length] {
        result *= a
    }
    
    return result
}

samples_per_pixel :: 6
max_depth :: 10

render_image :: proc(width, height, thread_count: i32, world: Hitable, camera: Camera) -> []rl.Color {
	image := make([]v3, height * width)
    
    args := make([]Args, thread_count)
    threads := make([]^thread.Thread, thread_count)
    fmt.println("Start render")
    start_time := time.now()
    
    length := height / thread_count
    for i in 0 ..< thread_count {
        start := i32(i) * length
        
        args[i].image = image
        args[i].total = {width, height}
        args[i].offset = start
        args[i].extent = length
        args[i].camera = camera
        args[i].world = world
        args[i].thread_index = i+1
        threads[i] = thread.create_and_start_with_poly_data(&args[i], render_into_image)
    }
    thread.join_multiple(..threads)
    
    fmt.println("Finish render:", time.since(start_time))
    
	rl_image := make([] rl.Color, height * width)
    for i in 0..<len(rl_image) {
        rl_image[i] = get_pixel_color(image[i], 1)
    }
    delete(image)
    
	return rl_image
}

Args :: struct {
    image:          [] v3,
    total:          [2] i32,
    offset, extent: i32,
    camera:         Camera,
    world:          Hitable,
    thread_index:   i32,
}

render_into_image :: proc(args: ^Args) {
    context.user_index = auto_cast args.thread_index
    init_spall_thread()
    
    for y in args.offset ..< args.offset + args.extent {
        for x in 0 ..< args.total.x {
            color: Color
            
            for s in 0 ..< samples_per_pixel {
                u := (f32(x) + random_unilateral()) / f32(args.total.x - 1)
                v := (f32(y) + random_unilateral()) / f32(args.total.y - 1)
                r := camera_get_ray(args.camera, u, v)
                color += ray_color(r, args.world, max_depth)
            }
            
            args.image[y * args.total.x + x] = (color / samples_per_pixel)
        }
    }
    fmt.println("Done", args.thread_index)
}

////////////////////////////////////////////////

get_pixel_color :: proc(pixel_color: Color, samples_per_pixel: u32) -> rl.Color {
	result := rl.Color {
        cast(u8) (math.sqrt(clamp(pixel_color.r, 0, 1)) * 255),
        cast(u8) (math.sqrt(clamp(pixel_color.g, 0, 1)) * 255),
        cast(u8) (math.sqrt(clamp(pixel_color.b, 0, 1)) * 255),
        255
    }
    
    return result
}

blur_scene :: proc() -> (world: Hitables, camera: Camera) {
	material_ground := Lambertian{Color{.0, .5, .2}}
	material_center := Lambertian{Color{.1, .2, .5}}
	material_left := Dielectric{1.5}
	material_right := Metal{Color{.8, .6, .2}, 0}

	append(&world, Sphere{{0.0, -100.5, -1.0}, 100.0, material_ground})
	append(&world, Sphere{{0.0, 0.0, -1.0}, 0.5, material_center})
	append(&world, Sphere{{-1.0, 0.0, -1.0}, 0.5, material_left})
	append(&world, Sphere{{-1.0, 0.0, -1.0}, -0.45, material_left})
	append(&world, Sphere{{1.0, 0.0, -1.0}, 0.5, material_right})

	look_from, look_at: Point : {3, 3, 2}, {0, 0, -1}
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
	return
}

random_scene :: proc(max_distance: f32) -> (world: Hitables, camera: Camera) {
	ground_material := Lambertian{.5}
	append(&world, Sphere{Point{0, -1000, 0}, 1000, ground_material})

	for a in -max_distance ..< max_distance {
		for b in -max_distance ..< max_distance {
			center := Point{f32(a) + 0.9 * random_unilateral(), 0.2, f32(b) + 0.9 * random_unilateral()}

			if linalg.length(center - Point{4, 0.2, 0}) > 0.9 {
				sphere_material: Material
				choose_mat := random_unilateral()
				switch {
				case choose_mat < .8:
					// diffuse
					albedo := random_vector() * random_vector()
					sphere_material := Lambertian{albedo}
					append(&world, Sphere{center, 0.2, sphere_material})
				case choose_mat < .95:
					// metal
					albedo := random_vector(.5, 1)
					fuzz := random_range(0, 0.5)
					sphere_material = Metal{albedo, fuzz}
					append(&world, Sphere{center, 0.2, sphere_material})
				case:
					// glass
					sphere_material := Dielectric{1.5}
					append(&world, Sphere{center, 0.2, sphere_material})
				}
			}
		}
	}

	material1 := Dielectric{1.5}
	append(&world, Sphere{Point{0, 1, 0}, 1.0, material1})

	material2 := Lambertian{{0.4, 0.2, 0.1}}
	append(&world, Sphere{Point{-4, 1, 0}, 1.0, material2})

	material3 := Metal{Color{0.7, 0.6, 0.5}, 0.0}
	append(&world, Sphere{Point{4, 1, 0}, 1.0, material3})

	look_from, look_at: Point : {13, 2, 3}, {0, 0, 0}
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
	return
}
