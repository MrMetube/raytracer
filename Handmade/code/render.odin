#+vet explicit-allocators
package main

import "core:time"
import "core:mem"
import rl "vendor:raylib"

Render_Stats :: struct {
    bounces_computed: u64,
    loops_computed:   u64,
    tiles_retired:    u32,
    pixels_done:      u32,
    
    using tests: Test_Info,
}

Render :: struct {
    normals:   [] [] Triangle_Normals,
    models:    [] Model,
    materials: [] Material,
    brdf_data: [] v3,
    
    ////////////////////////////////////////////////
    
    requested: bool,
    canceled:  bool,
    active:    bool,
    
    start, end: time.Time,
    
    image:   Image,
    texture: rl.Texture,
    queue:   WorkQueue,
    
    arena:     mem.Arena,
    allocator: Allocator,
    
    rays_per_pixel:   u32,
    max_bounce_count: u32,
    
    image_size_factor: i32,
    
    stats: Render_Stats,
}

Triangle_Normals :: struct {
    normal, tangent, binormal: v3,
}

Model :: struct {
    // @note(viktor): triangles is used outside the render, ray_triangles is used inside
    triangles:     [] Triangle,
    ray_triangles: [] Ray_Triangle,
    tree:          [] Tree_Node,
    translation: v3,
    material:    u32,
}

Color :: [4] u8

Image :: struct {
    data:   [] Color,
    width:  i32,
    height: i32,
}

Camera :: struct {
    x: v3,
    y: v3,
    z: v3,
    p: v3,
}

Material :: struct {
    emit:    v3,
    reflect: v3,
    emit_factor: f32,
    scatter: f32, // 0 = mirror like, 1 = chalk like
    
    brdf: BrdfTable,
}

BrdfTable :: struct {
    count: [3] u32,
    // @note(viktor): a view into the render.brdf_data array
    values_index: u32,
    values_count: u32,
}

////////////////////////////////////////////////

init_render :: proc (render: ^Render, rays_per_pixel: u32, max_bounce_count: u32, window_size: v2i, image_size_factor: i32, thread_count: u32, name: string) {
    render.rays_per_pixel    = rays_per_pixel
    render.max_bounce_count  = max_bounce_count
    render.image_size_factor = image_size_factor
    
    backing, err := make([] u8, 1 * Gigabyte, context.allocator); assert(err == nil)
    mem.arena_init(&render.arena, backing)
    render.allocator = mem.arena_allocator(&render.arena)
    
    init_render_image(render, window_size)
    
    init_work_queue(&render.queue, name, thread_count)
}

init_render_image :: proc (render: ^Render, window_size: v2i) {
    assert(!render.active)
    
    delete(render.image.data, context.allocator)
    
    image_size := window_size / render.image_size_factor
    render.image.width  = image_size.x
    render.image.height = image_size.y
    render.image.data   = make([] Color, render.image.width * render.image.height, context.allocator)
}

