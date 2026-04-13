package main

import "core:os"
import si "core:sys/info"
import "core:time"

import img "vendor:stb/image"
import rl "vendor:raylib"

Is_Optimized :: ODIN_OPTIMIZATION_MODE == .Speed

////////////////////////////////////////////////

State :: struct {
    window_size: v2i,
    
    ////////////////////////////////////////////////
    
    fast_image_is_focussed: bool,
    renderer: Render,
    quality_render: Render_Settings,
    fast_render:    Render_Settings,
    preview_render: Render_Settings,
    
    ////////////////////////////////////////////////
    
    ui: UI,
    previewed_object_id:  Object_Id,
    selected_object_id: Object_Id,
    selected_material_id: Material_Id,
    ojects_is_open:    bool,
    tree_info_is_open: bool,
    materials_is_open: bool,
    
    selected_model_info: Tree_Info,
    
    ////////////////////////////////////////////////
    
    camera: Camera,
    world:  World,
    
    is_controlling_camera: bool,
    ddp: v3,
    dp:  v3,
    
    ////////////////////////////////////////////////
    
    preview_render_p: v2,
    preview_render_drag_size: f32,
    
    preview_camera: Camera,
    preview_camera_offset: v3,
    preview_camera_orbit:  f32,
    preview_camera_pitch:  f32,
    preview_camera_dolly:  f32,
}

init_state :: proc (state: ^State) {
    state.camera = camera_look_at({0, -7, 3}, {0, 0, 1})
    world_init(&state.world)
    
    if false do default_scene(&state.world)
    if !false do benchmark_scene(&state.world)
    if false do kenney_scene(&state.world)
    if false do brdf_scene(&state.world)
    
    state.preview_render_p = .5 * vec_cast(f32, state.window_size - {state.preview_render.image.width, state.preview_render.image.height})
    state.preview_render_drag_size = 12
    state.preview_camera_offset = {0,0,-1}
    state.preview_camera_pitch = 0.0125 * Tau
    state.preview_camera_dolly = 3
    
    state.fast_render.is_open = true
    state.fast_render.requested = true
    
    state.fast_image_is_focussed = true
    
    init_render_settings(&state.quality_render, 64, 16, state.window_size, 2)
    init_render_settings(&state.fast_render,     8,  8, state.window_size, 6)
    init_render_settings(&state.preview_render, 32,  8, 128, 1)
}

