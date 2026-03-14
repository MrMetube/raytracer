package main

import "core:os"
import si "core:sys/info"
import "core:time"

import img "vendor:stb/image"
import rl "vendor:raylib"

////////////////////////////////////////////////

Is_Optimized :: ODIN_OPTIMIZATION_MODE == .Speed

main :: proc () {
    rl.SetTraceLogLevel(.WARNING)
    
    window_title := cprint("Handmade Ray %v", (Is_Optimized ? "Optimized" :  "Debug"))
    
    init_spall(output_name = tprint("trace_%v", Is_Optimized ? "optimized" : "debug"))
    
    _, logical_core_count, ok := si.cpu_core_count(); assert(ok)
    core_count := cast(u32) logical_core_count - 1
    
    world: World
    world_init(&world)
    
    teapot_scene(&world)
    ////////////////////////////////////////////////
    
    camera: Camera
    camera.p = {0, -7, 3}
    camera.z = normalize_or_zero(camera.p - {0, 0, 1})
    camera.x = normalize_or_zero(cross(v3{0, 0, 1}, camera.z))
    camera.y = normalize_or_zero(cross(camera.z, camera.x))
    
    ////////////////////////////////////////////////
    
    window_size := v2i { 1920, 1080 }
    
    rl.InitWindow(window_size.x, window_size.y, window_title)
    rl.SetTargetFPS(144)
    
    the_layout: Layout
    layout := &the_layout
    {
        font_size :: 20
        font := rl.LoadFontEx("./fonts/VictorMono-Bold.otf", font_size, nil, 0)
        layout_init(layout, font, Jasmine, font_size)
    }
    
    selected_model_index: int
    show_models: bool
    show_tree_info: bool
    selected_model_info: Tree_Info
    selected_model_build_time: time.Duration
    
    selected_material_index: int
    show_materials: bool
    quality_render_is_open: bool
    fast_render_is_open: bool = true
    
    quality_render: Render
    fast_render:    Render
    init_render(&quality_render, 64, 16, window_size, 2, core_count, "quality render")
    init_render(&fast_render,     8,  4, window_size, 6, core_count, "fast render")
    defer close_work_queue_and_wait_for_threads(&quality_render.queue)
    defer close_work_queue_and_wait_for_threads(&fast_render.queue)
    
    renders := make([dynamic] ^Render, 0, 2, context.allocator)
    append(&renders, &quality_render)
    append(&renders, &fast_render)
    
    ////////////////////////////////////////////////
    
    render_display_progress := false
    
    fast_render.requested = true
    fast_image_is_focussed: bool = true
    
    is_controlling_camera: bool
    ddp: v3
    dp: v3
    for !rl.WindowShouldClose() {
        free_all(context.temp_allocator)
        
        rl.BeginDrawing()
        rl.ClearBackground({0x18, 0x18, 0x18, 0xff})
        
        delta_time := rl.GetFrameTime()
        layout.dt = delta_time
        speed: f32 = 60
        dddp: v3
        dlook: v2
        
        if !rl.IsWindowFocused() {
            is_controlling_camera = false
            rl.ShowCursor()
        } else {
            if rl.IsMouseButtonPressed(.MIDDLE) {
                is_controlling_camera = !is_controlling_camera
            }
            
            if is_controlling_camera {
                if rl.IsKeyDown(.A) do dddp += {-1, 0,  0}
                if rl.IsKeyDown(.D) do dddp += { 1, 0,  0}
                if rl.IsKeyDown(.W) do dddp += { 0, 0, -1}
                if rl.IsKeyDown(.S) do dddp += { 0, 0,  1}
                
                if rl.IsKeyDown(.SPACE)      do dddp += {0, 1,  0}
                if rl.IsKeyDown(.LEFT_SHIFT) do dddp += {0,-1,  0}
                
                if !rl.IsMouseButtonDown(.RIGHT) {
                    ddp *= 0.1
                }
            
                dlook = -rl.GetMouseDelta()
                rl.HideCursor()
                rl.SetMousePosition(window_size.x / 2, window_size.y / 2)
            } else {
                rl.ShowCursor()
            }
            
            if rl.IsKeyPressed(.R) {
                fast_render.requested = true
            }
        }
        
        if dlook != 0 {
            dlook *= 100 / vec_cast(f32, window_size) * delta_time
            up :: v3{0, 0, 1}
            
            yaw   := axis_angle_rotation(camera.y,                           dlook.x)
            pitch := axis_angle_rotation(normalize(multiply(yaw, camera.x)), dlook.y)
            
            new_z := multiply(pitch * yaw, camera.z)
            
            if abs(dot(new_z, up)) < 0.9999 {
                camera.z = new_z
            } else {
                camera.z = multiply(yaw, camera.z)
            }
            
            camera.x = normalize_or_zero(cross(up, camera.z))
            camera.y = normalize_or_zero(cross(camera.z, camera.x))
            
            fast_render.requested = true
        }
        
        
        dddp = normalize_or_zero(dddp)
        dddp *= speed
        ddp  += dddp
        ddp  *= 0.9
        dp   += ddp * delta_time
        dp   *= 0.9
        if length_squared(dp) < square(cast(f32) 0.01) do dp = 0
        
        if dp != 0 {
            camera.p += dp.x * camera.x    * delta_time
            camera.p += dp.y * v3{0, 0, 1} * delta_time
            camera.p += dp.z * camera.z    * delta_time
            
            fast_render.requested = true
        }
        
        for &render in renders {
            if !render.active {
                if render.requested {
                    begin_render(render, &world, core_count, camera)
                }
            } else {
                reload := false
                if work_is_completed(&render.queue) {
                    complete_all_work(&render.queue)
                    
                    render.active = false
                    render.end = time.now()
                    print_render_results(&render.stats, render.start, render.end)
                    
                    free_all(render.allocator)
                    reload = true
                }
                
                if render_display_progress {
                    reload = true
                }
                
                if reload {
                    load_image_into_texture(&render.texture, render.image)
                }
            }
        }
        
        if rl.IsKeyPressed(.TAB) && !(rl.IsKeyDown(.LEFT_ALT) || rl.IsKeyDown(.RIGHT_ALT)) {
            fast_image_is_focussed = !fast_image_is_focussed
        }
        
        if rl.IsKeyPressed(.F5) && !quality_render.active {
            output_path := "./render.bmp"
            img.write_bmp(ctprint("%v", output_path), quality_render.image.width, quality_render.image.height, 4, &quality_render.image.data[0])
            cwd, _ := os.get_working_directory(context.temp_allocator)
            print("Wrote ouput to %v/%v\n", cwd, output_path)
        }
        
        ////////////////////////////////////////////////
        
        layout_begin(layout, 10)
        
        {
            small_factor :: 6
            small_size := window_size / small_factor
            p := window_size - small_size
            p.y = 0
            if fast_image_is_focussed {
                rl.DrawTextureEx(fast_render.texture, 0, 0, cast(f32) fast_render.image_size_factor, rl.WHITE)
                rl.DrawTextureEx(quality_render.texture, vec_cast(f32, p), 0, cast(f32) quality_render.image_size_factor / small_factor, rl.WHITE)
            } else {
                rl.DrawTextureEx(quality_render.texture, 0, 0, cast(f32) quality_render.image_size_factor, rl.WHITE)
                rl.DrawTextureEx(fast_render.texture, vec_cast(f32, p), 0, cast(f32) fast_render.image_size_factor / small_factor, rl.WHITE)
            }
        }
        
        display_line(layout, "Camera: %v : %v ", camera.p, camera.z)
        layout_advance(layout, 10)
        
        layout_begin_horizontal(layout)
            if display_button_highlighted(layout, "Normal",     Debug_View == 0) { Debug_View = 0; fast_render.requested = true }
            layout_advance(layout, 10)
            if display_button_highlighted(layout, "Triangles",  Debug_View == 1) { Debug_View = 1; fast_render.requested = true }
            layout_advance(layout, 10)
            if display_button_highlighted(layout, "Rectangles", Debug_View == 2) { Debug_View = 2; fast_render.requested = true }
            layout_advance(layout, 10)
            if display_button_highlighted(layout, "Both",       Debug_View == 3) { Debug_View = 3; fast_render.requested = true }
        layout_end_horizontal(layout)
        layout_advance(layout, 10)
        
        if Debug_View != 0 {
            layout_begin_horizontal(layout)
                if display_slider(layout, 100, &Triangle_Threshold, 10, 10000, "Triangle Threshold", flags = { .logarithmic }) {
                    fast_render.requested = true
                }
                layout_advance(layout, 10)
                display_line(layout, "%v", view_magnitude(cast(u32) Triangle_Threshold, precision = 1))
            layout_end_horizontal(layout)
            layout_advance(layout, 10)
            layout_begin_horizontal(layout)
                if display_slider(layout, 100, &Rectangle_Threshold, 10, 10000, "Rectangle Threshold", flags = { .logarithmic }) {
                    fast_render.requested = true
                }
                layout_advance(layout, 10)
                display_line(layout, "%v", view_magnitude(cast(u32) Rectangle_Threshold, precision = 1))
            layout_end_horizontal(layout)
            layout_advance(layout, 10)
        }
        
        layout_begin_horizontal(layout)
            display_toggle(layout, "Display Progress", &render_display_progress)
        layout_end_horizontal(layout)
        layout_advance(layout, 10)
        
        if display_render(layout, &quality_render, "Quality", &quality_render_is_open, !fast_image_is_focussed, window_size) {
            fast_image_is_focussed = false
        }
        layout_advance(layout, 10)
        if display_render(layout, &fast_render, "Fast", &fast_render_is_open, fast_image_is_focussed, window_size) {
            fast_image_is_focussed = true
        }
        layout_advance(layout, 10)
        
        layout_advance(layout, layout.font_size)
        if display_list(layout, &show_models, "Models") {
            layout_indent(layout)
            defer layout_unindent(layout)
            
            for &model, model_index in world.models {
                selected, open := display_toggle(layout, tprint("Model %v", model_index), selected_model_index == model_index)
                if selected { selected_model_index = model_index; open = true }
                if open {
                    layout_indent(layout)
                    defer layout_unindent(layout)
                    
                    if display_list(layout, &show_tree_info, "Tree") {
                        layout_indent(layout)
                        
                        display_line(layout, "build took %v", selected_model_build_time)
                        display_line(layout, "node count %v", selected_model_info.node_count)
                        display_line(layout, "depth: max = %v, avg = %.2f", selected_model_info.depth.max, selected_model_info.depth.avg)
                        display_line(layout, "values per node: max = %v, avg = %.2f", selected_model_info.values_per_node.max, selected_model_info.values_per_node.avg)
                        layout_advance(layout, 10)
                        
                        if display_button(layout, "Rebuild") {
                            start := time.now()
                            tree_build(&model.tree, model.triangles)
                            selected_model_build_time = time.since(start)
                            print("building tree took %v\n", selected_model_build_time)
                            selected_model_info = inspect(model.tree)
                            
                            fast_render.requested = true
                        }
                        
                        layout_unindent(layout)
                    }
                                    
                    if display_slider(layout, 100, &model.translation.x, -100, 100, "translate x", flags={.relative}) do fast_render.requested = true
                    if display_slider(layout, 100, &model.translation.y, -100, 100, "translate y", flags={.relative}) do fast_render.requested = true
                    if display_slider(layout, 100, &model.translation.z, -100, 100, "translate z", flags={.relative}) do fast_render.requested = true
                    
                    if display_slider(layout, 100, &model.triangles[0].material, 1, cast(u32) len(world.materials)-1, "material %v", model.triangles[0].material) {
                        fast_render.requested = true
                        for &triangle in model.triangles do triangle.material = model.triangles[0].material
                    }
                }
            }
        }
        
        layout_advance(layout, layout.font_size)
        if display_list(layout, &show_materials, "Materials") {
            layout_indent(layout)
            defer layout_unindent(layout)
            
            for &material, index in world.materials {
                selected, open := display_toggle_condition(layout, tprint("Material %v: material %v", index, world.material_names[index]), index == selected_material_index)
                if selected { selected_material_index = index; open = true }
                if open {
                    layout_indent(layout)
                    defer layout_unindent(layout)
                    
                    if display_slider(layout, 240, &material.scatter,  0,   1, "Scatter") do fast_render.requested = true
                    if display_slider(layout, 240, &material.emit_factor, 0.00001, 1000, "Emittance", flags = {.logarithmic}) do fast_render.requested = true
                    
                    layout_advance(layout, 10)
                    layout_begin_horizontal(layout)
                    color_size :: 40
                    {
                        display_line(layout, "Emit")
                        layout_advance(layout, 10)
                        
                        color  := rl.ColorFromNormalized(V4(material.emit, 1))
                        before := color
                        size := to_rl_rect(rectangle_min_dimension(layout.at, color_size))
                        rl.GuiColorPicker(size, "", &color)
                        if color != before do fast_render.requested = true
                        material.emit = rl.ColorNormalize(color).rgb
                        
                        layout_advance(layout, color_size)
                        layout_advance(layout, color_size)
                        layout_advance(layout, 10)
                    }
                    
                    {
                        display_line(layout, "Reflect")
                        layout_advance(layout, 10)
                        
                        color := rl.ColorFromNormalized(V4(material.reflect, 0))
                        before := color
                        size := to_rl_rect(rectangle_min_dimension(layout.at, color_size))
                        rl.GuiColorPicker(size, "", &color)
                        if color != before do fast_render.requested = true
                        material.reflect = rl.ColorNormalize(color).rgb
                        layout_advance(layout, color_size)
                    }
                    layout_end_horizontal(layout)
                    layout_advance(layout, color_size)
                }
            }
        }
        
        rl.EndDrawing()
    }
}