begin_render :: proc (render: ^Render, world: ^World, core_count: u32, camera: Camera) {
    free_all(render.allocator)
    
    render.active = true
    render.canceled = false
    render.requested = false
    
    render.stats = {}
    
    render.models = make([] Model, len(world.models), render.allocator)
    render.normals = make([] [] Triangle_Normals, len(world.models), render.allocator)
    for model, model_index in world.models {
        render_model := &render.models[model_index]
        render_model^ = model
        
        render_model.ray_triangles = make([] Ray_Triangle, len(model.triangles), render.allocator)
        for &it, it_index in render_model.ray_triangles {
            triangle := model.triangles[it_index]
            it.a  = triangle.a
            it.ab = triangle.b - triangle.a
            it.ac = triangle.c - triangle.a
        }
        render_model.tree      = make_shallow_copy(model.tree, render.allocator)
        
        render_normals := &render.normals[model_index]
        render_normals^ = make([] Triangle_Normals, len(model.triangles), render.allocator)
        for &it, it_index in render_normals {
            triangle := model.triangles[it_index]
            // @todo(viktor): interpolate the vertex normals
            // @note(viktor): Assuming counter-clockwise winding order
            ab := triangle.b - triangle.a
            ac := triangle.c - triangle.a
            it.normal   = normalize_or_zero(cross(ab, ac))
            it.tangent  = normalize_or_zero(ab)
            it.binormal = normalize_or_zero(cross(it.normal, it.tangent))
        }
    }
    
    render.brdf_data = world.brdf_data[:]
    render.materials = make_shallow_copy(world.materials[:], render.allocator)
    
    // @todo(viktor): make a copy per thread of the image data, so that it cannot be "false shared"
    zero_slice(render.image.data)
    
    tile_size := cast(v2i) max(render.image.width, render.image.height) / cast(i32) core_count
    tile_cols  := (render.image.width  + tile_size.x - 1) / tile_size.x
    tile_rows  := (render.image.height + tile_size.y - 1) / tile_size.y
    tile_count := tile_cols * tile_rows
    
    Work :: struct {
        render: ^Render,
        camera:  Camera,
        rect:    Rectangle2i, 
        entropy: RandomSeries,
    }
    
    works := make([] Work, tile_count, render.allocator)
    work_index: u32
    
    render.start = time.now()
    for row in 0..<tile_rows {
        for col in 0..<tile_cols {
            rect := rectangle_min_dimension(tile_size * {col, row}, tile_size)
            rect  = rectangle_intersection(rect, rectangle_zero_dimension(render.image.width, render.image.height))
            
            entropy := seed_random_series(1842098778 + row * 984612097 + col * 237711 + cast(i32) work_index)
            
            work := &works[work_index]
            work_index += 1
            work ^= { render, camera, rect, entropy }
            
            enqueue_work_or_do_immediatly(&render.queue, proc(work: ^Work) {
                render_tile(work.render, work.camera, work.rect, &work.entropy)
            }, work)
        }
    }
}

print_render_results :: proc (stats: ^Render_Stats, start, end: time.Time) {
    total_time := time.diff(start, end)
    
    print("\n")
    
    bounces_computed := volatile_load(&stats.bounces_computed)
    loops_computed   := volatile_load(&stats.loops_computed)
    wasted_bounces   := loops_computed - bounces_computed
    time_per_ray := safe_ratio_or_zero(cast(i64) total_time, cast(i64) bounces_computed)
    time_per_triangle  := safe_ratio_or_zero(cast(i64) total_time, cast(i64) stats.triangles)
    time_per_rectangle := safe_ratio_or_zero(cast(i64) total_time, cast(i64) stats.rectangles)
    
    print("Raycasting time: %v\n", total_time)
    print("  bounces %v\n", view_magnitude(bounces_computed, 2))
    print("  total bounces %v\n", view_magnitude(loops_computed, 2))
    print("  wasted bounces %v (%v)\n", view_magnitude(wasted_bounces, 2), view_percentage(wasted_bounces, loops_computed))
    print("  time per ray %v\n",       cast(time.Duration) time_per_ray)
    print("  time per triangle %v\n",  cast(time.Duration) time_per_triangle)
    print("  time per rectangle %v\n", cast(time.Duration) time_per_rectangle)
    
    total_lanes: u32
    wasted_lanes: u32
    for count, lanes in stats.empty_lanes {
        total_lanes  += count * LaneWidth
        wasted_lanes += count * cast(u32) lanes
    }
    
    
    total_tests := stats.triangles + stats.rectangles
    
    print("Hit tests:\n")
    print("  total tests = %v\n",      view_magnitude(total_tests))
    print("  triangles   = %v (%v)\n", view_magnitude(stats.triangles),  view_percentage(stats.triangles, total_tests))
    print("  rectangles  = %v (%v)\n", view_magnitude(stats.rectangles), view_percentage(stats.rectangles, total_tests))
    print("  empty lanes: [")
    for e, i in stats.empty_lanes {
        if i > 0 do print(", ")
        print("%v = %v", i, view_percentage(e, total_lanes))
    }
    print("]\n")
    print("  total  lanes = %v\n",    view_magnitude(total_lanes))
    print("  wasted lanes = %v %v\n", view_magnitude(wasted_lanes), view_percentage(wasted_lanes, total_lanes))
    
    print("\n")
}