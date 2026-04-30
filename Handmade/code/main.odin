package main

import "core:os"
import si "core:sys/info"
import "core:time"

import img "vendor:stb/image"
import rl "vendor:raylib"

Is_Optimized :: ODIN_OPTIMIZATION_MODE == .Speed

////////////////////////////////////////////////

State :: struct {
    window_size: iv2,
    
    ////////////////////////////////////////////////
    
    fast_image_is_focussed: bool,
    renderer: Render,
    quality_render: Render_Settings,
    fast_render:    Render_Settings,
    preview_render: Render_Settings,
    
    ////////////////////////////////////////////////
    
    ui: UI,
    previewed_object_id:  Object_Id,
    selected_object_id:   Object_Id,
    selected_material_id: Material_Id,
    ojects_is_open:    bool,
    materials_is_open: bool,
    
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

state_init :: proc (state: ^State) {
    state.camera = camera_look_at({0, -7, 3}, {0, 0, 1})
    world_init(&state.world)
    
    if !false do default_scene(&state.world)
    if false do benchmark_scene(&state.world)
    if false do kenney_scene(&state.world)
    
    state.preview_render_p = .5 * vec_cast(f32, state.window_size - {state.preview_render.image.width, state.preview_render.image.height})
    state.preview_render_drag_size = 12
    state.preview_camera_offset = {0,0,-1}
    state.preview_camera_pitch = 0.0125 * Tau
    state.preview_camera_dolly = 3
    
    state.fast_render.is_open = true
    state.fast_render.requested = true
    
    state.fast_image_is_focussed = true
    
    init_render_settings(&state.quality_render, 64, 16, state.window_size)
    init_render_settings(&state.fast_render,     8,  8, state.window_size / 4)
    init_render_settings(&state.preview_render, 32,  8, 128)
    
    font_size :: 18
    font := rl.LoadFontEx("./fonts/VictorMono-Bold.otf", font_size, nil, 0)
    ui_init(&state.ui, font, font_size)
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
    
    state.window_size = iv2 { 1920, 1080 }
    
    rl.SetTraceLogLevel(.WARNING)
    rl.InitWindow(state.window_size.x, state.window_size.y, window_title)
    rl.SetTargetFPS(144)
    
    ////////////////////////////////////////////////
    the_layout: Element
    layout := &the_layout
    
    init_render(&state.renderer, core_count)
    defer {
        state.renderer.canceled = true
        close_work_queue_and_wait_for_threads(&state.renderer.queue)
    }
    
    state_init(state)
    
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
        rl.ClearBackground({0x00, 0x00, 0x00, 0xff})
        
        delta_time := rl.GetFrameTime()
        ui.dt = delta_time
        
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
                state.ddp += dddp
                state.ddp *= 0.9
                state.dp  += state.ddp * delta_time
                state.dp  *= 0.9
                if length_squared(state.dp) < square(cast(f32) 0.01) do state.dp = 0
                
                if state.dp != 0 {
                    state.camera.t += state.dp.x * state.camera.x * delta_time
                    state.camera.t += state.dp.y * v3{0, 0, 1}    * delta_time
                    state.camera.t += state.dp.z * state.camera.z * delta_time
                    
                    state.fast_render.requested = true
                }
            }
            
            if rl.IsKeyPressed(.TAB) && !rl.IsKeyDown(.LEFT_ALT) && !rl.IsKeyDown(.RIGHT_ALT) {
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
                
                render_end(&state.renderer, settings, state.world.materials[:])
            }
        }
        
        ////////////////////////////////////////////////
        
        begin_ui(ui, delta_time)
            draw_ui(layout, state)
            interact(ui)
        end_ui(ui)
        
        ////////////////////////////////////////////////
        
        // @cleanup the request system, can we just render every frame?
        if state.fast_render.requested && state.previewed_object_id != 0 {
            state.preview_render.requested = true
        }
        
        rl.EndDrawing()
    }
}

////////////////////////////////////////////////

