package main

import os "core:os/os2"
import os_old "core:os"
import "core:time"
import "core:math"

import img "vendor:stb/image"
import rl "vendor:raylib"

FontSize :: 20

Use_Tree := true

////////////////////////////////////////////////

Is_Optimized :: ODIN_OPTIMIZATION_MODE == .Speed


main :: proc() {
    rl.SetTraceLogLevel(.WARNING)
    
    init_spall()
    
    core_count := cast(i32) os_old.processor_core_count() - 1
    
    world: World
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
    
    if false {
        area_size := cast(f32) 20
        append(&world.spheres, Sphere { center = { 0, 0, 0},   radius = 1,  material = 2 })
        append(&world.spheres, Sphere { center = { 3,-2, 0.4}, radius = .1, material = 3 })
        append(&world.spheres, Sphere { center = {-2,-1, 2},   radius = 1,  material = 1 })
        append(&world.spheres, Sphere { center = { 1,-1, 3},   radius = 1,  material = 5 })
        append(&world.spheres, Sphere { center = {-2, 3, 0},   radius = 2,  material = 6 })
    
        gen_entropy := seed_random_series(565)
        if false do for _ in 0..< square(area_size) * 1.2 {
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
    
        append(&world.planes, Plane { normal = { 0, 0, 1}, tangent = {}, binormal = {}, center = { 0, 0, 0},             radius = +Infinity,   material = 6 })
        append(&world.planes, Plane { normal = { 0, 0,-1}, tangent = {}, binormal = {}, center = { 0, 0, area_size-0.1}, radius = area_size/5, material = 3 })
        // append(&world.planes, Plane { normal = { 0, 0,-1}, tangent = {}, binormal = {}, center = { 0, 0, area_size},     radius = area_size,   material = 6 })
        // append(&world.planes, Plane { normal = { 1, 0, 0}, tangent = {}, binormal = {}, center = {-area_size, 0, 0},     radius = area_size,   material = 2 })
        // append(&world.planes, Plane { normal = {-1, 0, 0}, tangent = {}, binormal = {}, center = {+area_size, 0, 0},     radius = area_size,   material = 2 })
        // append(&world.planes, Plane { normal = { 0,-1, 0}, tangent = {}, binormal = {}, center = {0, +area_size, 0},     radius = area_size,   material = 4 })
    } else {
        area_size := cast(f32) 5
        append(&world.planes, Plane { normal = { 0, 0, 1}, tangent = {}, binormal = {}, center = { 0, 0, 0},             radius = +Infinity,   material = 6 })
        append(&world.planes, Plane { normal = { 0, 0,-1}, tangent = {}, binormal = {}, center = { 0, 0, area_size-0.1}, radius = area_size/5, material = 3 })
        
        // append(&world.planes, Plane { normal = { 0, 0,-1}, tangent = {}, binormal = {}, center = { 0, 0, area_size},     radius = area_size,   material = 6 })
        // append(&world.planes, Plane { normal = { 1, 0, 0}, tangent = {}, binormal = {}, center = {-area_size, 0, 0},     radius = area_size,   material = 1 })
        // append(&world.planes, Plane { normal = {-1, 0, 0}, tangent = {}, binormal = {}, center = {+area_size, 0, 0},     radius = area_size,   material = 5 })
        // append(&world.planes, Plane { normal = { 0,-1, 0}, tangent = {}, binormal = {}, center = {0, +area_size, 0},     radius = area_size,   material = 4 })
        
        load_teapot(&world.triangles, 0, 2)
    }
    
    ////////////////////////////////////////////////
    
    reserve(&world.sphere_nodes, len(world.spheres))
    sphere_info := tree_init(&world.sphere_nodes, 1, rectangle_center_dimension(v3{0, 0, 0}, 256))
    
    // @speed Currently the octtree is a ~79% less work compared to the straight array
    // @note(viktor): skip nil sphere
    for sphere in world.spheres[1:] {
        bounds := rectangle_center_dimension(sphere.center, sphere.radius)
        tree_append(&sphere_info, &world.sphere_nodes, sphere, bounds)
    }
    
    // @todo(viktor): think about the layout of nodes and values
    // currently we append nil, root,
    // then each value + new nodes if needed, 
    // then the next value ...
    reserve(&world.triangle_nodes, len(world.triangles))
    triangle_info := tree_init(&world.triangle_nodes, 1, rectangle_center_dimension(v3{}, 128))
    
    // @note(viktor): skip nil triangle
    for triangle in world.triangles[1:] {
        bounds := rectangle_inverted_infinity(Rectangle3)
        bounds = rectangle_union_point(bounds, triangle.a)
        bounds = rectangle_union_point(bounds, triangle.b)
        bounds = rectangle_union_point(bounds, triangle.c)
        
        tree_append(&triangle_info, &world.triangle_nodes, triangle, bounds)
    }
    
    {
        compacted: Stat(f32)
        
        nodes := world.triangle_nodes
        backing: [1024] Node_Index
        stack := dynamic_array_from_parts(Node_Index, raw_data(&backing), 0, len(backing))
        append(&stack, Root_Index)
        for len(stack) != 0 {
            it_index := pop(&stack)
            assert(it_index != Nil_Index)
            it := nodes[it_index]
            if it.node.first_subnode != Nil_Index {
                append(&stack, it.node.first_subnode+0)
                append(&stack, it.node.first_subnode+1)
            }
            
            if it.node.first_value != Nil_Index {
                bounds := rectangle_inverted_infinity(Rectangle3)
                for link := it.node.first_value; link != Nil_Index; link = nodes[link].value.next_value {
                    value := nodes[link].value
                    bounds = rectangle_union_point(bounds, value.value.a)
                    bounds = rectangle_union_point(bounds, value.value.b)
                    bounds = rectangle_union_point(bounds, value.value.c)
                }
                
                if it.node.bounds != bounds {
                    stat_update(&compacted, rectangle_clamped_area(bounds) / rectangle_clamped_area(it.node.bounds))
                    it.node.bounds = bounds
                }
            } else {
                it.node.bounds = {}
            }
        }
        
        stat_finalize(&compacted)
        print("compacting nodes: average size afterwards = % %%\n", view_percentage_ratio(compacted.avg))
    }
    
    inspection := inspect(triangle_info, world.triangle_nodes[:], Root_Index)
    print("triangle tree info:\n")
    print("            nodes: %\n", inspection.node_count)
    print("            depth: max = %, avg = %\n", inspection.depth.max, view_float(inspection.depth.avg, precision = 2))
    print("  values per node: max = %, avg = %\n", inspection.values_per_node.max, view_float(inspection.values_per_node.avg, precision = 2))
    print("  values per node = %\n", triangle_info.values_per_node)
    print("          density = % %%\n", 100 * cast(f64) inspection.values_per_node.sum / cast(f64) (inspection.node_count + inspection.values_per_node.sum))
    print("     overfullness = % %%\n", 100 * cast(f64) inspection.overfull_nodes / cast(f64) (inspection.node_count))
    print("\n")

    // print_node(world.triangle_nodes[:], 0, Root_Index)
    
    ////////////////////////////////////////////////
    
    camera: Camera
    if !false {
        camera.p = {0, -7, 2.149546}
        camera.z = {-0.064219, -0.991897, 0.109620}
    } else {
        camera.p = {0, -7, 1}
        camera.z = normalize_or_zero(camera.p)
    }
    camera.x = normalize_or_zero(cross(v3{0, 0, 1}, camera.z))
    camera.y = normalize_or_zero(cross(camera.z, camera.x))
    
    ////////////////////////////////////////////////
        
    window_size := v2i { 1920, 1080 }
    
    rl.InitWindow(window_size.x, window_size.y, ctprint("Handmade Ray %", (Is_Optimized ? "Optimized" :  "Debug")))
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
    
    show_materials: bool
    show_planes: bool
    show_spheres: bool
    
    
    quality_render: Render
    fast_render:    Render
    init_render(&quality_render, 64, 16, window_size, 2 when SpallDisabled else 8, core_count)
    init_render(&fast_render,     8,  4, window_size, 6 when SpallDisabled else 30, core_count)
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
        if !rl.IsMouseButtonDown(.RIGHT) {
            ddp *= 0.1
        }
        
        if rl.IsKeyPressed(.Q) do Use_Tree = !Use_Tree
        
        dddp: v3
        if rl.IsKeyDown(.A) do dddp += {-1, 0,  0}
        if rl.IsKeyDown(.D) do dddp += { 1, 0,  0}
        if rl.IsKeyDown(.W) do dddp += { 0, 0, -1}
        if rl.IsKeyDown(.S) do dddp += { 0, 0,  1}
        
        if rl.IsKeyDown(.SPACE)      do dddp += {0, 1,  0}
        if rl.IsKeyDown(.LEFT_SHIFT) do dddp += {0,-1,  0}
        
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
        
        if rl.IsKeyPressed(.R) {
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
                    print_render_results(&render.world, render.start, render.end)
                    
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
            display_toggle(layout, "Display Progress", &render_display_progress)
            layout_advance(layout, 10)
            display_toggle(layout, "Use Tree", &Use_Tree)
        layout_end_horizontal(layout)
        
        xx := !fast_image_is_focussed
        display_render(layout, &quality_render, "Quality", &xx, window_size)
        fast_image_is_focussed = !xx
        display_render(layout, &fast_render, "Fast", &fast_image_is_focussed, window_size)
        layout_advance(layout, 10)
        
        // @todo(viktor): Rebuild the octtree if the spheres are edited in any way
        layout_advance(layout, FontSize)
        if display_list(layout, &show_spheres, "Spheres") {
            layout_indent(layout)
            defer layout_unindent(layout)
            
            for &sphere, index in world.spheres[1:] {
                material := cast(f32) sphere.material
                display_line(layout, "Sphere %: %", index, material_names[sphere.material])
                
                layout_indent(layout)
                defer layout_unindent(layout)
                
                display_slider(layout, 360, &material, 0, cast(f32) len(material_names)-0.51, "Material Index")
                if sphere.material != round(u32, material) do fast_render.requested = true
                sphere.material = round(u32, material)
                if display_slider  (layout, 240, &sphere.radius, 0.001, 10, "Radius")                      do fast_render.requested = true
                if display_slider_v(layout, 240, &sphere.center, -10, 10, "Center", flags = { .relative }) do fast_render.requested = true
                
                layout_advance(layout, 10)
            }
        }
        
        layout_advance(layout, FontSize)
        if display_list(layout, &show_planes, "Planes") {
            layout_indent(layout)
            defer layout_unindent(layout)
            
            for &plane, index in world.planes[1:] {
                material := cast(f32) plane.material
                display_line(layout, "Plane %: %", index, material_names[plane.material])
                
                layout_indent(layout)
                defer layout_unindent(layout)
                
                display_slider(layout, 360, &material, 0, cast(f32) len(material_names)-0.51, "Material Index")
                if plane.material != round(u32, material) do fast_render.requested = true
                plane.material = round(u32, material)
                
                if display_slider  (layout, 240, &plane.radius, 0.1, 1000, "Radius", flags = { .logarithmic }) do fast_render.requested = true
                if display_slider_v(layout, 240, &plane.center, -10, 10,   "Center", flags = { .relative })    do fast_render.requested = true
                
                layout_advance(layout, 10)
            }
        }
        
        layout_advance(layout, FontSize)
        if display_list(layout, &show_materials, "Materials") {
            layout_indent(layout)
            defer layout_unindent(layout)
            
            for &material, index in world.materials {
                if index == 0 do continue
                display_line(layout, "Material %: material %", index, material_names[index])
                
                layout_indent(layout)
                defer layout_unindent(layout)
                
                if display_slider(layout, 240, &material.scatter, 0, 1, "Scatter")  do fast_render.requested = true
                
                layout_advance(layout, 10)
                layout_begin_horizontal(layout)
                color_size :: 50
                {
                    display_line(layout, "Emit")
                    layout_advance(layout, 10)
                    
                    // @todo(viktor): emittance could be larger than 1
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
                layout_advance(layout, 10)
            }
        }
        
        rl.EndDrawing()
    }
}

////////////////////////////////////////////////

display_render :: proc (layout: ^Layout, render: ^Render, name: string, focus: ^bool, window_size: v2i) { 
    display_line(layout, name)
    
    layout_indent(layout)
    defer layout_unindent(layout)
    
    layout_begin_horizontal(layout)
        display_toggle(layout, "Render", &render.requested)
        layout_advance(layout, 5)
        condition := focus^
        display_toggle(layout, "Focus", &condition)
        focus^ ||= condition
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
    }
    
    layout_begin_horizontal(layout)
        end := render.active ? time.now() : render.end
        display_line(layout, "Render took: %", view_time_duration(time.diff(render.start, end), precision = 2))
        
        if render.active && !work_is_completed(&render.queue){
            total_pixels := render.image.width * render.image.height
            done_percentage := cast(f32) render.world.pixels_done / cast(f32) total_pixels
            
            layout_advance(layout, 10)
            bar_p := layout.at
            bar_width  :: 300
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