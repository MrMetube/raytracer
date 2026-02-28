package main

import "core:time"

Color :: [4] u8

Image:: struct {
    data:   [] Color,
    width:  i32,
    height: i32,
}

// @volatile also update the render's world copying
World :: struct {
    sphere_nodes:   [dynamic] Sphere_Node,
    triangle_nodes: [dynamic] Triangle_Node,
    
    spheres:   [dynamic] Sphere,
    triangles: [dynamic] Triangle,
    planes:    [dynamic] Plane,
    materials: [dynamic] Material,
    all_brdf_values: [dynamic] v3,
    
    bounces_computed: u64,
    loops_computed:   u64,
    tiles_retired:    u32,
    pixels_done:      u32,
    nil_value_lanes_tested: [9] u32,
    
    rays_per_pixel:   u32,
    max_bounce_count: u32,
}

Camera :: struct {
    x, y, z: v3,
    p:       v3,
}

Sphere_Node :: struct {
    using base: Oct_Node,
    value:      Sphere,
}

Triangle_Node :: struct {
    using base: Oct_Node,
    value:      Triangle,
}

////////////////////////////////////////////////

begin_render :: proc (render: ^Render, core_count: i32, camera: Camera) {
    image := render.image
    tile_size: v2i = image.width / core_count
    
    tile_cols  := (image.width  + tile_size.x - 1) / tile_size.x
    tile_rows  := (image.height + tile_size.y - 1) / tile_size.y
    tile_count := tile_cols * tile_rows
    
    // print("Configuration: %x% with % cores and % %x% (%/tile) tiles and lane width of % \n", image.width, image.height, core_count, tile_count, tile_size.x, tile_size.y, view_memory_size(tile_size.x * tile_size.y * size_of(Color)), LaneWidth)
    // print("Quality: % rays per pixel with a maximum of % bounces\n", world.rays_per_pixel, world.max_bounce_count)
    
    Work :: struct {
        world:   ^World,
        camera:  Camera,
        image:   Image, 
        rect:    Rectangle2i, 
        entropy: RandomSeries,
    }
    
    works := make_slice(render.allocator, [] Work, tile_count)
    work_index: u32
    
    render.start = time.now()
    for row in 0..<tile_rows {
        for col in 0..<tile_cols {
            rect := rectangle_min_dimension(tile_size * {col, row}, tile_size)
            rect  = get_intersection(rect, rectangle_min_dimension(i32(0), 0, image.width, image.height))
            
            entropy := seed_random_series(1842098778 + row * 984612097 + col * 237711 + cast(i32) work_index)
            
            work := &works[work_index]
            work_index += 1
            work ^= { &render.world, camera, image, rect, entropy }
            
            enqueue_work_or_do_immediatly(&render.queue, proc(work: ^Work) {
                render_tile(work.world, work.camera, work.image, work.rect, &work.entropy)
            }, work)
        }
    }
}

print_render_results :: proc (world: ^World, start, end: time.Time) {
    total_time := time.diff(start, end)
    bounces_computed := volatile_load(&world.bounces_computed)
    loops_computed   := volatile_load(&world.loops_computed)
    wasted_bounces   := loops_computed - bounces_computed
    nanoseconds := time.duration_nanoseconds(total_time) / cast(i64) bounces_computed
    print("Raycasting time: %s\n  bounces %\n  total bounces %\n  wasted bounces % (% %%)\n  time per ray %\n", 
        time.duration_seconds(total_time), 
        view_magnitude(bounces_computed), 
        view_magnitude(loops_computed), 
        view_magnitude(wasted_bounces), 
        view_percentage_ratio(cast(f32) wasted_bounces / cast(f32) loops_computed), 
        cast(time.Duration) nanoseconds
    )
    
    total_lanes: u32
    wasted: u32
    for e, i in world.nil_value_lanes_tested {
        total_lanes += e
        wasted += e * cast(u32) i
    }
    
    print("Lane utilization for hit tests:\n")
    print("  [")
    for e, i in world.nil_value_lanes_tested {
        if i > 0 do print(", ")
        print("% = % %%", i, view_percentage_ratio(cast(f64) e / cast(f64) total_lanes))
    }
    print("]\n")
    print("  Wasted lanes: % % %%\n", view_magnitude(wasted), view_percentage_ratio(cast(f64) wasted / cast(f64) (total_lanes * 8)))
}
