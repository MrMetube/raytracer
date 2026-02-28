package main

import os "core:os/os2"
import os_old "core:os"
import "core:time"
import "core:fmt"
import "core:math"

import img "vendor:stb/image"
import rl "vendor:raylib"

Todo :: true

FontSize :: 20

Render :: struct {
    requested: bool,
    active:    bool,
    
    start, end: time.Time,
    
    world: World,
    
    image:   Image,
    texture: rl.Texture,
    queue:   WorkQueue,
    
    arena:     Arena,
    allocator: Allocator,
}

////////////////////////////////////////////////

fast_factor :: 6 when SpallDisabled else 60

main :: proc() {
    rl.SetTraceLogLevel(.WARNING)
    
    init_spall()
    
    core_count := cast(i32) os_old.processor_core_count() - 1
    
    world: World
    world.rays_per_pixel   = 8
    world.max_bounce_count = 8
    
    // nil sphere, triangle, and plane
    append(&world.spheres,   Sphere{})
    append(&world.triangles, Triangle{})
    append(&world.planes,    Plane{})
    
    append(&world.materials, Material{ emit    = { .3  , .4  , .5 },              })
    append(&world.materials, Material{ reflect = { .5  , .5  , .5 }, scatter = 1  })
    append(&world.materials, Material{ reflect = { .7  , .5  , .3 }, scatter = .8 })
    append(&world.materials, Material{ emit    = {  35 ,  20 , .5 }, scatter = 1. })
    append(&world.materials, Material{ reflect = { .2  , .8  , .2 }, scatter = .3 })
    append(&world.materials, Material{ reflect = { .65 , .1  , .7 }, scatter = .9 })
    append(&world.materials, Material{ reflect = { .9  , .9  , .8 }, scatter = .6 })
    
    material_names := make_slice(context.allocator, [] string, len(world.materials))
    
    load_brdf_merl("",                                         &world.materials[0].brdf, &world.all_brdf_values); material_names[0] = ""
    load_brdf_merl("./BRDFDatabase/brdfs/gray-plastic.binary", &world.materials[1].brdf, &world.all_brdf_values); material_names[1] = "gray-plastic"
    load_brdf_merl("./BRDFDatabase/brdfs/brass.binary",        &world.materials[2].brdf, &world.all_brdf_values); material_names[2] = "brass"
    load_brdf_merl("./BRDFDatabase/brdfs/gold-paint.binary",   &world.materials[3].brdf, &world.all_brdf_values); material_names[3] = "gold-paint"
    load_brdf_merl("./BRDFDatabase/brdfs/green-latex.binary",  &world.materials[4].brdf, &world.all_brdf_values); material_names[4] = "green-latex"
    load_brdf_merl("./BRDFDatabase/brdfs/purple-paint.binary", &world.materials[5].brdf, &world.all_brdf_values); material_names[5] = "purple-paint"
    load_brdf_merl("./BRDFDatabase/brdfs/white-marble.binary", &world.materials[6].brdf, &world.all_brdf_values); material_names[6] = "white-marble"
    
    // append(&world.spheres, Sphere { center = { 0, 0, 0},   radius = 1,  material = 2 })
    // append(&world.spheres, Sphere { center = { 3,-2, 0.4}, radius = .1, material = 3 })
    // append(&world.spheres, Sphere { center = {-2,-1, 2},   radius = 1,  material = 1 })
    // append(&world.spheres, Sphere { center = { 1,-1, 3},   radius = 1,  material = 5 })
    // append(&world.spheres, Sphere { center = {-2, 3, 0},   radius = 2,  material = 6 })
    
    area_size := cast(f32) 20
    if false {
        gen_entropy := seed_random_series(565)
        for _ in 0..< square(area_size) * 1.2 {
            radius := random_between_f32(&gen_entropy, 0.1, 0.4)
            
            bounds := radius + 0.05
            
            center: v3
            center.z = bounds
            
            attemps: for _ in 0..< 10 {
                center.xy = random_bilateral(&gen_entropy, v2) * (area_size - bounds)
                for other in world.spheres {
                    if length_squared(other.center - center) > square(other.radius + bounds) {
                        break attemps
                    }
                }
            }
            
            material := random_between_u32(&gen_entropy, 1, auto_cast len(world.materials) - 1)
            append(&world.spheres, Sphere { center, radius, material })
        }
    }
    
    append(&world.planes, Plane { normal = { 0, 0, 1}, tangent = {}, binormal = {}, center = { 0, 0, 0},             radius = +Infinity,   material = 6 })
    // append(&world.planes, Plane { normal = { 0, 0,-1}, tangent = {}, binormal = {}, center = { 0, 0, area_size},     radius = area_size,   material = 6 })
    append(&world.planes, Plane { normal = { 0, 0,-1}, tangent = {}, binormal = {}, center = { 0, 0, area_size-0.1}, radius = area_size/5, material = 3 })
    // append(&world.planes, Plane { normal = { 1, 0, 0}, tangent = {}, binormal = {}, center = {-area_size, 0, 0},     radius = area_size,   material = 2 })
    // append(&world.planes, Plane { normal = {-1, 0, 0}, tangent = {}, binormal = {}, center = {+area_size, 0, 0},     radius = area_size,   material = 2 })
    // append(&world.planes, Plane { normal = { 0,-1, 0}, tangent = {}, binormal = {}, center = {0, +area_size, 0},     radius = area_size,   material = 4 })
    
    ////////////////////////////////////////////////
    
    teapot := load_teapot(0, 2)
    append(&world.triangles, ..teapot)
    
    ////////////////////////////////////////////////
    values_per_node :: 1
    
    stack := make_dynamic_array(context.temp_allocator, [dynamic] Node_Index, 0, 0)
    reserve(&world.sphere_nodes, len(world.spheres))
    tree_init(&world.sphere_nodes, rectangle_center_dimension(v3{0, 0, 0}, 128))
    
    // Currently the octtree is a ~30% gain compared to the straight array
    for sphere, index in world.spheres {
        value: Sphere_Node
        value.value = sphere
        value.bounds = rectangle_center_dimension(sphere.center, sphere.radius)
        
        ok := octtree_append(&stack, &world.sphere_nodes, value, values_per_node)
        assert(ok)
    }
    
    clear(&stack)
    reserve(&world.triangle_nodes, len(world.triangles))
    tree_init(&world.triangle_nodes, rectangle_center_dimension(v3{}, 128))
    
    for triangle in world.triangles {
        value: Triangle_Node
        value.value = triangle
        
        // @note(viktor): These bounds are currently only used in construction and not in the octtree traversal. if hit_rectangle + maybe hit_value is generally faster than just hit_value, it may be worth also testing the value bounds.
        value.bounds = rectangle_inverted_infinity(Rectangle3)
        value.bounds = get_union_point(value.bounds, triangle.a)
        value.bounds = get_union_point(value.bounds, triangle.b)
        value.bounds = get_union_point(value.bounds, triangle.c)
        append(&world.triangle_nodes, value)
        
        ok := octtree_append(&stack, &world.triangle_nodes, value, values_per_node = values_per_node)
        assert(ok)
    }
    
    info := inspect(world.triangle_nodes, Root_Index, values_per_node)
    print("triangle tree info = %\n", info)
    print("  values per node = %\n", values_per_node)
    print("  density         = % %%\n", 100 * cast(f64) info.value_count / cast(f64) (info.node_count + info.value_count))
    print("  overfullness    = % %%\n", 100 * cast(f64) info.overfull_nodes / cast(f64) (info.node_count))
    print("\n")
    
    ////////////////////////////////////////////////
    
    camera: Camera
    if false {
        camera.p = {2.33, -4.22, 3.8}
        camera.z = normalize_or_zero(camera.p - {0.3, 0.8, 0.5})
    } else {
        camera.p = {0, -7, 1}
        camera.z = normalize_or_zero(camera.p)
    }
    camera.x = normalize_or_zero(cross(v3{0, 0, 1}, camera.z))
    camera.y = normalize_or_zero(cross(camera.z, camera.x))
    
    ////////////////////////////////////////////////
        
    window_size := v2i { 1920, 1080 }
    
    rl.InitWindow(window_size.x, window_size.y, "Handmade Ray")
    rl.SetTargetFPS(144)
    
    font := rl.LoadFontEx("./fonts/VictorMono-Bold.otf", FontSize, nil, 0)
    
    rl.GuiEnable()
    rl.GuiSetFont(font)
    rl.GuiSetStyle(.DEFAULT, auto_cast rl.GuiDefaultProperty.TEXT_SIZE, FontSize)
    rl.GuiSetStyle(.DEFAULT, auto_cast rl.GuiControlProperty.TEXT_COLOR_NORMAL, auto_cast rl.ColorToInt(rl.WHITE))
    
    ui_rect := rectangle_min_dimension(v2{}, vec_cast(f32, window_size))
    ui_rect = add_radius(ui_rect, -10)
    
    show_materials: bool
    show_planes: bool
    show_spheres: bool
    
    
    quality_render: Render
    fast_render:    Render
    init_render(&quality_render, 64, 8, window_size.x, window_size.y, core_count)
    init_render(&fast_render,    8,  4, window_size.x / fast_factor, window_size.y / fast_factor, core_count)
    defer close_work_queue_and_wait_for_threads(&quality_render.queue)
    defer close_work_queue_and_wait_for_threads(&fast_render.queue)
    
    renders := make_dynamic_array(context.allocator, [dynamic] ^Render, 0, 2)
    append(&renders, &quality_render)
    append(&renders, &fast_render)
    
    ////////////////////////////////////////////////
    
    fast_render.requested = true
    fast_image_is_focussed: bool = true
    
    mouse_is_look: bool
    ddp: v3
    dp: v3
    for !rl.WindowShouldClose() {
        free_all(context.temp_allocator)
        
        rl.BeginDrawing()
        rl.ClearBackground({0x18, 0x18, 0x18, 0xff})
        
        delta_time := rl.GetFrameTime()
        
        speed: f32 = 60
        if !rl.IsKeyDown(.LEFT_SHIFT) {
            ddp *= 0.1
        }
        
        dddp: v3
        if rl.IsKeyDown(.A) do dddp += {-1, 0,  0}
        if rl.IsKeyDown(.D) do dddp += { 1, 0,  0}
        if rl.IsKeyDown(.W) do dddp += { 0, 0, -1}
        if rl.IsKeyDown(.S) do dddp += { 0, 0,  1}
        
        if rl.IsKeyDown(.SPACE)        do dddp += {0, 1,  0}
        if rl.IsKeyDown(.LEFT_CONTROL) do dddp += {0,-1,  0}
        
        if rl.IsMouseButtonPressed(.MIDDLE) {
            mouse_is_look = !mouse_is_look
        }
        
        dlook: v2
        if mouse_is_look {
            dlook = -rl.GetMouseDelta()
        }
        
        if !rl.IsWindowFocused() {
            mouse_is_look = false
            rl.ShowCursor()
        } else {
            if mouse_is_look {
                rl.HideCursor()
                rl.SetMousePosition(window_size.x / 2, window_size.y / 2)
            } else do rl.ShowCursor()   
            
        }
        
        if dlook != 0 {
            dlook *= 100/vec_cast(f32, window_size) * delta_time
            up :: v3{0,0,1}
            
            yaw   := axis_angle_rotation(camera.y,                            dlook.x)
            pitch := axis_angle_rotation(normalize(multiply3(yaw, camera.x)), dlook.y)
            
            new_z := multiply3(pitch * yaw, camera.z)
            
            if abs(dot(new_z, up)) < 0.9999 {
                camera.z = new_z
            } else {
                camera.z = multiply3(yaw, camera.z)
            }
            
            camera.x = normalize_or_zero(cross(up, camera.z))
            camera.y = normalize_or_zero(cross(camera.z, camera.x))
            
            fast_render.requested = true
        }
        
        
        dddp = normalize_or_zero(dddp)
        dddp *= speed
        ddp += dddp
        ddp *= 0.9
        dp += ddp * delta_time
        dp *= 0.9
        if length_squared(dp) < square(cast(f32) 0.01) do dp = 0
        
        if dp != 0 {
            camera.p += dp.x * camera.x    * delta_time
            camera.p += dp.y * v3{0, 0, 1} * delta_time
            camera.p += dp.z * camera.z    * delta_time
            
            fast_render.requested = true
        }
        
        // @todo(viktor): set in render and only copy on render start, check that noone is using render.world.raysperpixel
        if !quality_render.active {
            if rl.IsKeyPressed(.J) {
                quality_render.world.rays_per_pixel /= 2
            }
            if rl.IsKeyPressed(.K) {
                quality_render.world.rays_per_pixel *= 2
            }
            quality_render.world.rays_per_pixel = clamp(quality_render.world.rays_per_pixel, LaneWidth, 2048)
        }
        
        if !fast_render.active {
            if rl.IsKeyPressed(.N) {
                fast_render.world.rays_per_pixel /= 2
            }
            if rl.IsKeyPressed(.M) {
                fast_render.world.rays_per_pixel *= 2
            }
            fast_render.world.rays_per_pixel = clamp(fast_render.world.rays_per_pixel, LaneWidth, 128)
        }
        
        if rl.IsKeyPressed(.X) {
            quality_render.requested = true
        }
        if rl.IsKeyPressed(.C) {
            fast_render.requested = true
        }
        
        for &render in renders {
            if !render.active {
                if render.requested {
                    render.requested = false
                    render.active = true
                    
                    render.world.bounces_computed = 0
                    render.world.loops_computed   = 0
                    render.world.tiles_retired    = 0
                    render.world.pixels_done      = 0
                    render.world.nil_value_lanes_tested = 0
                    
                    render.world.all_brdf_values = world.all_brdf_values
                    
                    // @volatile
                    make_by_pointer(&render.world.spheres,        len(world.spheres),        render.allocator)
                    make_by_pointer(&render.world.planes,         len(world.planes),         render.allocator)
                    make_by_pointer(&render.world.sphere_nodes,   len(world.sphere_nodes),   render.allocator)
                    make_by_pointer(&render.world.triangle_nodes, len(world.triangle_nodes), render.allocator)
                    make_by_pointer(&render.world.triangles,      len(world.triangles),      render.allocator)
                    make_by_pointer(&render.world.materials,      len(world.materials),      render.allocator)
                    
                    copy(render.world.spheres[:],        world.spheres[:])
                    copy(render.world.sphere_nodes[:],   world.sphere_nodes[:])
                    copy(render.world.triangle_nodes[:], world.triangle_nodes[:])
                    copy(render.world.planes[:],         world.planes[:])
                    copy(render.world.materials[:],      world.materials[:])
                    copy(render.world.triangles[:],      world.triangles[:])
                    
                    begin_render(render, core_count, camera)
                }
            } else {
                if work_is_completed(&render.queue) {
                    complete_all_work(&render.queue)
                    
                    print_render_results(&render.world, render.start, render.end)
                    
                    render.active = false
                    render.end = time.now()
                    free_all(render.allocator)
                    load_image_into_texture(&render.texture, render.image)
                }
            }
        }
        
        if rl.IsKeyPressed(.R) {
            fast_image_is_focussed = !fast_image_is_focussed
        }
        
        if rl.IsKeyPressed(.F5) && !quality_render.active {
            output_path := "./render.bmp"
            img.write_bmp(ctprint("%", output_path), quality_render.image.width, quality_render.image.height, 4, &quality_render.image.data[0])
            cwd, _ := os.get_working_directory(context.temp_allocator)
            print("Wrote ouput to %/%\n", cwd, output_path)
        }
        
        ////////////////////////////////////////////////
        
        layout: Layout
        layout.font = font
        layout.at = ui_rect.min
        
        if fast_image_is_focussed {
            rl.DrawTextureEx(fast_render.texture, 0, 0, fast_factor, rl.WHITE)
            rl.DrawTextureEx(quality_render.texture, vec_cast(f32, window_size.x - quality_render.texture.width / fast_factor, 0), 0, 1.0 / fast_factor, rl.WHITE)
        } else {
            rl.DrawTextureEx(quality_render.texture, 0, 0, 1, rl.WHITE)
            rl.DrawTextureEx(fast_render.texture, vec_cast(f32, window_size.x - fast_render.texture.width, 0), 0, 1, rl.WHITE)
        }
        
        display_line(&layout, "Camera: % : % ", camera.p, camera.p + -camera.z)
        display_line(&layout, "rays per pixel: quality % / fast % ", quality_render.world.rays_per_pixel, fast_render.world.rays_per_pixel)
        
        for &render in renders {
            layout_begin_horizontal(&layout)
            end := render.active ? time.now() : render.end
            display_line(&layout, "Render took: %", fmt.tprintf("%.2v", time.diff(render.start, end)))
            
            if render.active && !work_is_completed(&render.queue){
                total_pixels := render.image.width * render.image.height
                done_percentage := cast(f32) render.world.pixels_done / cast(f32) total_pixels
                
                layout_advance(&layout, 10)
                bar_p := layout.at
                bar_width  := get_dimension(ui_rect).x / 10
                bar_height := cast(f32) FontSize * 0.8
                
                rect     := rectangle_min_dimension(bar_p, v2{bar_width,                                             bar_height})
                progress := rectangle_min_dimension(bar_p, v2{linear_blend(cast(f32) 0, bar_width, done_percentage), bar_height})
                rl.DrawRectangleRec(to_rl_rect(add_radius(rect, 1)), rl.BLACK)
                rl.DrawRectangleLinesEx(to_rl_rect(rect), 2, rl.WHITE)
                rl.DrawRectangleRec(to_rl_rect(progress), rl.WHITE)
                layout_advance(&layout, bar_width)
            }
            
            layout_end_horizontal(&layout)
            layout_advance(&layout, FontSize)
        }
        
        // @todo(viktor): Rebuild the octtree if the spheres are edited in any way
        layout_advance(&layout, FontSize)
        if display_list(&layout, &show_spheres, "Spheres") {
            layout_indent(&layout)
            defer layout_unindent(&layout)
            
            for &sphere, index in world.spheres {
                material := cast(f32) sphere.material
                display_line(&layout, "Sphere %: %", index, material_names[sphere.material])
                
                layout_indent(&layout)
                defer layout_unindent(&layout)
                
                display_slider(&layout, 360, &material, 0, cast(f32) len(material_names)-0.51, "Material Index")
                if sphere.material != round(u32, material) do fast_render.requested = true
                sphere.material = round(u32, material)
                if display_slider  (&layout, 240, &sphere.radius, 0.001, 10, "Radius")                      do fast_render.requested = true
                if display_slider_v(&layout, 240, &sphere.center, -10, 10, "Center", flags = { .relative }) do fast_render.requested = true
                
                layout_advance(&layout, 10)
            }
        }
        
        layout_advance(&layout, FontSize)
        if display_list(&layout, &show_planes, "Planes") {
            layout_indent(&layout)
            defer layout_unindent(&layout)
            
            for &plane, index in world.planes {
                material := cast(f32) plane.material
                display_line(&layout, "Plane %: %", index, material_names[plane.material])
                
                layout_indent(&layout)
                defer layout_unindent(&layout)
                
                display_slider(&layout, 360, &material, 0, cast(f32) len(material_names)-0.51, "Material Index")
                if plane.material != round(u32, material) do fast_render.requested = true
                plane.material = round(u32, material)
                
                if display_slider  (&layout, 240, &plane.radius, 0.1, 1000, "Radius", flags = { .logarithmic }) do fast_render.requested = true
                if display_slider_v(&layout, 240, &plane.center, -10, 10,   "Center", flags = { .relative })    do fast_render.requested = true
                
                layout_advance(&layout, 10)
            }
        }
        
        layout_advance(&layout, FontSize)
        if display_list(&layout, &show_materials, "Materials") {
            layout_indent(&layout)
            defer layout_unindent(&layout)
            
            for &material, index in world.materials {
                if index == 0 do continue
                display_line(&layout, "Material %: material %", index, material_names[index])
                
                layout_indent(&layout)
                defer layout_unindent(&layout)
                
                if display_slider(&layout, 240, &material.scatter, 0, 1, "Scatter")  do fast_render.requested = true
                
                layout_advance(&layout, 10)
                layout_begin_horizontal(&layout)
                color_size :: 50
                {
                    display_line(&layout, "Emit")
                    layout_advance(&layout, 10)
                    
                    // @todo(viktor): emittance could be larger than 1
                    color  := rl.ColorFromNormalized(V4(material.emit, 1))
                    before := color
                    size := to_rl_rect(rectangle_min_dimension(layout.at, color_size))
                    rl.GuiColorPicker(size, "", &color)
                    if color != before do fast_render.requested = true
                    material.emit = rl.ColorNormalize(color).rgb
                    
                    layout_advance(&layout, color_size + 50)
                    layout_advance(&layout, 10)
                }
                
                {
                    display_line(&layout, "Reflect")
                    layout_advance(&layout, 10)
                    
                    color := rl.ColorFromNormalized(V4(material.reflect, 0))
                    before := color
                    size := to_rl_rect(rectangle_min_dimension(layout.at, color_size))
                    rl.GuiColorPicker(size, "", &color)
                    if color != before do fast_render.requested = true
                    material.reflect = rl.ColorNormalize(color).rgb
                }
                layout_end_horizontal(&layout)
                layout_advance(&layout, color_size)
                layout_advance(&layout, 10)
            }
        }
        
        rl.EndDrawing()
    }
}