draw_ui :: proc (layout: ^Element, state: ^State) {
    screen_dim    := vec_cast(f32, state.window_size)
    screen_bounds := rect_zero_dimension(screen_dim)
    layout_bounds := rect_add_radius(screen_bounds, -10)
    
    layout_begin(layout, layout_bounds, 8)
    
    ui_push_parent(layout)
    defer ui_pop_parent()
    
    {
        factor :: 0.2
        small_bounds := rect_min_dimension(v2{screen_dim.x * (1 - factor), 0}, screen_dim * factor)
        
        if state.fast_image_is_focussed {
            draw_texture(state.fast_render.texture, screen_bounds)
            draw_texture(state.quality_render.texture, small_bounds)
        } else {
            draw_texture(state.quality_render.texture, screen_bounds)
            draw_texture(state.fast_render.texture, small_bounds)
        }
    }
    
    if state.previewed_object_id != 0 {
        preview_render_size := vec_cast(f32, state.preview_render.image.width, state.preview_render.image.height)
        
        p := state.preview_render_p
        draw_rectangle_outline(rect_min_dimension(p, preview_render_size), 1, Black)
        draw_texture(state.preview_render.texture, rect_min_dimension(p, preview_render_size))
        
        if rl.IsWindowFocused() {
            // @api how can one hot surface have multiple interactions?
            interaction := Interaction { kind = .NOP, target = &state.preview_camera, right = true, middle = true }
            rect := rect_min_dimension(state.preview_render_p, preview_render_size)
            if rect_contains(rect, the_ui.mouse_p) {
                the_ui.next_hot_interaction = interaction
            }
            
            if is_active(the_ui, interaction) {
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
            
            ui_mover(the_ui, &state.preview_render_p, state.preview_render_drag_size)
        }
        
        settings := &state.preview_render
        if render_begin(&state.renderer, settings) {
            object := state.world.objects[state.previewed_object_id]
            
            set_camera(settings, state.preview_camera)
            draw_model(settings, object.model, object.material, object.transform)
            
            render_end(&state.renderer, settings, state.world.materials[:])
        }
    }
    
    ////////////////////////////////////////////////
    
    rerender := state.fast_render.requested
    defer state.fast_render.requested = rerender
    
    begin_horizontal()
        for kind in Debug_View_Kind {
            if ui_radio_button(&Debug_View, kind, "%v", kind).clicked {
                rerender = true
            }
        }
        if ui_toggle(&Sort_Subnodes,     "Sort Subnodes")     do rerender = true
        if ui_toggle(&Early_Elimination, "Early Elimination") do rerender = true
    end_horizontal()
    
    layout_advance(layout, layout.spacing)
    tests := bit_set[Debug_View_Kind] { .Triangle_Tests, .Rectangle_Tests, .Both_Tests }
    if Debug_View in tests {
        if ui_dragger(&Triangle_Threshold, "Triangle Threshold %v", view_magnitude(Triangle_Threshold, precision = 1), speed = 1, min = 1, max = 100000, logarithmic = true) {
            rerender = true
        }
        
        if ui_dragger(&Rectangle_Threshold, "Rectangle Threshold %v", view_magnitude(Rectangle_Threshold, precision = 1), speed = 1, min = 1, max = 100000, logarithmic = true) {
            rerender = true
        }
    }
    
    {
        resolutions := [?] iv2 {
            {1920, 1080},
            {1280,  720},
            { 960,  540},
            { 640,  360},
            { 480,  270},
            { 320,  180},
        }
        square_resolutions := [?] iv2 {
            { 1024, 1024},
            {  512,  512},
            {  256,  256},
            {  128,  128},
        }
        if draw_render_settings_ui(state, layout, &state.quality_render, "Quality", !state.fast_image_is_focussed, true, resolutions[:]) {
            state.fast_image_is_focussed = false
        }
        if draw_render_settings_ui(state, layout, &state.fast_render, "Fast", state.fast_image_is_focussed, true, resolutions[:]) {
            state.fast_image_is_focussed = true
        }
        draw_render_settings_ui(state, layout, &state.preview_render, "Focus", false, false, square_resolutions[:])
    }
    ////////////////////////////////////////////////
    
    if ui_collapser(&state.ojects_is_open, "Objects") {
        layout_indent_scope(layout)
        
        // @api maybe make an iterator?
        for object_index in 1..=state.world.last_used_object_index {
            object := &state.world.objects[object_index]
            
            
            if ui_radio_button(&state.selected_object_id, object_index, "Object %v", object_index).is_selected {
                layout_indent_scope(layout)
                
                if ui_radio_button(&state.previewed_object_id, object_index, "Focus").clicked {
                    if state.previewed_object_id == object_index {
                        state.previewed_object_id = 0
                    } else {
                        state.previewed_object_id = object_index
                        state.preview_render.requested = true
                    }
                }
                
                if ui_dragger(&object.transform.x.x, "scale x = %v",       object.transform.x.x) do rerender = true
                if ui_dragger(&object.transform.y.y, "scale y = %v",       object.transform.y.y) do rerender = true
                if ui_dragger(&object.transform.z.z, "scale z = %v",       object.transform.z.z) do rerender = true
                if ui_dragger(&object.transform.t.x, "translation x = %v", object.transform.t.x) do rerender = true
                if ui_dragger(&object.transform.t.y, "translation y = %v", object.transform.t.y) do rerender = true
                if ui_dragger(&object.transform.t.z, "translation z = %v", object.transform.t.z) do rerender = true
                
                max_material_id := cast(Material_Id) len(state.world.materials)-1
                if ui_dragger(&object.material, "material = %v: %v", object.material, state.world.material_names[object.material], min = 1, max = max_material_id) {
                    rerender = true
                }
            }
        }
    }
    
    layout_advance(layout, layout.spacing)
    if ui_collapser(&state.materials_is_open, "Materials") {
        layout_indent_scope(layout)
        
        for &material, index in state.world.materials {
            id := cast(Material_Id) index
            
            
            if ui_radio_button(&state.selected_material_id, id, "%v: %v", id, state.world.material_names[id]).is_selected {
                layout_indent_scope(layout)
                
                material.emit_strength = max(0.000001, material.emit_strength)
                if ui_dragger(&material.emit_strength, "emit strength %f", material.emit_strength, logarithmic = true, min = 0.00001, max = 1000) do rerender = true
                if ui_dragger_01(&material.roughness,         "roughness %f",         material.roughness)         do rerender = true
                if ui_dragger_01(&material.specular_strength, "specular_strength %f", material.specular_strength) do rerender = true
                if ui_dragger_01(&material.anisotropic,       "anisotropic %f",       material.anisotropic)       do rerender = true
                if ui_dragger_01(&material.subsurface,        "subsurface %f",        material.subsurface)        do rerender = true
                if ui_dragger_01(&material.sheen,             "sheen %f",             material.sheen)             do rerender = true
                if ui_dragger_01(&material.sheen_tint,        "sheen_tint %f",        material.sheen_tint)        do rerender = true
                if ui_dragger_01(&material.metallic,          "metallic %f",          material.metallic)          do rerender = true
                if ui_dragger_01(&material.clearcoat,         "clearcoat %f",         material.clearcoat)         do rerender = true
                if ui_dragger_01(&material.clearcoat_gloss,   "clearcoat_gloss %f",   material.clearcoat_gloss)   do rerender = true
                
                begin_horizontal()
                    if ui_color_picker(&material.emit_color, "emit color") do rerender = true
                    if ui_color_picker(&material.base_tint,  "base tint")  do rerender = true
                end_horizontal()
            }
        }
    }
}

////////////////////////////////////////////////

draw_render_settings_ui :: proc (state: ^State, layout: ^Element, settings: ^Render_Settings, name: string, is_focused: bool, can_be_focused: bool, resolutions: [] iv2) -> bool {
    result: bool
    if ui_collapser(&settings.is_open, name) {
        layout_indent_scope(layout)
        
        begin_horizontal()
            if can_be_focused {
                // @todo(viktor): is_focused -> highlighted
                result = ui_button({ kind = .SetValue, target = settings, value = name }, "Focus")
            }
            
            ui_toggle(&settings.display_progress, "Display Progress")
            ui_toggle(&settings.requested,        "Render")
            
            if settings.active {
                ui_text("%v", time.since(settings.start))
            } else {
                ui_text("%v", time.diff(settings.start, settings.end))
            }
        end_horizontal()
        layout_advance(layout, layout.spacing)
        
        layout_indent(layout)
            if ui_button({kind = .SetValue, target = &settings.render_time }, "Reset") {
                if !settings.active {
                    stat_init(&settings.render_time, time.diff(settings.start, settings.end))
                } else {
                    stat_init(&settings.render_time)
                }
                stat_finalize(&settings.render_time)
                stat_init(&settings.time_per_ray)
                stat_finalize(&settings.time_per_ray)
            }
            ui_text("Time: min %v, avg %v, max %v",         settings.render_time.min,  cast(time.Duration) settings.render_time.avg,  settings.render_time.max)
            ui_text("Time per Ray: min %v, avg %v, max %v", settings.time_per_ray.min, cast(time.Duration) settings.time_per_ray.avg, settings.time_per_ray.max)
        layout_unindent(layout)
        layout_advance(layout, layout.spacing)
        
        if settings.active {
            begin_horizontal()
                total_pixels := settings.image.width * settings.image.height
                done_percentage := cast(f32) settings.stats.pixels_done / cast(f32) total_pixels
                ui_progress_bar(done_percentage, 120)
                
                ui_toggle(&state.renderer.canceled, "Cancel Render")
            end_horizontal()
        } else {
            layout_advance(layout, {0, the_ui.font_size})
        }
        layout_advance(layout, layout.spacing)
        
        begin_horizontal()
            if ui_button(set_value_interaction(&settings.rays_per_pixel, settings.rays_per_pixel / 2 ), "-") do settings.rays_per_pixel /= 2 
            if ui_button(set_value_interaction(&settings.rays_per_pixel, settings.rays_per_pixel * 2), "+") do settings.rays_per_pixel *= 2
            ui_text("rays per_pixel %v", settings.rays_per_pixel)
            settings.rays_per_pixel = clamp(settings.rays_per_pixel, LaneWidth, 8192)
        end_horizontal()
        layout_advance(layout, layout.spacing)
        
        ui_dragger(&settings.max_bounce_count, "Bounces %v", settings.max_bounce_count, min = 1, max = 64)
        
        if ui_collapser(&settings.resolution_open, "resolution %vx%v", settings.image.width, settings.image.height) {
            begin_horizontal()
                if !settings.active {
                    for size, index in resolutions {
                        if ui_button(interaction(.SetValue, settings, index), "%vx%v", size.x, size.y) {
                            if size.x != settings.image.width || size.y != settings.image.height {
                                init_render_image(settings, size)
                            }
                        }
                    }
                }
                
            end_horizontal()
        }
        layout_advance(layout, layout.spacing)
    }
    
    return result
}