main :: proc () {
    spall_init(output_name = tprint("trace_%v", Is_Optimized ? "optimized" : "debug"))
    
    window_title := cprint("Handmade Ray %v", (Is_Optimized ? "Optimized" :  "Debug"))
    
    _, logical_core_count, ok := si.cpu_core_count(); assert(ok)
    core_count := cast(u32) logical_core_count - 1
    print("Using %v cores per render\n", core_count)
    
    ////////////////////////////////////////////////
    
    the_state: State
    state := &the_state
    ui := &state.ui
    
    state.window_size = v2i { 1920, 1080 }
    
    rl.SetTraceLogLevel(.WARNING)
    rl.InitWindow(state.window_size.x, state.window_size.y, window_title)
    rl.SetTargetFPS(144)
    
    ////////////////////////////////////////////////
    the_layout: Layout
    layout := &the_layout
    {
        font_size :: 20
        font := rl.LoadFontEx("./fonts/VictorMono-Bold.otf", font_size, nil, 0)
        layout_init(layout, font, Jasmine, font_size)
    }
    
    init_render(&state.renderer, core_count)
    defer {
        state.renderer.canceled = true
        close_work_queue_and_wait_for_threads(&state.renderer.queue)
    }
    
    init_state(state)
    
    render_settings := make([dynamic] ^Render_Settings, 0, 2, context.allocator)
    append(&render_settings, &state.quality_render)
    append(&render_settings, &state.fast_render)
    for &render in render_settings {
        stat_init(&render.render_time)
        stat_init(&render.time_per_ray)
    }
    stat_init(&state.preview_render.render_time)
    stat_init(&state.preview_render.time_per_ray)
    
    ////////////////////////////////////////////////
    
    for !rl.WindowShouldClose() {
        free_all(context.temp_allocator)
        
        rl.BeginDrawing()
        rl.ClearBackground({0x18, 0x18, 0x18, 0xff})
        
        delta_time := rl.GetFrameTime()
        layout.dt = delta_time
        
        if !rl.IsWindowFocused() {
            state.is_controlling_camera = false
            rl.ShowCursor()
        } else {
            speed: f32 = 60
            look_speed: f32 = 100
            dddp: v3
            dlook: v2
            if rl.IsMouseButtonPressed(.MIDDLE) {
                state.is_controlling_camera = !state.is_controlling_camera
            }
            
            if state.is_controlling_camera {
                if rl.IsKeyDown(.A) do dddp += {-1, 0,  0}
                if rl.IsKeyDown(.D) do dddp += { 1, 0,  0}
                if rl.IsKeyDown(.W) do dddp += { 0, 0, -1}
                if rl.IsKeyDown(.S) do dddp += { 0, 0,  1}
                
                if rl.IsKeyDown(.SPACE)      do dddp += {0, 1,  0}
                if rl.IsKeyDown(.LEFT_SHIFT) do dddp += {0,-1,  0}
                
                if !rl.IsMouseButtonDown(.RIGHT) {
                    state.ddp *= 0.1
                } else {
                    look_speed *= 5
                }
            
                dlook = -rl.GetMouseDelta()
                rl.HideCursor()
                rl.SetMousePosition(state.window_size.x / 2, state.window_size.y / 2)
            } else {
                rl.ShowCursor()
            }
            
            if rl.IsKeyDown(.R) {
                state.fast_render.requested = true
            }
            
            if dlook != 0 {
                dlook *= look_speed / vec_cast(f32, state.window_size) * delta_time
                up :: v3{0, 0, 1}
                
                yaw   := axis_angle_rotation(state.camera.y,                           dlook.x)
                pitch := axis_angle_rotation(normalize(multiply(yaw, state.camera.x)), dlook.y)
                
                new_z := multiply(pitch * yaw, state.camera.z)
                
                if abs(dot(new_z, up)) < 0.9999 {
                    state.camera.z = new_z
                } else {
                    state.camera.z = multiply(yaw, state.camera.z)
                }
                
                state.camera.x = normalize_or_zero(cross(up, state.camera.z))
                state.camera.y = normalize_or_zero(cross(state.camera.z, state.camera.x))
                
                state.fast_render.requested = true
            }
            
            if dddp != 0 || state.ddp != 0 {
                dddp = normalize_or_zero(dddp)
                dddp *= speed
                state.ddp  += dddp
                state.ddp  *= 0.9
                state.dp   += state.ddp * delta_time
                state.dp   *= 0.9
                if length_squared(state.dp) < square(cast(f32) 0.01) do state.dp = 0
                
                if state.dp != 0 {
                    state.camera.t += state.dp.x * state.camera.x    * delta_time
                    state.camera.t += state.dp.y * v3{0, 0, 1} * delta_time
                    state.camera.t += state.dp.z * state.camera.z    * delta_time
                    
                    state.fast_render.requested = true
                }
            }
            
            if rl.IsKeyPressed(.TAB) && !(rl.IsKeyDown(.LEFT_ALT) || rl.IsKeyDown(.RIGHT_ALT)) {
                state.fast_image_is_focussed = !state.fast_image_is_focussed
            }
            
            if rl.IsKeyPressed(.F5) && !state.quality_render.active {
                output_path := "../output/render.bmp"
                img.write_bmp(ctprint("%v", output_path), state.quality_render.image.width, state.quality_render.image.height, 4, &state.quality_render.image.data[0])
                cwd, _ := os.get_working_directory(context.temp_allocator)
                print("Wrote ouput to %v/%v\n", cwd, output_path)
            }
        }
        
        ////////////////////////////////////////////////
        
        for settings in render_settings {
            if render_begin(&state.renderer, settings) {
                set_camera(settings, state.camera)
                
                for object in state.world.objects {
                    draw_model(settings, object.model, object.material, object.transform)
                }
                
                render_end(&state.renderer, settings, state.world.brdf_data[:], state.world.materials[:])
            }
        }
        
        ////////////////////////////////////////////////
        
        begin_ui(ui)
        
        draw_ui(layout, ui, state, delta_time)
        
        interact(ui)
        
        ////////////////////////////////////////////////
        
        // @cleanup the request system, can we just render every frame?
        if state.fast_render.requested && state.previewed_object_id != 0 {
            state.fast_render.requested  = false
            state.preview_render.requested = true
        }
        
        rl.EndDrawing()
    }
}

////////////////////////////////////////////////

