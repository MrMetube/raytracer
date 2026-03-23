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
    
    spall_init(output_name = tprint("trace_%v", Is_Optimized ? "optimized" : "debug"))
    
    _, logical_core_count, ok := si.cpu_core_count(); assert(ok)
    core_count := cast(u32) logical_core_count - 1
    print("Using %v cores per render\n", core_count)
    
    world: World
    world_init(&world)
    
    default_scene(&world)
    ////////////////////////////////////////////////
    
    camera := camera_look_at({0, -7, 3}, {0, 0, 1})
    
    camera_look_at :: proc (p: v3, at: v3) -> Camera {
        camera: Camera
        camera.t = p
        camera.z = normalize_or_zero(camera.t - at)
        camera.x = normalize_or_zero(cross(v3{0, 0, 1}, camera.z))
        camera.y = normalize_or_zero(cross(camera.z, camera.x))
        return camera
    }
    focus_camera: Camera
    
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
    
    focused_object_index: Object_Index
    selected_object_index: Object_Index
    show_models: bool
    show_tree_info: bool
    selected_model_info: Tree_Info
    selected_model_build_time: time.Duration
    
    selected_material_index: int
    show_materials: bool
    quality_render_is_open: bool
    fast_render_is_open: bool = true
    focus_render_is_open: bool
    
    quality_render: Render
    fast_render:    Render
    focus_render:   Render
    init_render(&quality_render, 64, 16, window_size, 2, core_count, "quality render")
    init_render(&fast_render,    32,  4, window_size, 6, core_count, "fast render")
    init_render(&focus_render,   128, 4, 64*8, 8, core_count, "focus render")
    defer {
        quality_render.canceled = true
        fast_render.canceled    = true
        focus_render.canceled   = true
        close_work_queue_and_wait_for_threads(&quality_render.queue)
        close_work_queue_and_wait_for_threads(&fast_render.queue)
        close_work_queue_and_wait_for_threads(&focus_render.queue)
    }
    focus_render_p: v2 = (vec_cast(f32, window_size) - vec_cast(f32, focus_render.image.width, focus_render.image.height)) / 2
    focus_render_dragged: bool
    focus_render_drag_offset: v2
    focus_render_drag_size :: 12
    focus_camera_offset: v3 = {0,0,-1}
    focus_camera_orbit: f32
    focus_camera_pitch: f32 = 0.0125 * Tau
    focus_camera_dolly: f32 = 3
    
    renders := make([dynamic] ^Render, 0, 2, context.allocator)
    append(&renders, &quality_render)
    append(&renders, &fast_render)
    for &render in renders do stat_init(&render.render_time)
    
    ////////////////////////////////////////////////
    
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
        look_speed: f32 = 100
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
                } else {
                    look_speed *= 5
                }
            
                dlook = -rl.GetMouseDelta()
                rl.HideCursor()
                rl.SetMousePosition(window_size.x / 2, window_size.y / 2)
            } else {
                rl.ShowCursor()
            }
            
            if rl.IsKeyDown(.R) {
                fast_render.requested = true
            }
        }
        
        if dlook != 0 {
            dlook *= look_speed / vec_cast(f32, window_size) * delta_time
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
            camera.t += dp.x * camera.x    * delta_time
            camera.t += dp.y * v3{0, 0, 1} * delta_time
            camera.t += dp.z * camera.z    * delta_time
            
            fast_render.requested = true
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
        
        for render in renders {
            render_begin(render)
            
            set_camera(render, camera)
            
            for object in world.objects {
                draw_model(render, object.model, object.material, object.transform)
            }
            
            render_end(render, world.brdf_data[:], world.materials[:])
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
        
        if focused_object_index != 0 {
            focus_render_size := vec_cast(f32, focus_render.image.width, focus_render.image.height) * cast(f32) focus_render.image_size_factor
            
            if rl.IsWindowFocused() {
                if rl.IsMouseButtonPressed(.LEFT) {
                    if rectangle_contains(rectangle_min_dimension(focus_render_p, focus_render_drag_size), rl.GetMousePosition()) {
                        focus_render_drag_offset = focus_render_p - rl.GetMousePosition()
                        focus_render_dragged = true
                    }
                }
                if rl.IsMouseButtonReleased(.LEFT) {
                    focus_render_dragged = false
                }
                
                if focus_render_dragged {
                    focus_render_p = rl.GetMousePosition() + focus_render_drag_offset
                } else {
                    if rectangle_contains(rectangle_min_dimension(focus_render_p, focus_render_size), rl.GetMousePosition()) {
                        changed_camera := false
                        dmousep := rl.GetMouseDelta()
                        if rl.IsMouseButtonDown(.LEFT) {
                            rotation_speed :: 0.001 * Tau
                            focus_camera_orbit += -dmousep.x * rotation_speed
                            focus_camera_pitch += -dmousep.y * rotation_speed
                            changed_camera = true
                        } else if rl.IsMouseButtonDown(.RIGHT) {
                            zoom_speed := 0.005 * (focus_camera_offset.z - focus_camera_dolly)
                            focus_camera_dolly += -dmousep.y * zoom_speed
                            changed_camera = true
                        } else if rl.IsMouseButtonDown(.MIDDLE) {
                            focus_camera = camera
                            focus_render.requested = true
                        }
                        
                        if changed_camera {
                            focus_render.requested = true
                        }
                        camera_orbit :: proc (p: v3, orbit: f32, dolly, pitch: f32) -> Camera {
                            offset := p
                            
                            camera := xy_rotation(orbit) * yz_rotation(pitch)
                            offset.z += dolly
                            offset = multiply(camera, offset)
                            
                            result: Camera
                            result.x = get_column(camera, 0)
                            result.y = get_column(camera, 1)
                            result.z = get_column(camera, 2)
                            result.t = offset
                            return result
                        }
                        
                        object := world.objects[focused_object_index]
                        focus_camera = camera_orbit(focus_camera_offset, focus_camera_orbit, focus_camera_dolly, focus_camera_pitch)
                        focus_camera.t += object.transform.t
                    }
                }
            } else {
                focus_render_dragged = false
            }
            
            
            if focused_object_index != 0 {
                render := &focus_render
                
                render_begin(render)
                object := world.objects[focused_object_index]
                
                
                set_camera(render, focus_camera)
                draw_model(render, object.model, object.material, object.transform)
                
                render_end(render, world.brdf_data[:], world.materials[:])
            }
            
            p := focus_render_p
            box := rectangle_min_dimension(p, focus_render_size)
            box = rectangle_add_radius(box, 2)
            rl.DrawRectangleRec(rect_to_rl(box), rl.BLACK)
            rl.DrawTextureEx(focus_render.texture, p, 0, cast(f32) focus_render.image_size_factor, rl.WHITE)
            rl.DrawRectangleV(p, focus_render_drag_size, color_to_rl(Isabelline))
        }
        
        display_line(layout, "Camera: %v : %v ", camera.t, camera.z)
        display_line(layout, "Focus: orbit %v : dolly %v : pitch %v ", focus_camera_orbit, focus_camera_dolly, focus_camera_pitch)
        display_line(layout, "Focus Camera  %v : %v ", focus_camera.t, focus_camera.z)
        layout_advance(layout, 10)
        
        layout_begin_horizontal(layout)
            for kind, kind_index in Debug_View_Kind {
                if kind_index != 0 {
                    layout_advance(layout, 10)
                }
                
                if display_button_highlighted(layout, tprint("%v", kind), Debug_View == kind) {
                    Debug_View = kind
                    fast_render.requested = true
                }
            }
        layout_end_horizontal(layout)
        layout_advance(layout, 10)
        
        if Debug_View in (bit_set[Debug_View_Kind]{ .Triangle_Tests, .Rectangle_Tests, .Both_Tests }) {
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
        
        if display_render(layout, &quality_render, "Quality", &quality_render_is_open, !fast_image_is_focussed, window_size) {
            fast_image_is_focussed = false
        }
        layout_advance(layout, 10)
        if display_render(layout, &fast_render, "Fast", &fast_render_is_open, fast_image_is_focussed, window_size) {
            fast_image_is_focussed = true
        }
        display_render(layout, &focus_render, "Focus", &focus_render_is_open, false, 256)
        layout_advance(layout, 10)
        
        layout_advance(layout, layout.font_size)
        if display_list(layout, &show_models, "Objects") {
            layout_indent(layout)
            defer layout_unindent(layout)
            
            // @api maybe make an iterator?
            for object_index in 1..=world.last_used_object_index {
                object := &world.objects[object_index]
                
                selected, open := display_toggle(layout, tprint("Object %v", object_index), selected_object_index == object_index)
                if selected { selected_object_index = object_index; open = true }
                if open {
                    layout_indent(layout)
                    defer layout_unindent(layout)
                    
                    if focus_selected, focused := display_toggle_condition(layout, "Focus", focused_object_index == object_index); focus_selected {
                        if focused {
                            focused_object_index = object_index
                            focus_render.requested = true
                        } else {
                            focused_object_index = 0
                        }
                    }
                    
                    if display_list(layout, &show_tree_info, "Tree") {
                        layout_indent(layout)
                        
                        display_line(layout, "build took %v", selected_model_build_time)
                        display_line(layout, "node count %v", selected_model_info.node_count)
                        display_line(layout, "depth: max = %v, avg = %.2f", selected_model_info.depth.max, selected_model_info.depth.avg)
                        display_line(layout, "values per node: max = %v, avg = %.2f", selected_model_info.values_per_node.max, selected_model_info.values_per_node.avg)
                        layout_advance(layout, 10)
                        
                        if display_button(layout, "Rebuild") {
                            m := &Models[object.model]
                            start := time.now()
                            tree_build(&m.tree, m.triangles, m.normals)
                            selected_model_build_time = time.since(start)
                            print("building tree took %v\n", selected_model_build_time)
                            selected_model_info = inspect(m.tree)
                            
                            fast_render.requested = true
                        }
                        
                        layout_unindent(layout)
                    }
                                    
                    if display_slider_v(layout, 300, &object.transform.x, -100, 100, "x", flags={.relative}) do fast_render.requested = true
                    if display_slider_v(layout, 300, &object.transform.y, -100, 100, "y", flags={.relative}) do fast_render.requested = true
                    if display_slider_v(layout, 300, &object.transform.z, -100, 100, "z", flags={.relative}) do fast_render.requested = true
                    if display_slider_v(layout, 300, &object.transform.t, -100, 100, "translate", flags={.relative}) do fast_render.requested = true
                    
                    if display_slider(layout, 100, &object.material, 1, cast(u32) len(world.materials)-1, "material %v", object.material) {
                        fast_render.requested = true
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
                        size := rect_to_rl(rectangle_min_dimension(layout.at, color_size))
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
                        size := rect_to_rl(rectangle_min_dimension(layout.at, color_size))
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
        
        if fast_render.requested && focused_object_index != 0 {
            fast_render.requested  = false
            focus_render.requested = true
        }
    }
}

////////////////////////////////////////////////

display_render :: proc (layout: ^Layout, render: ^Render, name: string, is_open: ^bool, is_focused: bool, window_size: v2i) -> bool { 
    result: bool
    if display_list(layout, is_open, name) {
        layout_indent(layout)
        defer layout_unindent(layout)
        
        layout_advance(layout, 5)
        layout_begin_horizontal(layout)
            result, _ = display_toggle_condition(layout, "Focus", is_focused)
            
            layout_advance(layout, 5)
            display_toggle(layout, "Display Progress", &render.display_progress)
            
            layout_advance(layout, 5)
            display_toggle(layout, "Render", &render.requested)
            
            layout_advance(layout, 5)
            if render.active {
                display_line(layout, "%v", time.since(render.start))
            } else {
                display_line(layout, "%v", time.diff(render.start, render.end))
            }
        layout_end_horizontal(layout)
        
        layout_advance(layout, 5)
        layout_begin_horizontal(layout)
            if display_button(layout, "Reset") {
                stat_init(&render.render_time, time.diff(render.start, render.end))
                stat_finalize(&render.render_time)
            }
            layout_advance(layout, 5)
            display_line(layout, "Render time: min = %v, avg = %v, max = %v", render.render_time.min, cast(time.Duration) render.render_time.avg, render.render_time.max)
        layout_end_horizontal(layout)
        
        layout_advance(layout, 5)
        if render.active && !work_is_completed(&render.queue){
            layout_begin_horizontal(layout)
                total_pixels := render.image.width * render.image.height
                done_percentage := cast(f32) render.stats.pixels_done / cast(f32) total_pixels
                
                bar_width  :: 120
                bar_height_scale :: 0.75
                bar_height := layout.font_size * bar_height_scale
                border_size :: 2
                bar_p := layout.at + {0, bar_height * (1 - bar_height_scale)}
                
                rect     := rectangle_min_dimension(bar_p, v2{bar_width,                                             bar_height})
                progress := rectangle_min_dimension(bar_p, v2{linear_blend(cast(f32) 0, bar_width, done_percentage), bar_height})
                progress  = rectangle_add_radius(progress, -border_size)
                
                // @todo(viktor): use the layout/rl gui style colors
                rl.DrawRectangleRec(    rect_to_rl(rect),              color_to_rl(Green))
                rl.DrawRectangleLinesEx(rect_to_rl(rect), border_size, color_to_rl(DarkGreen))
                rl.DrawRectangleRec(    rect_to_rl(progress),          color_to_rl(Isabelline))
                layout_advance(layout, bar_width)
                
                layout_advance(layout, 5)
                display_toggle(layout, "Cancel Render", &render.canceled)
            layout_end_horizontal(layout)
        } else {
            layout_advance_2(layout, layout.font_size)
        }
            
        layout_advance(layout, 5)
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

rect_to_rl :: proc (rect: Rectangle2) -> rl.Rectangle {
    result: rl.Rectangle
    
    result.x = rect.min.x
    result.y = rect.min.y
    result.width  = rectangle_get_dimension(rect).x
    result.height = rectangle_get_dimension(rect).y
    
    return result
}

color_to_rl :: proc (color: $V) -> rl.Color {
    bytes := color_to_u8(color)
    result := transmute(rl.Color) bytes
    return result
}