init_render :: proc (render: ^Render, rays_per_pixel: u32, max_bounce_count: u32, image_width: i32, image_height: i32, core_count: i32) {
    render.world.rays_per_pixel = rays_per_pixel
    render.world.max_bounce_count = max_bounce_count
    
    render.allocator = arena_allocator(&render.arena)
    
    render.image.width  = image_width
    render.image.height = image_height
    render.image.data   = make_slice(context.allocator, [] Color, render.image.width * render.image.height)
    
    create_infos := make_slice(context.allocator, [] CreateThreadInfo, core_count) // @leak
    init_work_queue(&render.queue, create_infos)
}

load_image_into_texture :: proc (texture: ^rl.Texture, image: Image) {
    rl.UnloadTexture(texture^)
    
    rl_image := rl.Image {
        data    = raw_data(image.data),
        width   = image.width,
        height  = image.height,
        mipmaps = 1,
        format  = .UNCOMPRESSED_R8G8B8A8,
    }
    
    texture^ = rl.LoadTextureFromImage(rl_image)
}

axis_angle_rotation :: proc(axis: v3, angle: f32) -> m4 {
    cos_angle := cos(angle)
    sin_angle := sin(angle)
    inv_angle := 1.0 - cos_angle
    
    x, y, z := axis.x, axis.y, axis.z
    
    return m4 {
        inv_angle*x*x + cos_angle,   inv_angle*x*y - sin_angle*z, inv_angle*x*z + sin_angle*y, 0,
        inv_angle*x*y + sin_angle*z, inv_angle*y*y + cos_angle,   inv_angle*y*z - sin_angle*x, 0,
        inv_angle*x*z - sin_angle*y, inv_angle*y*z + sin_angle*x, inv_angle*z*z + cos_angle,   0,
        0,                           0,                           0,                           1,
    }
}