draw_ui :: proc (layout: ^Layout, ui: ^UI, state: ^State, delta_time: f32) {
    layout_begin(layout, ui, 10, delta_time)
    
    {
        small_factor :: 6
        small_size := state.window_size / small_factor
        p := state.window_size - small_size
        p.y = 0
        if state.fast_image_is_focussed {
            rl.DrawTextureEx(state.fast_render.texture, 0, 0, cast(f32) state.fast_render.image_size_factor, rl.WHITE)
            rl.DrawTextureEx(state.quality_render.texture, vec_cast(f32, p), 0, cast(f32) state.quality_render.image_size_factor / small_factor, rl.WHITE)
        } else {
            rl.DrawTextureEx(state.quality_render.texture, 0, 0, cast(f32) state.quality_render.image_size_factor, rl.WHITE)
            rl.DrawTextureEx(state.fast_render.texture, vec_cast(f32, p), 0, cast(f32) state.fast_render.image_size_factor / small_factor, rl.WHITE)
        }
    }
    
    if state.previewed_object_id != 0 {
        preview_render_size := vec_cast(f32, state.preview_render.image.width, state.preview_render.image.height) * cast(f32) state.preview_render.image_size_factor
        
        p := state.preview_render_p
        draw_rectangle_outline(rect_min_dimension(p, preview_render_size), 1, Black)
        rl.DrawTextureEx(state.preview_render.texture, p, 0, cast(f32) state.preview_render.image_size_factor, rl.WHITE)
        
        if rl.IsWindowFocused() {
            // @api how can one hot surface have multiple interactions?
            interaction := Interaction { kind = .NOP, target = &state.preview_camera, right = true, middle = true }
            rect := rect_min_dimension(state.preview_render_p, preview_render_size)
            if rect_contains(rect, layout.ui.mouse_p) {
                layout.ui.next_hot_interaction = interaction
            }
            
            if is_active(layout.ui, interaction) {
                changed_camera := false
                dmousep := rl.GetMouseDelta()
                if rl.IsMouseButtonDown(.LEFT) {
                    rotation_speed :: 0.001 * Tau
                    state.preview_camera_orbit += -dmousep.x * rotation_speed
                    state.preview_camera_pitch += -dmousep.y * rotation_speed
                    changed_camera = true
                } else if rl.IsMouseButtonDown(.RIGHT) {
                    zoom_speed := 0.005 * (state.preview_camera_offset.z - state.preview_camera_dolly)
                    state.preview_camera_dolly += -dmousep.y * zoom_speed
                    changed_camera = true
                } else if rl.IsMouseButtonDown(.MIDDLE) {
                    state.preview_camera = state.camera
                    state.preview_render.requested = true
                }
                
                if changed_camera {
                    state.preview_render.requested = true
                }
                
                object := state.world.objects[state.previewed_object_id]
                state.preview_camera = camera_orbit(state.preview_camera_offset, state.preview_camera_orbit, state.preview_camera_dolly, state.preview_camera_pitch)
                state.preview_camera.t += object.transform.t
            }
            
            ui_mover(ui, &state.preview_render_p, state.preview_render_drag_size)
        }
        
        settings := &state.preview_render
        if render_begin(&state.renderer, settings) {
            object := state.world.objects[state.previewed_object_id]
            
            set_camera(settings, state.preview_camera)
            draw_model(settings, object.model, object.material, object.transform)
            
            render_end(&state.renderer, settings, state.world.brdf_data[:], state.world.materials[:])
        }
    }
    
    ////////////////////////////////////////////////
    
    rerender := state.fast_render.requested
    defer state.fast_render.requested = rerender
    layout_begin_horizontal(layout)
        for kind in Debug_View_Kind {
            if ui_button(layout, set_value_interaction(&Debug_View, kind), "%v", kind, is_highlighted = Debug_View == kind) {
                Debug_View = kind
                rerender = true
            }
        }
        if ui_toggle(layout, &Sort_Subnodes,     "Sort Subnodes")     do rerender = true
        if ui_toggle(layout, &Early_Elimination, "Early Elimination") do rerender = true
    layout_end_horizontal(layout)
    
    
    layout_pad(layout)
    if Debug_View in (bit_set[Debug_View_Kind]{ .Triangle_Tests, .Rectangle_Tests, .Both_Tests }) {
        if ui_dragger(layout, &Triangle_Threshold, "Triangle Threshold %v", view_magnitude(Triangle_Threshold, precision = 1), speed = 1, min = 1, max = 100000, logarithmic = true) {
            rerender = true
        }
        
        if ui_dragger(layout, &Rectangle_Threshold, "Rectangle Threshold %v", view_magnitude(Rectangle_Threshold, precision = 1), speed = 1, min = 1, max = 100000, logarithmic = true) {
            rerender = true
        }
    }
    
    
    if draw_render_settings_ui(state, layout, &state.quality_render, "Quality", !state.fast_image_is_focussed, true, state.window_size) {
        state.fast_image_is_focussed = false
    }
    if draw_render_settings_ui(state, layout, &state.fast_render, "Fast", state.fast_image_is_focussed, true, state.window_size) {
        state.fast_image_is_focussed = true
    }
    draw_render_settings_ui(state, layout, &state.preview_render, "Focus", false, false, 256)
    
    ////////////////////////////////////////////////
    
    
    if ui_collapser(layout, &state.ojects_is_open, "Objects") {
        layout_indent_scope(layout)
        
        
        // @api maybe make an iterator?
        for object_index in 1..=state.world.last_used_object_index {
            object := &state.world.objects[object_index]
            
                if ui_button(layout, set_value_interaction(&state.selected_object_id, object_index), "Object %v", object_index, is_highlighted = state.selected_object_id == object_index) {
                state.selected_object_id = object_index
            }
            
            if state.selected_object_id == object_index {
                layout_indent_scope(layout)
                
                if ui_button(layout, set_value_interaction(&state.previewed_object_id, object_index), "Focus", is_highlighted = state.previewed_object_id == object_index) {
                    if state.previewed_object_id == object_index {
                        state.previewed_object_id = 0
                    } else {
                        state.previewed_object_id = object_index
                        state.preview_render.requested = true
                    }
                }
                
                if ui_collapser(layout, &state.tree_info_is_open, "Inspect Tree") {
                    m := &Models[object.model]
                    state.selected_model_info = inspect(m.tree)
                    
                    layout_indent_scope(layout)
                    ui_text(layout, "triangle count %v", state.selected_model_info.value_count)
                    ui_text(layout, "node count %v", state.selected_model_info.node_count)
                    ui_text(layout, "depth: max = %v, avg = %.2f", state.selected_model_info.depth.max, state.selected_model_info.depth.avg)
                    ui_text(layout, "values per node: max = %v, avg = %.2f", state.selected_model_info.values_per_node.max, state.selected_model_info.values_per_node.avg)
                }
                
                if ui_dragger(layout, &object.transform.x.x, "scale x = %v",       object.transform.x.x) do rerender = true
                if ui_dragger(layout, &object.transform.y.y, "scale y = %v",       object.transform.y.y) do rerender = true
                if ui_dragger(layout, &object.transform.z.z, "scale z = %v",       object.transform.z.z) do rerender = true
                if ui_dragger(layout, &object.transform.t.x, "translation x = %v", object.transform.t.x) do rerender = true
                if ui_dragger(layout, &object.transform.t.y, "translation y = %v", object.transform.t.y) do rerender = true
                if ui_dragger(layout, &object.transform.t.z, "translation z = %v", object.transform.t.z) do rerender = true
                
                max_material_id := cast(Material_Id) len(state.world.materials)-1
                material_released := ui_dragger_clamp_uint(layout, &object.material, "material %v", object.material, min = 1, max = max_material_id)
                if material_released {
                    rerender = true
                }
            }
        }
    }
    
    layout_pad(layout)
    if ui_collapser(layout, &state.materials_is_open, "Materials") {
        layout_indent_scope(layout)
        
        for &material, index in state.world.materials {
            id := cast(Material_Id) index
            if ui_button(layout, set_value_interaction(&state.selected_material_id, id), "Material %v: material %v", id, state.world.material_names[id], is_highlighted = id == state.selected_material_id) {
                state.selected_material_id = id
            }
            
            if id == state.selected_material_id {
                layout_indent_scope(layout)
                
                material.emission = max(0.000001, material.emission)
                if ui_dragger(layout, &material.roughness, "Roughness %f", material.roughness, speed = 0.001, min = 0, max = 1) do rerender = true
                if ui_dragger(layout, &material.emission, "Emission %f", material.emission, logarithmic = true, min = 0.00001, max = 1000) do rerender = true
                if ui_dragger(layout, &material.transmission, "Transmission %f", material.transmission, speed = 0.001, min = 0, max = 1) do rerender = true
                if ui_dragger(layout, &material.index_of_refraction, "Index of Refraction %f", material.index_of_refraction, speed = 0.01, min = 0, max = 10) do rerender = true
                
                layout_begin_horizontal(layout)
                    if ui_color_picker(layout, &material.transmit, "Transmit") do rerender = true
                    if ui_color_picker(layout, &material.emit,     "Emit") do rerender = true
                    if ui_color_picker(layout, &material.reflect,  "Reflect") do rerender = true
                layout_end_horizontal(layout)
                
            }
        }
    }
}

