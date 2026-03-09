package main

import "core:os"
import si "core:sys/info"
import "core:time"
import "core:fmt"

import img "vendor:stb/image"
import rl "vendor:raylib"

FontSize :: 20

Use_Tree := true

////////////////////////////////////////////////

Is_Optimized :: ODIN_OPTIMIZATION_MODE == .Speed

// @cleanup after this is tested with a huge model for build time
Tree_Max_Depth: u32 = 32

main :: proc () {
    rl.SetTraceLogLevel(.WARNING)
    
    window_title := cprint("Handmade Ray %", (Is_Optimized ? "Optimized" :  "Debug"))
    
    init_spall(output_name = tprint("trace_%", Is_Optimized ? "optimized" : "debug"))
    
    _, logical_core_count, ok := si.cpu_core_count()
    assert(ok)
    core_count := cast(u32) logical_core_count - 1
    
    world: World
    
    append(&world.materials, Material{ emit    = { .3  , .4  , .5  }, emit_factor = 2   })
    append(&world.materials, Material{ reflect = { .5  , .5  , .5  }, scatter = .1      })
    append(&world.materials, Material{ reflect = { .7  , .5  , .3  }, scatter = .8      })
    append(&world.materials, Material{ emit    = { .35 , .2 ,  .01 }, emit_factor = 1000 })
    append(&world.materials, Material{ reflect = { .2  , .8  , .2  }, scatter = .5      })
    append(&world.materials, Material{ reflect = { .65 , .1  , .7  }, scatter = 1.      })
    append(&world.materials, Material{ reflect = { .9  , .9  , .8  }, scatter = .6      })
    
    material_names := make_slice(context.allocator, [] string, len(world.materials))
    
    load_brdf_merl("",                                         &world.materials[0].brdf, &world.all_brdf_values); material_names[0] = ""
    load_brdf_merl("./BRDFDatabase/brdfs/gray-plastic.binary", &world.materials[1].brdf, &world.all_brdf_values); material_names[1] = "gray-plastic"
    load_brdf_merl("./BRDFDatabase/brdfs/brass.binary",        &world.materials[2].brdf, &world.all_brdf_values); material_names[2] = "brass"
    load_brdf_merl("./BRDFDatabase/brdfs/gold-paint.binary",   &world.materials[3].brdf, &world.all_brdf_values); material_names[3] = "gold-paint"
    load_brdf_merl("./BRDFDatabase/brdfs/green-latex.binary",  &world.materials[4].brdf, &world.all_brdf_values); material_names[4] = "green-latex"
    load_brdf_merl("./BRDFDatabase/brdfs/purple-paint.binary", &world.materials[5].brdf, &world.all_brdf_values); material_names[5] = "purple-paint"
    load_brdf_merl("./BRDFDatabase/brdfs/white-marble.binary", &world.materials[6].brdf, &world.all_brdf_values); material_names[6] = "white-marble"
    
    // @todo(viktor): fixed Buffer of models and return indices
    reserve(&world.models, 128)
    
    // append(&world.planes, Plane { normal = { 0, 0,-1}, tangent = {}, binormal = {}, center = { 0, 0, area_size},     radius = area_size,   material = 6 })
    // append(&world.planes, Plane { normal = { 1, 0, 0}, tangent = {}, binormal = {}, center = {-area_size, 0, 0},     radius = area_size,   material = 1 })
    // append(&world.planes, Plane { normal = {-1, 0, 0}, tangent = {}, binormal = {}, center = {+area_size, 0, 0},     radius = area_size,   material = 5 })
    // append(&world.planes, Plane { normal = { 0,-1, 0}, tangent = {}, binormal = {}, center = {0, +area_size, 0},     radius = area_size,   material = 4 })
    
    // @cleanup 
    { // light
        plane := world_create_model(&world)
        
        v0 := v3 {-1, -1, 0}
        v1 := v3 {-1,  1, 0}
        v2 := v3 { 1,  1, 0}
        v3 := v3 { 1, -1, 0}
        
        append(&plane.triangles, Triangle{ a = v0, b = v2, c = v3, material = 3})
        append(&plane.triangles, Triangle{ a = v0, b = v1, c = v2, material = 3})
        
        for &t in plane.triangles {
            t.a.z += 4
            t.b.z += 4
            t.c.z += 4
        }
        
        tree_build(&plane.tree, plane.triangles)
    }
    { // ground
        plane := world_create_model(&world)
        
        v0 := v3 {-1, -1, 0}
        v1 := v3 {-1,  1, 0}
        v2 := v3 { 1,  1, 0}
        v3 := v3 { 1, -1, 0}
        
        append(&plane.triangles, Triangle{ a = v0, b = v2, c = v3, material = 1})
        append(&plane.triangles, Triangle{ a = v0, b = v1, c = v2, material = 1})
        
        for &t in plane.triangles {
            t.a.xy *= 500
            t.b.xy *= 500
            t.c.xy *= 500
        }
        
        tree_build(&plane.tree, plane.triangles)
    }
    { // top
        plane := world_create_model(&world)
        
        v0 := v3 {-1, -1, 0}
        v1 := v3 {-1,  1, 0}
        v2 := v3 { 1,  1, 0}
        v3 := v3 { 1, -1, 0}
        
        append(&plane.triangles, Triangle{ a = v0, b = v2, c = v3, material = 6})
        append(&plane.triangles, Triangle{ a = v0, b = v1, c = v2, material = 6})
        
        for &t in plane.triangles {
            t.a.xy *= 4
            t.b.xy *= 4
            t.c.xy *= 4
            t.a.z += 4
            t.b.z += 4
            t.c.z += 4
        }
        
        tree_build(&plane.tree, plane.triangles)
    }
    { // back
        plane := world_create_model(&world)
        
        v0 := v3 {-1, 0, -1}
        v1 := v3 {-1, 0,  1}
        v2 := v3 { 1, 0,  1}
        v3 := v3 { 1, 0, -1}
        
        append(&plane.triangles, Triangle{ a = v0, b = v2, c = v3, material = 6})
        append(&plane.triangles, Triangle{ a = v0, b = v1, c = v2, material = 6})
        
        for &t in plane.triangles {
            t.a.xz *= 4
            t.b.xz *= 4
            t.c.xz *= 4
            t.a.y += 4
            t.b.y += 4
            t.c.y += 4
        }
        
        tree_build(&plane.tree, plane.triangles)
    }
    { // right
        plane := world_create_model(&world)
        
        v0 := v3 {0, -1, -1}
        v1 := v3 {0, -1,  1}
        v2 := v3 {0,  1,  1}
        v3 := v3 {0,  1, -1}
        
        append(&plane.triangles, Triangle{ a = v0, b = v2, c = v3, material = 5})
        append(&plane.triangles, Triangle{ a = v0, b = v1, c = v2, material = 5})
        
        for &t in plane.triangles {
            t.a.yz *= 4
            t.b.yz *= 4
            t.c.yz *= 4
            t.a.x += 4
            t.b.x += 4
            t.c.x += 4
        }
        
        tree_build(&plane.tree, plane.triangles)
    }
    { // left
        plane := world_create_model(&world)
        
        v0 := v3 {0, -1, -1}
        v1 := v3 {0, -1,  1}
        v2 := v3 {0,  1,  1}
        v3 := v3 {0,  1, -1}
        
        append(&plane.triangles, Triangle{ a = v0, b = v2, c = v3, material = 4})
        append(&plane.triangles, Triangle{ a = v0, b = v1, c = v2, material = 4})
        
        for &t in plane.triangles {
            t.a.yz *= 4
            t.b.yz *= 4
            t.c.yz *= 4
            t.a.x -= 4
            t.b.x -= 4
            t.c.x -= 4
        }
        
        tree_build(&plane.tree, plane.triangles)
    }
    
    
    
    // 0 =   3488 triangles
    // 1 =  19480 triangles, 5.5x 0
    // 2 = 145620 triangles, 7.5x 1
    
    teapot := world_create_model(&world)
    clear(&teapot.triangles)
    load_teapot(&teapot.triangles, 1, 2)
    
    start := time.now()
    tree_build(&teapot.tree, teapot.triangles)
    build_time := time.since(start)
    print("build time %\n", fmt.tprint(build_time))
    
    inspection := inspect(teapot.tree)
    {
        print_inspection(teapot.triangles, inspection)
    }
    
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
    
    font := rl.LoadFontEx("./fonts/VictorMono-Bold.otf", FontSize, nil, 0)
    
    rl.GuiEnable()
    rl.GuiSetFont(font)
    rl.GuiSetStyle(.DEFAULT, auto_cast rl.GuiDefaultProperty.TEXT_SIZE, FontSize)
    
    {
        Background := color_to_u8(DarkGreen)
        Foreground := color_to_u8(Jasmine)
        Highlight  := color_to_u8(Green)
        Focus      := color_to_u8(Isabelline)
        None       := color_to_u8(v4{})
        rlGuiSetColor(.DEFAULT, auto_cast rl.GuiControlProperty.TEXT_COLOR_NORMAL, Foreground)
        rlGuiSetColor(.DEFAULT, auto_cast rl.GuiControlProperty.BASE_COLOR_NORMAL, Background)
        rlGuiSetColor(.DEFAULT, auto_cast rl.GuiControlProperty.BORDER_COLOR_NORMAL, None)
        rlGuiSetColor(.DEFAULT, auto_cast rl.GuiControlProperty.TEXT_COLOR_FOCUSED, Focus)
        rlGuiSetColor(.DEFAULT, auto_cast rl.GuiControlProperty.BASE_COLOR_FOCUSED, Highlight)
        rlGuiSetColor(.DEFAULT, auto_cast rl.GuiControlProperty.BORDER_COLOR_FOCUSED, Background)
        rlGuiSetColor(.DEFAULT, auto_cast rl.GuiControlProperty.TEXT_COLOR_PRESSED, Highlight)
        rlGuiSetColor(.DEFAULT, auto_cast rl.GuiControlProperty.BASE_COLOR_PRESSED, Focus)
        rlGuiSetColor(.DEFAULT, auto_cast rl.GuiControlProperty.BORDER_COLOR_PRESSED, Highlight)
        rlGuiSetColor(.DEFAULT, auto_cast rl.GuiControlProperty.TEXT_COLOR_DISABLED, Highlight)
        rlGuiSetColor(.DEFAULT, auto_cast rl.GuiControlProperty.BASE_COLOR_DISABLED, Background)
        rlGuiSetColor(.DEFAULT, auto_cast rl.GuiControlProperty.BORDER_COLOR_DISABLED, None)
    }
    
    show_tree_info: bool = true
    show_materials: bool
    quality_render_is_open: bool
    fast_render_is_open: bool = true
    
    quality_render: Render
    fast_render:    Render
    init_render(&quality_render, 64, 16, window_size, 2 when SpallDisabled else 8, core_count, "quality render")
    init_render(&fast_render,     8,  4, window_size, 6 when SpallDisabled else 12, core_count, "fast render")
    defer close_work_queue_and_wait_for_threads(&quality_render.queue)
    defer close_work_queue_and_wait_for_threads(&fast_render.queue)
    
    renders := make_dynamic_array(context.allocator, [dynamic] ^Render, 0, 2)
    append(&renders, &quality_render)
    append(&renders, &fast_render)
    
    ////////////////////////////////////////////////
    
    render_display_progress := false
    
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
        dddp: v3
        dlook: v2
        
        if !rl.IsWindowFocused() {
            mouse_is_look = false
            rl.ShowCursor()
        } else {
            
            if rl.IsKeyDown(.A) do dddp += {-1, 0,  0}
            if rl.IsKeyDown(.D) do dddp += { 1, 0,  0}
            if rl.IsKeyDown(.W) do dddp += { 0, 0, -1}
            if rl.IsKeyDown(.S) do dddp += { 0, 0,  1}
            
            if rl.IsKeyDown(.SPACE)      do dddp += {0, 1,  0}
            if rl.IsKeyDown(.LEFT_SHIFT) do dddp += {0,-1,  0}
            
            if !rl.IsMouseButtonDown(.RIGHT) {
                ddp *= 0.1
            }
            
            if rl.IsMouseButtonPressed(.MIDDLE) {
                mouse_is_look = !mouse_is_look
            }
            
            if mouse_is_look {
                dlook = -rl.GetMouseDelta()
            }
            
            if mouse_is_look {
                rl.HideCursor()
                rl.SetMousePosition(window_size.x / 2, window_size.y / 2)
            } else do rl.ShowCursor()
            
            if rl.IsKeyPressed(.Q) do Use_Tree = !Use_Tree
            
            if rl.IsKeyPressed(.R) {
                fast_render.requested = true
            }
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
                    render.requested = false
                    
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
            img.write_bmp(ctprint("%", output_path), quality_render.image.width, quality_render.image.height, 4, &quality_render.image.data[0])
            cwd, _ := os.get_working_directory(context.temp_allocator)
            print("Wrote ouput to %/%\n", cwd, output_path)
        }
        
        ////////////////////////////////////////////////
        
        _layout: Layout
        layout := &_layout
        layout_init(layout, font, Jasmine, 10)
        
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
        
        display_line(layout, "Camera: % : % ", camera.p, camera.z)
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
        
        layout_begin_horizontal(layout)
            if display_slider(layout, 100, &Triangle_Threshold, 10, 10000, "Triangle Threshold", flags = { .logarithmic }) {
                fast_render.requested = true
            }
            layout_advance(layout, 10)
            display_line(layout, "%", view_magnitude(cast(u32) Triangle_Threshold, precision = 1))
        layout_end_horizontal(layout)
        layout_advance(layout, 10)
        layout_begin_horizontal(layout)
            if display_slider(layout, 100, &Rectangle_Threshold, 10, 10000, "Rectangle Threshold", flags = { .logarithmic }) {
                fast_render.requested = true
            }
            layout_advance(layout, 10)
            display_line(layout, "%", view_magnitude(cast(u32) Rectangle_Threshold, precision = 1))
        layout_end_horizontal(layout)
        layout_advance(layout, 10)
        
        layout_begin_horizontal(layout)
            display_toggle(layout, "Display Progress", &render_display_progress)
            layout_advance(layout, 10)
            display_toggle(layout, "Use Tree", &Use_Tree)
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
        
        if display_list(layout, &show_tree_info, "Tree") {
            layout_indent(layout)
            
            display_line(layout, "build took %", fmt.tprint(build_time))
            display_line(layout, "node count %", inspection.node_count)
            display_line(layout, "depth: max = %, avg = %", inspection.depth.max, view_float(inspection.depth.avg, precision = 2))
            display_line(layout, "values per node: max = %, avg = %", inspection.values_per_node.max, view_float(inspection.values_per_node.avg, precision = 2))
            layout_advance(layout, 10)
            
            if display_button(layout, "Rebuild") {
                start = time.now()
                tree_build(&teapot.tree, teapot.triangles)
                build_time = time.since(start)
                print("building tree took %\n", fmt.tprint(build_time))
                inspection = inspect(teapot.tree)
                
                fast_render.requested = true
            }
            
            layout_unindent(layout)
        }
        
        layout_advance(layout, FontSize)
        if display_list(layout, &show_materials, "Materials") {
            layout_indent(layout)
            defer layout_unindent(layout)
            
            for &material, index in world.materials {
                display_line(layout, "Material %: material %", index, material_names[index])
                
                layout_indent(layout)
                defer layout_unindent(layout)
                
                if display_slider(layout, 240, &material.scatter,  0,   1, "Scatter") do fast_render.requested = true
                if display_slider(layout, 240, &material.emit_factor, 1, 1000, "Emittance", flags = {.logarithmic}) do fast_render.requested = true
                
                layout_advance(layout, 10)
                layout_begin_horizontal(layout)
                color_size :: 50
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
                    layout_advance(layout, 50)
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
                layout_advance(layout, 50)
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
        layout_end_horizontal(layout)
        
        layout_begin_horizontal(layout)
            if display_button(layout, "-") do render.rays_per_pixel /= 2 
            layout_advance(layout, 5)
            if display_button(layout, "+") do render.rays_per_pixel *= 2
            layout_advance(layout, 5)
            display_line(layout, "rays per_pixel %", render.rays_per_pixel)
            render.rays_per_pixel = clamp(render.rays_per_pixel, LaneWidth, 2048)
        layout_end_horizontal(layout)
        
        layout_begin_horizontal(layout)
            if display_button(layout, "-") do render.max_bounce_count -= render.max_bounce_count <= 8 ? 1 : 2
            layout_advance(layout, 5)
            if display_button(layout, "+") do render.max_bounce_count += render.max_bounce_count  < 8 ? 1 : 2
            render.max_bounce_count = clamp(render.max_bounce_count, 1, 16)
            layout_advance(layout, 5)
            display_line(layout, "bounces %", render.max_bounce_count)
        layout_end_horizontal(layout)
            
        if !render.active {
            layout_begin_horizontal(layout)
                before := render.image_size_factor
                if display_button(layout, "-") do render.image_size_factor -= 1
                layout_advance(layout, 5)
                if display_button(layout, "+") do render.image_size_factor += 1
                render.image_size_factor = clamp(render.image_size_factor, 1, 32)
                
                if render.image_size_factor != before {
                    init_render_image(render, window_size)
                }
                layout_advance(layout, 5)
                display_line(layout, "size factor %", render.image_size_factor)
            layout_end_horizontal(layout)
        } else {
            layout_advance(layout, FontSize)
        }
        
        layout_begin_horizontal(layout)
            end := render.active ? time.now() : render.end
            display_line(layout, "Render took: %", view_time_duration(time.diff(render.start, end), precision = 2))
            
            if render.active && !work_is_completed(&render.queue){
                total_pixels := render.image.width * render.image.height
                done_percentage := cast(f32) render.stats.pixels_done / cast(f32) total_pixels
                
                layout_advance(layout, 10)
                bar_p := layout.at
                bar_width  :: 200
                bar_height := cast(f32) FontSize * 0.8
                
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

rlGuiSetColor :: proc (control: rl.GuiControl, property: i32, value: Color) {
    rl.GuiSetStyle(control, property, transmute(i32) value.abgr)
}

to_rl_rect :: proc (rect: Rectangle2) -> rl.Rectangle {
    result: rl.Rectangle
    
    result.x = rect.min.x
    result.y = rect.min.y
    result.width  = rectangle_get_dimension(rect).x
    result.height = rectangle_get_dimension(rect).y
    
    return result
}