////////////////////////////////////////////////

Layout :: struct {
    font: rl.Font,
    at:  v2,
    
    horizontal: bool,
    base: v2,
}

layout_advance :: proc (layout: ^Layout, dimension: v2) {
    if layout.horizontal {
        layout.at.x += dimension.x
    } else {
        layout.at.y += dimension.y
    }
}

layout_begin_horizontal :: proc (layout: ^Layout) {
    assert(!layout.horizontal)
    layout.horizontal = true
    layout.base = layout.at.x
}

layout_end_horizontal :: proc (layout: ^Layout) {
    assert(layout.horizontal)
    layout.horizontal = false
    layout.at.x = layout.base.x
}

layout_indent :: proc (layout: ^Layout) {
    layout.at.x += 20
}
layout_unindent :: proc (layout: ^Layout) {
    layout.at.x -= 20
}

////////////////////////////////////////////////

SliderFlag :: enum {
    relative,
    logarithmic,
}
SliderFlags :: bit_set[SliderFlag]

// @copypasta
display_slider_v :: proc (layout: ^Layout, width: f32, value: ^$V/[$N] $E, min: V, max: V, format: string = "", args: ..any, flags := SliderFlags{}) -> bool {
    layout_begin_horizontal(layout)
    if format != "" {
        display_line(layout, format, ..args)
        layout_advance(layout, 10)
    }
    
    slider_width := (width - 20) / len(V)
    result: bool
    for i in 0..<len(V) {
        result ||= display_slider_raw(layout, slider_width, &value[i], min[i], max[i], flags = flags)
        layout_advance(layout, 10)
    }
    layout_end_horizontal(layout)
    layout_advance(layout, FontSize)
    return result
}