////////////////////////////////////////////////

draw_render_settings_ui :: proc (state: ^State, layout: ^Layout, settings: ^Render_Settings, name: string, is_focused: bool, can_be_focused: bool, window_size: v2i) -> bool { 
    result: bool
    if ui_collapser(layout, &settings.is_open, name) {
        layout_indent_scope(layout)
        
        layout_begin_horizontal(layout)
            if can_be_focused {
                result = ui_button(layout, { kind = .SetValue, target = settings, value = name }, "Focus", is_highlighted = is_focused)
            }
            
            ui_toggle(layout, &settings.display_progress, "Display Progress")
            ui_toggle(layout, &settings.requested,        "Render")
            
            if settings.active {
                ui_text(layout, "%v", time.since(settings.start))
            } else {
                ui_text(layout, "%v", time.diff(settings.start, settings.end))
            }
        layout_end_horizontal(layout)
        layout_pad(layout)
        
        layout_indent(layout)
            if ui_button(layout,  {kind = .SetValue, target = &settings.render_time }, "Reset") {
                stat_init(&settings.render_time, time.diff(settings.start, settings.end))
                stat_finalize(&settings.render_time)
                stat_init(&settings.time_per_ray)
                stat_finalize(&settings.time_per_ray)
            }
            ui_text(layout, "Time: min %v, avg %v, max %v", settings.render_time.min, cast(time.Duration) settings.render_time.avg, settings.render_time.max)
            ui_text(layout, "Time per Ray: min %v, avg %v, max %v", settings.time_per_ray.min, cast(time.Duration) settings.time_per_ray.avg, settings.time_per_ray.max)
        layout_unindent(layout)
        layout_pad(layout)
        
        if settings.active {
            layout_begin_horizontal(layout)
                total_pixels := settings.image.width * settings.image.height
                done_percentage := cast(f32) settings.stats.pixels_done / cast(f32) total_pixels
                ui_progress_bar(layout, done_percentage, 120)
                
                ui_toggle(layout, &state.renderer.canceled, "Cancel Render")
            layout_end_horizontal(layout)
        } else {
            layout_advance(layout, layout.font_size)
        }
        layout_pad(layout)
        
        layout_begin_horizontal(layout)
            if ui_button(layout, set_value_interaction(&settings.rays_per_pixel, settings.rays_per_pixel / 2 ), "-") do settings.rays_per_pixel /= 2 
            if ui_button(layout, set_value_interaction(&settings.rays_per_pixel, settings.rays_per_pixel * 2), "+") do settings.rays_per_pixel *= 2
            ui_text(layout, "rays per_pixel %v", settings.rays_per_pixel)
            settings.rays_per_pixel = clamp(settings.rays_per_pixel, LaneWidth, 8192)
        layout_end_horizontal(layout)
        layout_pad(layout)
        
        ui_dragger(layout, &settings.max_bounce_count, "Bounces %v", settings.max_bounce_count, min = 1, max = 64)
        
        layout_begin_horizontal(layout)
            if !settings.active {
                // @todo(viktor): this generally sucks to use and should just allow the user to set a resolution maybe from a small selection of reasonable ones
                before := settings.image_size_factor
                if ui_button(layout, set_value_interaction(&settings.image_size_factor, settings.image_size_factor + 1), "-") do settings.image_size_factor += 1
                if ui_button(layout, set_value_interaction(&settings.image_size_factor, settings.image_size_factor - 1), "+") do settings.image_size_factor -= 1
                settings.image_size_factor = clamp(settings.image_size_factor, 1, 16)
                
                if settings.image_size_factor != before {
                    init_render_image(settings, window_size)
                }
            }
            
            layout_pad(layout)
            ui_text(layout, "resolution %vx%v", settings.image.width, settings.image.height)
        layout_end_horizontal(layout)
        layout_pad(layout)
    }
    
    return result
}

////////////////////////////////////////////////

camera_look_at :: proc (p: v3, at: v3) -> Camera {
    camera: Camera
    camera.t = p
    camera.z = normalize_or_zero(camera.t - at)
    camera.x = normalize_or_zero(cross(v3{0, 0, 1}, camera.z))
    camera.y = normalize_or_zero(cross(camera.z, camera.x))
    return camera
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
