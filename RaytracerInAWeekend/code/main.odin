package main

import "core:fmt"
import "core:io"
import "core:math"
import "core:math/linalg"
import "core:math/rand"
import "core:os"
import "core:thread"
import "core:time"
import rl "vendor:raylib"

ray_color :: proc(r: ^Ray, world: Hitable, depth: i32) -> Color {
	rec: HitRecord
	if depth <= 0 {
		return 0
	}
	if hit_any(world, r^, 0.001, math.INF_F32, &rec) {
		scattered: Ray
		attenuation: Color
		if scatter(rec.material, r, rec, &attenuation, &scattered) {
			return attenuation * ray_color(&scattered, world, depth - 1)
		}
		return 0
	}

	unit_vector := linalg.normalize(r.direction)
	t := .5 * (unit_vector.y + 1)
	return (1 - t) * Color{1, 1, 1} + t * Color{.5, .7, 1}
}

main :: proc() {
	rl.SetTraceLogLevel(.WARNING)
	
	thread_count := i32(os.processor_core_count())
	width: i32 = 80 * thread_count
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

	rl.InitWindow(width, height, "Raytracer in a Weekend")
	for !rl.WindowShouldClose() {
		if rl.IsKeyDown(.SPACE) {
			break
		}
		rl.BeginDrawing()
		rl.ClearBackground({0, 0, 0, 0})
		for y := int(height - 1); y >= 0; y -= 1 {
			for x := 0; x < int(width); x += 1 {
				rl.DrawPixel(i32(x), height - i32(y) - 1, image[y * int(width) + x])
			}
		}
		rl.EndDrawing()

	}
	rl.CloseWindow()
}

render_image :: proc(width, height, thread_count: i32, world:Hitable, camera:Camera) -> []rl.Color{
	samples_per_pixel :: 2
	max_depth :: 10

	image := make([]rl.Color, height * width)
	when true { 	//render_image
		render_into_image :: proc(using args: ^Args) {
			for y in 0 ..< total.y {
				for x in offset ..< offset + extent {
					color: Color

					for s in 0 ..< samples_per_pixel {
						u := (f32(x) + rand.float32()) / f32(total.x - 1)
						v := (f32(y) + rand.float32()) / f32(total.y - 1)
						r := camera_get_ray(camera, u, v)
						color += ray_color(&r, world, max_depth)
					}
					pixel_color := get_pixel_color(color, samples_per_pixel)
					image[y * total.x + x] = pixel_color
				}
			}
			fmt.println(os.current_thread_id(), "Done")
		}

		length := width / thread_count
		Args :: struct {
			image:          []rl.Color,
			total:          [2]i32,
			offset, extent: i32,
			camera:         Camera,
			world:          Hitable,
		}
		args := make([]^Args, thread_count)
		threads := make([]^thread.Thread, thread_count)
		fmt.println("Start render")
		start := time.now()
		for i in 0 ..< thread_count {
			start := i32(i) * length
			args[i] = new(Args)
			args[i].image = image
			args[i].total = {width, height}
			args[i].offset = start
			args[i].extent = length
			args[i].camera = camera
			args[i].world = world
			threads[i] = thread.create_and_start_with_poly_data(args[i], render_into_image)
		}
		thread.join_multiple(..threads)

		fmt.println("Finish render:", time.diff(start, time.now()))

	}
	return image
}

get_pixel_color :: proc(pixel_color: Color, samples_per_pixel: u32) -> rl.Color {
	scale := 1 / f32(samples_per_pixel)
	color := pixel_color * scale
	color.r = clamp(math.sqrt(color.r) * 256, 0, 255.999)
	color.g = clamp(math.sqrt(color.g) * 256, 0, 255.999)
	color.b = clamp(math.sqrt(color.b) * 256, 0, 255.999)

	return {u8(color.r), u8(color.g), u8(color.b), 255}
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
			center := Point{f32(a) + 0.9 * rand.float32(), 0.2, f32(b) + 0.9 * rand.float32()}

			if linalg.length(center - Point{4, 0.2, 0}) > 0.9 {
				sphere_material: Material
				choose_mat := rand.float32()
				switch {
				case choose_mat < .8:
					// diffuse
					albedo := random_vector() * random_vector()
					sphere_material := Lambertian{albedo}
					append(&world, Sphere{center, 0.2, sphere_material})
				case choose_mat < .95:
					// metal
					albedo := random_vector(.5, 1)
					fuzz := rand.float32_range(0, 0.5)
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
