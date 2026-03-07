package main

import "core:time"
import rl "vendor:raylib"

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
    
    rays_per_pixel:   u32,
    max_bounce_count: u32,
    
    image_size_factor: i32,
}

Color :: [4] u8

Image :: struct {
    data:   [] Color,
    width:  i32,
    height: i32,
}

// @volatile also update the render's world copying
World :: struct {
    triangle_nodes: [dynamic] Tree_Node,
    triangles: [dynamic] Triangle,
    
    planes:    [dynamic] Plane,
    materials: [dynamic] Material,
    all_brdf_values: [dynamic] v3,
    
    using render_stats: struct {
        bounces_computed: u64,
        loops_computed:   u64,
        tiles_retired:    u32,
        pixels_done:      u32,
        nil_value_lanes_tested: [LaneWidth] u32,
        
        // @note(viktor): only sum and count -> avg are valid
        all_triangle_tests, triangle_tests: Stat(u32),
    },
}

Camera :: struct {
    x: v3,
    y: v3,
    z: v3,
    p: v3,
}

////////////////////////////////////////////////

init_render :: proc (render: ^Render, rays_per_pixel: u32, max_bounce_count: u32, window_size: v2i, image_size_factor: i32, core_count: i32) {
    render.rays_per_pixel   = rays_per_pixel
    render.max_bounce_count = max_bounce_count
    render.image_size_factor = image_size_factor
    
    render.allocator = arena_allocator(&render.arena)
    
    init_render_image(render, window_size)
    
    create_infos := make_slice(context.allocator, [] CreateThreadInfo, core_count) // @leak
    init_work_queue(&render.queue, create_infos)
}

init_render_image :: proc (render: ^Render, window_size: v2i) {
    assert(!render.active)
    
    delete(render.image.data, context.allocator)
    
    image_size := window_size / render.image_size_factor
    render.image.width  = image_size.x
    render.image.height = image_size.y
    render.image.data   = make_slice(context.allocator, [] Color, render.image.width * render.image.height)
}

begin_render :: proc (render: ^Render, world: ^World, core_count: i32, camera: Camera) {
    render.active = true
    
    render.world.render_stats = {}
    
    render.world.all_brdf_values = world.all_brdf_values
    
    // @volatile
    make_by_pointer(&render.world.planes,         len(world.planes),         render.allocator)
    make_by_pointer(&render.world.triangles,      len(world.triangles),      render.allocator)
    make_by_pointer(&render.world.triangle_nodes, len(world.triangle_nodes), render.allocator)
    make_by_pointer(&render.world.materials,      len(world.materials),      render.allocator)
    
    copy(render.world.planes[:],         world.planes[:])
    copy(render.world.triangles[:],      world.triangles[:])
    copy(render.world.triangle_nodes[:], world.triangle_nodes[:])
    copy(render.world.materials[:],      world.materials[:])
    
    image := render.image
    zero_slice(image.data)
    tile_size: v2i = max(image.width, image.height) / core_count
    
    tile_cols  := (image.width  + tile_size.x - 1) / tile_size.x
    tile_rows  := (image.height + tile_size.y - 1) / tile_size.y
    tile_count := tile_cols * tile_rows
    
    Work :: struct {
        world:   ^World,
        camera:  Camera,
        image:   Image, 
        rect:    Rectangle2i, 
        entropy: RandomSeries,
        rays_per_pixel:   u32,
        max_bounce_count: u32,
    }
    
    works := make_slice(render.allocator, [] Work, tile_count)
    work_index: u32
    
    render.start = time.now()
    for row in 0..<tile_rows {
        for col in 0..<tile_cols {
            rect := rectangle_min_dimension(tile_size * {col, row}, tile_size)
            rect  = rectangle_intersection(rect, rectangle_min_dimension(i32(0), 0, image.width, image.height))
            
            entropy := seed_random_series(1842098778 + row * 984612097 + col * 237711 + cast(i32) work_index)
            
            work := &works[work_index]
            work_index += 1
            work ^= { &render.world, camera, image, rect, entropy, render.rays_per_pixel, render.max_bounce_count }
            
            enqueue_work_or_do_immediatly(&render.queue, proc(work: ^Work) {
                render_tile(work.world, work.camera, work.image, work.rect, &work.entropy, work.rays_per_pixel, work.max_bounce_count)
            }, work)
        }
    }
}

print_render_results :: proc (world: ^World, start, end: time.Time) {
    total_time := time.diff(start, end)
    bounces_computed := volatile_load(&world.bounces_computed)
    loops_computed   := volatile_load(&world.loops_computed)
    wasted_bounces   := loops_computed - bounces_computed
    nanoseconds := safe_ratio_or_zero(time.duration_nanoseconds(total_time), cast(i64) bounces_computed)
    print("Raycasting time: %s\n  bounces %\n  total bounces %\n  wasted bounces % (% %%)\n  time per ray %\n", 
        time.duration_seconds(total_time), 
        view_magnitude(bounces_computed), 
        view_magnitude(loops_computed), 
        view_magnitude(wasted_bounces), 
        view_percentage_ratio(cast(f32) wasted_bounces / cast(f32) loops_computed), 
        cast(time.Duration) nanoseconds,
    )
    
    total_lanes: u32
    wasted_lanes: u32
    for e, i in world.nil_value_lanes_tested {
        total_lanes += e
        wasted_lanes += e * cast(u32) i
    }
    
    print("Lane utilization for hit tests:\n")
    print("  Empty lanes: [")
    for e, i in world.nil_value_lanes_tested {
        if i > 0 do print(", ")
        print("% = % %%", i, view_percentage_ratio(safe_ratio_or_zero(cast(f64) e, cast(f64) total_lanes)))
    }
    print("]\n")
    
    print("  Wasted lanes: % % %%\n", view_magnitude(wasted_lanes), view_percentage_ratio(safe_ratio_or_zero(cast(f64) wasted_lanes, cast(f64) (total_lanes * LaneWidth))))
    
    {
        tests := &world.triangle_tests
        total := &world.all_triangle_tests
        stat_finalize(tests)
        stat_finalize(total)
        wasted := total.sum - tests.sum
        
        print("Triangle tests:\n")
        print("     tests = % (avg ~%)\n", view_magnitude(tests.sum), view_float(tests.avg, precision = 2))
        print(" all lanes = % (avg ~%)\n", view_magnitude(total.sum), view_float(total.avg, precision = 2))
        print("    wasted = % % %%\n", view_magnitude(wasted), view_percentage(wasted, total.sum))
    }
    
    print("\n\n")
}
