package main

import os_old "core:os"
import "core:time"

Color :: [4] u8

Image:: struct {
    data:   [] Color,
    width:  i32,
    height: i32,
}

#assert(Todo, "inline sphere and triangle into node, no double indexing")
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
    
    rays_per_pixel:   u32,
    max_bounce_count: u32,
}

Camera :: struct {
    x, y, z: v3,
    p:       v3,
}

Sphere_Node :: struct {
    using base:   Oct_Node,
    sphere_index: u32,
}

Triangle_Node :: struct {
    using base:     Oct_Node,
    triangle_index: u32,
}

////////////////////////////////////////////////

do_one_render :: proc (render_allocator: Allocator, image: Image, core_count: i32, world: ^World, camera: Camera, work_queue: ^WorkQueue, create_infos: [] CreateThreadInfo) {
    init_work_queue(work_queue, create_infos[:])

    start := enqueue_render_work(render_allocator, image, core_count, world, camera, work_queue)
    end := wait_for_one_render_to_end(image, world, work_queue)
    
    close_work_queue_and_wait_for_threads(work_queue)
    
    print_render_results(world, start, end)
}

enqueue_render_work :: proc (render_allocator: Allocator, image: Image, core_count: i32, world: ^World, camera: Camera, work_queue: ^WorkQueue) -> time.Time {
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
    
    works := make_slice(render_allocator, [] Work, tile_count)
    work_index: u32
    
    start := time.now()
    for row in 0..<tile_rows {
        for col in 0..<tile_cols {
            rect := rectangle_min_dimension(tile_size * {col, row}, tile_size)
            rect  = get_intersection(rect, rectangle_min_dimension(i32(0), 0, image.width, image.height))
            
            entropy := seed_random_series(1842098778 + row * 984612097 + col * 237711 + cast(i32) work_index)
            
            work := &works[work_index]
            work_index += 1
            work ^= { world, camera, image, rect, entropy }
            
            enqueue_work_or_do_immediatly(work_queue, proc(work: ^Work) {
                render_tile(work.world, work.camera, work.image, work.rect, &work.entropy)
            }, work)
        }
    }
    return start
}

wait_for_one_render_to_end :: proc (image: Image, world: ^World, work_queue: ^WorkQueue) -> time.Time {
    {
        total_pixels := image.width * image.height
        for work_queue.completion_count != work_queue.completion_goal {
            print_to_console("                                 \r % %% done", view_percentage_ratio(cast(f32) world.pixels_done / cast(f32) (total_pixels)), console = os_old.stderr)
        }
        print_to_console("\n", console = os_old.stderr)
    }
    complete_all_work(work_queue)
    end := time.now()
    
    return end
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
    view_magnitude(wasted_bounces), view_percentage_ratio(cast(f32) wasted_bounces / cast(f32) loops_computed), 
    cast(time.Duration) nanoseconds)
}