////////////////////////////////////////////////

display_render :: proc (layout: ^Layout, render: ^Render, name: string, is_open: ^bool, is_focused: bool, window_size: v2i) -> bool { 
    result: bool
    if display_list(layout, is_open, name) {
        layout_indent(layout)
        defer layout_unindent(layout)
        
        layout_begin_horizontal(layout)
            display_toggle(layout, "Render", &render.requested)
            layout_advance(layout, 5)
            // @cleanup
            condition := is_focused
            display_toggle(layout, "Focus", &condition)
            result = !is_focused && condition == true
            if render.active {
                layout_advance(layout, 5)
                display_toggle(layout, "Cancel Render", &render.canceled)
            }
        layout_end_horizontal(layout)
        
        layout_begin_horizontal(layout)
            if display_button(layout, "-") do render.rays_per_pixel /= 2 
            layout_advance(layout, 5)
            if display_button(layout, "+") do render.rays_per_pixel *= 2
            layout_advance(layout, 5)
            display_line(layout, "rays per_pixel %v", render.rays_per_pixel)
            render.rays_per_pixel = clamp(render.rays_per_pixel, LaneWidth, 8192)
        layout_end_horizontal(layout)
        
        layout_begin_horizontal(layout)
            if display_button(layout, "-") do render.max_bounce_count -= render.max_bounce_count <= 8 ? 1 : 2
            layout_advance(layout, 5)
            if display_button(layout, "+") do render.max_bounce_count += render.max_bounce_count  < 8 ? 1 : 2
            render.max_bounce_count = clamp(render.max_bounce_count, 1, 16)
            layout_advance(layout, 5)
            display_line(layout, "bounces %v", render.max_bounce_count)
        layout_end_horizontal(layout)
        
        layout_begin_horizontal(layout)
            if !render.active {
                before := render.image_size_factor
                if display_button(layout, "-") do render.image_size_factor += 1
                layout_advance(layout, 5)
                if display_button(layout, "+") do render.image_size_factor -= 1
                render.image_size_factor = clamp(render.image_size_factor, 1, 16)
                
                if render.image_size_factor != before {
                    init_render_image(render, window_size)
                }
            }
            
            layout_advance(layout, 5)
            display_line(layout, "resolution %vx%v", render.image.width, render.image.height)
        layout_end_horizontal(layout)
        
        layout_begin_horizontal(layout)
            end := render.active ? time.now() : render.end
            display_line(layout, "Render took: %.2v", time.diff(render.start, end))
            
            if render.active && !work_is_completed(&render.queue){
                total_pixels := render.image.width * render.image.height
                done_percentage := cast(f32) render.stats.pixels_done / cast(f32) total_pixels
                
                layout_advance(layout, 10)
                bar_p := layout.at
                bar_width  :: 200
                bar_height := layout.font_size * 0.8
                
                rect     := rectangle_min_dimension(bar_p, v2{bar_width,                                             bar_height})
                progress := rectangle_min_dimension(bar_p, v2{linear_blend(cast(f32) 0, bar_width, done_percentage), bar_height})
                rl.DrawRectangleRec(to_rl_rect(rectangle_add_radius(rect, 1)), rl.BLACK)
                rl.DrawRectangleLinesEx(to_rl_rect(rect), 2, rl.WHITE)
                rl.DrawRectangleRec(to_rl_rect(progress), rl.WHITE)
                layout_advance(layout, bar_width)
            }
        layout_end_horizontal(layout)
    }
    
    return result
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

to_rl_rect :: proc (rect: Rectangle2) -> rl.Rectangle {
    result: rl.Rectangle
    
    result.x = rect.min.x
    result.y = rect.min.y
    result.width  = rectangle_get_dimension(rect).x
    result.height = rectangle_get_dimension(rect).y
    
    return result
}