display_slider :: proc (layout: ^Layout, width: f32, value: ^f32, min: f32, max: f32, format: string = "", args: ..any, flags : SliderFlags = {}) -> bool {
    layout_begin_horizontal(layout)
    if format != "" {
        display_line(layout, format, ..args)
        layout_advance(layout, 10)
    }
    
    result := display_slider_raw(layout, width, value, min, max, flags)
    layout_end_horizontal(layout)
    layout_advance(layout, FontSize)
    return result
}

display_slider_raw :: proc (layout: ^Layout, width: f32, value: ^f32, min: f32, max: f32, flags : SliderFlags = {}) -> bool {
    min := min
    max := max
    if .relative in flags {
        min = value^ + (1.0 / min)
        max = value^ + (1.0 / max)
    }
    
    size := v2{width, FontSize}
    bounds := rectangle_min_dimension(layout.at, size)
    layout_advance(layout, size)
    
    result: bool
    if .logarithmic in flags {
        editing_value := math.ln(value^)
        min = math.ln(min)
        max = math.ln(max)
        rl.GuiSlider(to_rl_rect(bounds), "", "", &editing_value, min, max)
        
        new_value := math.exp(editing_value)
        result = new_value != value^
        value^ = new_value
    } else {
        editing_value := value^
        rl.GuiSlider(to_rl_rect(bounds), "", "", &editing_value, min, max)
        
        result = editing_value != value^
        value^ = editing_value
    }
    
    return result
}

display_line :: proc (layout: ^Layout, format: string, args: ..any) -> f32 {
    text := ctprint(format, ..args)
    size := rl.MeasureTextEx(layout.font, text, FontSize, 1)
    rl.DrawTextEx(layout.font, text, layout.at+2, FontSize, 1, rl.BLACK)
    rl.DrawTextEx(layout.font, text, layout.at, FontSize, 1, rl.WHITE)
    layout_advance(layout, size)
    
    return size.x
}

display_list :: proc (layout: ^Layout, is_open: ^bool, format: string) -> bool {
    bounds := to_rl_rect(rectangle_min_dimension(layout.at, v2{100, FontSize}))
    if rl.GuiButton(bounds, ctprint(format)) {
        is_open^ = !is_open^
    }
    layout_advance(layout, FontSize)
    return is_open^
}

////////////////////////////////////////////////

to_rl_rect :: proc (rect: Rectangle2) -> rl.Rectangle {
    result: rl.Rectangle
    
    result.x = rect.min.x
    result.y = rect.min.y
    result.width  = get_dimension(rect).x
    result.height = get_dimension(rect).y
    
    return result
}