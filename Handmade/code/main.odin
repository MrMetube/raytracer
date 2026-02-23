package main

import os "core:os/os2"
import os_old "core:os"

import img "vendor:stb/image"
import rl "vendor:raylib"

FontSize :: 20

main :: proc() {
    init_spall()
    
    core_count := cast(i32) os_old.processor_core_count() - 1
    
    world: World
    world.ray_per_pixel = 8
    world.max_bounce_count = 8
    
    append(&world.materials, Material{ emit    = { .3  , .4  , .5 },              })
    append(&world.materials, Material{ reflect = { .5  , .5  , .5 }, scatter = 1  })
    append(&world.materials, Material{ reflect = { .7  , .5  , .3 }, scatter = .8 })
    append(&world.materials, Material{ emit    = { 3.5 , 2.0 , .5 }, scatter = 1. })
    append(&world.materials, Material{ reflect = { .2  , .8  , .2 }, scatter = .3 })
    append(&world.materials, Material{ reflect = { .65 , .1  , .7 }, scatter = .9 })
    append(&world.materials, Material{ reflect = { .9  , .9  , .8 }, scatter = .6 })
    
    material_names := make([] string, len(world.materials))
    
    load_brdf_merl("",                                         &world.materials[0].brdf, &world.all_brdf_values); material_names[0] = ""
    load_brdf_merl("./BRDFDatabase/brdfs/gray-plastic.binary", &world.materials[1].brdf, &world.all_brdf_values); material_names[1] = "gray-plastic"
    load_brdf_merl("./BRDFDatabase/brdfs/brass.binary",        &world.materials[2].brdf, &world.all_brdf_values); material_names[2] = "brass"
    load_brdf_merl("./BRDFDatabase/brdfs/gold-paint.binary",   &world.materials[3].brdf, &world.all_brdf_values); material_names[3] = "gold-paint"
    load_brdf_merl("./BRDFDatabase/brdfs/green-latex.binary",  &world.materials[4].brdf, &world.all_brdf_values); material_names[4] = "green-latex"
    load_brdf_merl("./BRDFDatabase/brdfs/purple-paint.binary", &world.materials[5].brdf, &world.all_brdf_values); material_names[5] = "purple-paint"
    load_brdf_merl("./BRDFDatabase/brdfs/white-marble.binary", &world.materials[6].brdf, &world.all_brdf_values); material_names[6] = "white-marble"
    
    append(&world.planes,  Plane  { normal = {0,0,1}, tangent = {}, binormal = {}, center = { 0, 0, 0}, radius = +Infinity, material = 6 })
    append(&world.planes,  Plane  { normal = {1,0,0}, tangent = {}, binormal = {}, center = {-2, 0, 0}, radius = 6, material = 4 })
    
    append(&world.spheres, Sphere { center = { 0, 0, 0}, radius = 1, material = 2 })
    append(&world.spheres, Sphere { center = { 3,-2, 0.4}, radius = .1, material = 3 })
    append(&world.spheres, Sphere { center = {-2,-1, 2}, radius = 1, material = 1 })
    append(&world.spheres, Sphere { center = { 1,-1, 3}, radius = 1, material = 5 })
    append(&world.spheres, Sphere { center = {-2, 3, 0}, radius = 2, material = 6 })
    
    camera: Camera
    camera_look_at(&camera, {0, -7, 1}, {0, 0, 0})
    
    camera_look_at :: proc (camera: ^Camera, p: v3, look_at: v3) {
        camera.p = p
        camera.z = normalize_or_zero(-(look_at - camera.p))
        camera.x = normalize_or_zero(cross(v3{0, 0, 1}, camera.z))
        camera.y = normalize_or_zero(cross(camera.z, camera.x))
    }
    
    fast_factor :: 6
    
    quality_image: Image
    quality_image.width  = 1920
    quality_image.height = 1080
    quality_image.data = make([]Color, quality_image.width * quality_image.height)
    fast_image: Image
    fast_image.width  = quality_image.width  / fast_factor
    fast_image.height = quality_image.height / fast_factor
    fast_image.data = make([]Color, fast_image.width * fast_image.height)
    quality_rays_per_pixel: u32 = 64
    fast_rays_per_pixel: u32 = 8
    
    work_queue: WorkQueue
    create_infos := make([] CreateThreadInfo, core_count)
    init_work_queue(&work_queue, create_infos[:])
    
    ////////////////////////////////////////////////
        
    window_size := v2i { quality_image.width, quality_image.height }
    
    render_active := false
    rl.InitWindow(window_size.x, window_size.y, "Handmade Ray")
    rl.SetTargetFPS(144)
    
    main_texture: rl.Texture
    side_texture: rl.Texture
    font := rl.LoadFontEx("./fonts/VictorMono-Bold.otf", FontSize, nil, 0)

    rl.GuiEnable()
    rl.GuiSetFont(font)
    rl.GuiSetStyle(.DEFAULT, auto_cast rl.GuiDefaultProperty.TEXT_SIZE, FontSize)
    rl.GuiSetStyle(.DEFAULT, auto_cast rl.GuiControlProperty.TEXT_COLOR_NORMAL, auto_cast rl.ColorToInt(rl.WHITE))
    
    ui_rect := rectangle_min_dimension(v2{}, vec_cast(f32, quality_image.width, quality_image.height))
    ui_rect = add_radius(ui_rect, -10)
    
    request_fast_render: bool
    request_quality_render: bool
    world_for_renderer: World
    
    render_image: ^Image
    fast_image_is_focussed: bool
    
    show_materials: bool
    show_planes: bool
    show_spheres: bool
    
    ////////////////////////////////////////////////
    
    mouse_is_look: bool
    request_quality_render = true
    ddp: v3
    dp: v3
    for !rl.WindowShouldClose() {
        delta_time := rl.GetFrameTime()
        
        speed: f32 = 60
        if rl.IsKeyDown(.LEFT_SHIFT) {
            print("sprint %\n", ddp)
        } else {
            ddp *= 0.1
        }
        
        dddp: v3
        if rl.IsKeyDown(.A) do dddp += {-1, 0,  0}
        if rl.IsKeyDown(.D) do dddp += { 1, 0,  0}
        if rl.IsKeyDown(.W) do dddp += { 0, 0, -1}
        if rl.IsKeyDown(.S) do dddp += { 0, 0,  1}
        
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
        
        sensitivity :: 0.2
        if dlook != 0 {
            dlook *= sensitivity * delta_time
            
            axis_angle_rotation :: proc(axis: v3, angle: f32) -> m4 {
                cos_angle := cos(angle)
                sin_angle := sin(angle)
                inv_angle := 1.0 - cos_angle
                
                x, y, z := axis.x, axis.y, axis.z
                
                return m4 {
                    inv_angle*x*x + cos_angle,   inv_angle*x*y - sin_angle*z, inv_angle*x*z + sin_angle*y, 0,
                    inv_angle*x*y + sin_angle*z, inv_angle*y*y + cos_angle,   inv_angle*y*z - sin_angle*x, 0,
                    inv_angle*x*z - sin_angle*y, inv_angle*y*z + sin_angle*x, inv_angle*z*z + cos_angle,   0,
                              0,           0,         0,   1,
                }
            }
            
            yaw_rot := axis_angle_rotation(normalize(camera.y), dlook.x)
            camera.z = normalize(multiply3(yaw_rot, camera.z))
            camera.x = normalize(multiply3(yaw_rot, camera.x))
            
            pitch_rot := axis_angle_rotation(normalize(camera.x), dlook.y)
            camera.z = normalize(multiply3(pitch_rot, camera.z))
            camera.y = normalize(multiply3(pitch_rot, camera.y))
            
            camera.z = normalize_or_zero(camera.z)
            camera.x = normalize_or_zero(cross(v3{0, 0, 1}, camera.z))
            camera.y = normalize_or_zero(cross(camera.z, camera.x))
            
            request_fast_render = true
        }
        
        dddp = normalize_or_zero(dddp)
        dddp *= speed
        ddp += dddp
        ddp *= 0.9
        dp += ddp * delta_time
        dp *= 0.9
        if length_squared(dp) < square(cast(f32) 0.01) do dp = 0
        
        if dp != 0 {
            camera.p += dp.x * camera.x * delta_time
            camera.p += dp.y * camera.y * delta_time
            camera.p += dp.z * camera.z * delta_time
            
            request_fast_render = true
        }
        
        if rl.IsKeyPressed(.J) {
            quality_rays_per_pixel /= 2
        }
        if rl.IsKeyPressed(.K) {
            quality_rays_per_pixel *= 2
        }
        if rl.IsKeyPressed(.N) {
            fast_rays_per_pixel /= 2
        }
        if rl.IsKeyPressed(.M) {
            fast_rays_per_pixel *= 2
        }
        quality_rays_per_pixel = clamp(quality_rays_per_pixel, LaneWidth, 2048)
        fast_rays_per_pixel    = clamp(fast_rays_per_pixel,    LaneWidth, 128)
        
        if rl.IsKeyPressed(.SPACE) {
            request_quality_render = true
        }
        
        if (request_fast_render || request_quality_render) && !render_active {
            render_active = true
            world.bounces_computed = 0
            world.loops_computed = 0
            world.tiles_retired = 0
            world.pixels_done = 0
            
            world_for_renderer = world
            world_for_renderer.spheres   = make([dynamic] Sphere, len(world.spheres))
            world_for_renderer.planes    = make([dynamic] Plane, len(world.planes))
            world_for_renderer.materials = make([dynamic] Material, len(world.materials))
            
            copy(world_for_renderer.spheres[:], world.spheres[:])
            copy(world_for_renderer.planes[:], world.planes[:])
            copy(world_for_renderer.materials[:], world.materials[:])
            
            render_image = &quality_image
            if request_quality_render {
                request_quality_render = false
                world_for_renderer.ray_per_pixel = quality_rays_per_pixel
            } else {
                assert(request_fast_render)
                request_fast_render = false
                
                render_image = &fast_image
                world_for_renderer.ray_per_pixel = fast_rays_per_pixel
            }
            
            begin_one_render(render_image^, core_count, &world_for_renderer, camera, &work_queue)
            
        }
        
        if render_active {
            if work_is_completed(&work_queue) {
                complete_all_work(&work_queue)
                
                render_active = false
                
                load_image_into_texture(&main_texture, quality_image)
                load_image_into_texture(&side_texture, fast_image)
                
                delete(world_for_renderer.spheres)
                delete(world_for_renderer.planes)
                delete(world_for_renderer.materials)
            }
        }
        
        if rl.IsKeyPressed(.R) {
            fast_image_is_focussed = !fast_image_is_focussed
        }
        
        if rl.IsKeyPressed(.F5) && !render_active {
            output_path := "./render.bmp"
            img.write_bmp(ctprint("%", output_path), quality_image.width, quality_image.height, 4, &quality_image.data[0])
            cwd, _ := os.get_working_directory(context.temp_allocator)
            print("Wrote ouput to %/%\n", cwd, output_path)
        }
        
        ////////////////////////////////////////////////
        
        rl.BeginDrawing()
        rl.ClearBackground({0x18, 0x18, 0x18, 0xff})
        if fast_image_is_focussed {
            rl.DrawTextureEx(side_texture, 0, 0, fast_factor, rl.WHITE)
            rl.DrawTextureEx(main_texture, vec_cast(f32, window_size.x - main_texture.width / fast_factor, 0), 0, 1.0 / fast_factor, rl.WHITE)
        } else {
            rl.DrawTextureEx(main_texture, 0, 0, 1, rl.WHITE)
            rl.DrawTextureEx(side_texture, vec_cast(f32, window_size.x - side_texture.width, 0), 0, 1, rl.WHITE)
        }
        
        layout: Layout
        layout.font = font
        layout.at = ui_rect.min
        
        display_line(&layout, "rays per pixel: quality % / fast % ", quality_rays_per_pixel, fast_rays_per_pixel)
        
        if render_active {
            if !work_is_completed(&work_queue) {
                total_pixels := render_image.width * render_image.height
                done_percentage := cast(f32) world_for_renderer.pixels_done / cast(f32) total_pixels
                
                before := layout.at
                text_width := display_line(&layout, "Rendering")
                
                progress_p := before + { text_width + 10, 0 }
                total_size: f32 = get_dimension(ui_rect).x / 10
                rl.DrawRectangleLinesEx({ progress_p.x, progress_p.y, total_size, FontSize}, 2, rl.WHITE)
                rl.DrawRectangleV(progress_p, { linear_blend(cast(f32) 0, total_size, done_percentage) , FontSize}, rl.WHITE)
            }
        } else {
            layout_advance(&layout, FontSize)
        }
        
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
                if sphere.material != round(u32, material) do request_fast_render = true
                sphere.material = round(u32, material)
                if display_slider(&layout,    240, &sphere.radius, 0.001, 10, "Radius")                      do request_fast_render = true
                if display_slider_v3(&layout, 240, &sphere.center, -10, 10, "Center", flags = { .relative }) do request_fast_render = true
                
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
                if plane.material != round(u32, material) do request_fast_render = true
                plane.material = round(u32, material)
                
                if display_slider(&layout,    240, &plane.radius, 0.1, 10, "Radius")                        do request_fast_render = true
                if display_slider_v3(&layout, 240, &plane.center, -10, 10, "Center", flags = { .relative }) do request_fast_render = true
                
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
                
                if display_slider(&layout, 240, &material.scatter, 0, 1, "Scatter")  do request_fast_render = true
                
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
                    if color != before do request_fast_render = true
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
                    if color != before do request_fast_render = true
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

load_image_into_texture :: proc (texture: ^rl.Texture, image: Image) {
    rl_image := rl.Image {
        data = raw_data(image.data),
        width = image.width,
        height = image.height,
        mipmaps = 1,
        format = .UNCOMPRESSED_R8G8B8A8,
    }
    
    texture^ = rl.LoadTextureFromImage(rl_image)
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
    relative
    // @todo(viktor): add logarithmic
}
SliderFlags :: bit_set[SliderFlag]

display_slider_v3 :: proc (layout: ^Layout, width: f32, value: ^v3, min: v3, max: v3, format: string = "", args: ..any, flags := SliderFlags{}) -> bool {
    layout_begin_horizontal(layout)
    if format != "" {
        display_line(layout, format, ..args)
        layout_advance(layout, 10)
    }
    
    slider_width := (width - 20) / 3.0
    result: bool
    result ||= display_slider_raw(layout, slider_width, &value.x, min.x, max.x, flags = flags)
    layout_advance(layout, 10)
    result ||= display_slider_raw(layout, slider_width, &value.y, min.x, max.x, flags = flags)
    layout_advance(layout, 10)
    result ||= display_slider_raw(layout, slider_width, &value.z, min.x, max.x, flags = flags)
    layout_end_horizontal(layout)
    layout_advance(layout, FontSize)
    return result
}

display_slider :: proc (layout: ^Layout, width: f32, value: ^f32, min: f32, max: f32, format: string = "", args: ..any, flags : SliderFlags = {}) -> bool {
    layout_begin_horizontal(layout)
    before := layout^
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
    
    before_value := value^
    rl.GuiSlider(to_rl_rect(bounds), "", "", value, min, max)
    result := value^ != before_value
    
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