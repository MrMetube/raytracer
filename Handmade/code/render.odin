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

// @waste only use the render data structure if possible(skip lane_xx for now)
Render :: struct {
    triangles: [] Ray_Triangle,
    normals:   [] Normals,
    trees:     [] Tree_Node,
    models:    [] RenderModel,
    materials: [] Material,
    brdf_data: [] v3,
    
    ////////////////////////////////////////////////
    
    draw_camera: Camera,
    draw_models: [dynamic] Draw_Model,
    
    ////////////////////////////////////////////////
    
    requested: bool,
    canceled:  bool,
    active:    bool,
    display_progress: bool,
    
    start, end: time.Time,
    render_time: Stat(time.Duration),
    
    image:   Image,
    texture: rl.Texture,
    queue:   WorkQueue,
    thread_count: i32,
    
    arena:     mem.Arena,
    allocator: Allocator,
    
    rays_per_pixel:   u32,
    max_bounce_count: u32,
    
    image_size_factor: i32,
    
    stats: Render_Stats,
}

Normals :: [3] v3

Model :: struct {
    triangles: [] Triangle,
    normals:   [] Normals,
    tree:      Tree,
}

Draw_Model :: struct {
    using m: Model,
    transform: Transform,
    material:  u32,
}

RenderModel :: struct {
    triangle_offset: u32,
    triangle_count:  u32,
    tree_offset: u32,
    tree_count:  u32,
    
    material:  u32,
    
    forward: Transform,
    inverse: Transform,
    lane_inverse: lane_Transform,
}

Color :: [4] u8

Image :: struct {
    data:   [] Color,
    width:  i32,
    height: i32,
}

// @todo(viktor): see if #soa [LaneWidth] struct is equivalent
Transform :: struct {
    x: v3,
    y: v3,
    z: v3,
    t: v3,
}
lane_Transform :: struct {
    x: lane_v3,
    y: lane_v3,
    z: lane_v3,
    t: lane_v3,
}

Camera :: distinct Transform

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

// end_render :: proc () {
//     for model in active_models {
//         collect triangles normals and trees
//         // rebuild dirty trees
//     }
    
//     build tree of models
//     assign work to threads
// }

Model_Index :: distinct u32
Models: [256] Model
last_used_model_index: Model_Index

begin_model :: proc () -> (^Model, Model_Index) {
    last_used_model_index += 1
    result := &Models[last_used_model_index]
    
    return result, last_used_model_index
}

end_model :: proc (model: ^Model, triangles: [] Triangle, normals: [] Normals) {
    model.triangles = make_shallow_copy(triangles, context.allocator)
    model.normals   = make_shallow_copy(normals,   context.allocator)
    tree_build(&model.tree, model.triangles, model.normals)
}

////////////////////////////////////////////////

render_begin :: proc (render: ^Render) {}

draw_model :: proc (render: ^Render, model: Model_Index, material: u32, transform: Transform) {
    // @todo(viktor): is this okay?
    if !render.requested || render.active do return
    
    if model == 0 do return
    append(&render.draw_models, Draw_Model{ Models[model], transform, material })
}

set_camera :: proc (render: ^Render, camera: Camera) {
    // @todo(viktor): is this okay?
    if !render.requested || render.active do return
    render.draw_camera = camera
}

render_end :: proc (render: ^Render, brdf_data: [] v3, materials: [] Material) {
    if !render.active {
        if render.requested {
            render_start(render, render.draw_camera, render.draw_models[:], brdf_data, materials)
            clear(&render.draw_models)
        }
    } else {
        reload := false
        if work_is_completed(&render.queue) {
            reload = true
            
            render.active = false
            render.end = time.now()
            stat_update(&render.render_time, time.diff(render.start, render.end))
            stat_finalize(&render.render_time)
            print_render_results(&render.stats, render.start, render.end)
            
            free_all(render.allocator)
        }
        
        if reload || render.display_progress {
            load_image_into_texture(&render.texture, render.image)
        }
    }
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
    
    render.thread_count = cast(i32) thread_count
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

render_start :: proc (render: ^Render, camera: Camera, models: [] Draw_Model, brdf_data: [] v3, materials: [] Material) {
    free_all(render.allocator)
    
    render.active = true
    render.canceled  = false
    render.requested = false
    
    render.stats = {}
    
    total_triangle_count: u32
    total_tree_count: u32
    for model in models {
        total_triangle_count += cast(u32) len(model.triangles)
        total_tree_count     += cast(u32) len(model.tree)
    }
    next_free_triangle_offset: u32
    next_free_tree_offset: u32
    
    render.triangles = make([] Ray_Triangle, total_triangle_count, render.allocator)
    render.normals   = make([] Normals,      total_triangle_count, render.allocator)
    render.trees     = make([] Tree_Node,    total_tree_count,     render.allocator)
    
    render.models = make([] RenderModel, len(models), render.allocator)
    for model, model_index in models {
        rm := &render.models[model_index]
        rm.material = model.material
        
        rm.forward = model.transform
        
        determinant := dot(model.transform.x, cross(model.transform.y, model.transform.z))
        inv_x := cross(model.transform.y, model.transform.z) / determinant
        inv_y := cross(model.transform.z, model.transform.x) / determinant
        inv_z := cross(model.transform.x, model.transform.y) / determinant
        rm.inverse.x = inv_x
        rm.inverse.y = inv_y
        rm.inverse.z = inv_z
        rm.inverse.t = transform_mul_0(rm.inverse, -rm.forward.t)
        rm.lane_inverse.x = vec_cast(lane_f32, rm.inverse.x)
        rm.lane_inverse.y = vec_cast(lane_f32, rm.inverse.y)
        rm.lane_inverse.z = vec_cast(lane_f32, rm.inverse.z)
        rm.lane_inverse.t = vec_cast(lane_f32, rm.inverse.t)
        
        {
            rm.triangle_offset = next_free_triangle_offset
            rm.triangle_count  = cast(u32) len(model.triangles)
            next_free_triangle_offset += rm.triangle_count
            
            triangles := render.triangles[rm.triangle_offset : rm.triangle_offset + rm.triangle_count]
            for &it, it_index in triangles {
                triangle := model.triangles[it_index]
                it.a  = triangle.a
                it.ab = triangle.b - triangle.a
                it.ac = triangle.c - triangle.a
            }
        }
        
        {
            normals := render.normals[rm.triangle_offset : rm.triangle_offset + rm.triangle_count]
            copy(normals, model.normals)
        }
        
        {
            rm.tree_offset = next_free_tree_offset
            rm.tree_count  = cast(u32) len(model.tree)
            next_free_tree_offset += rm.tree_count
            tree := render.trees[rm.tree_offset : rm.tree_offset + rm.tree_count]
            copy(tree, model.tree)
        }
    }
    
    render.brdf_data = brdf_data
    render.materials = make_shallow_copy(materials, render.allocator)
    
    zero_slice(render.image.data)
    
    tile_size := cast(v2i) max(render.image.width, render.image.height) / render.thread_count / 2
    tile_cols  := (render.image.width  + tile_size.x - 1) / tile_size.x
    tile_rows  := (render.image.height + tile_size.y - 1) / tile_size.y
    tile_count := tile_cols * tile_rows
    
    Work :: struct {
        render: ^Render,
        camera:  lane_Transform,
        rect:    Rectangle2i, 
        entropy: RandomSeries,
    }
    
    works := make([] Work, tile_count, render.allocator)
    work_index: u32
    
    lane_camera: lane_Transform
    lane_camera.x = vec_cast(lane_f32, camera.x)
    lane_camera.y = vec_cast(lane_f32, camera.y)
    lane_camera.z = vec_cast(lane_f32, camera.z)
    lane_camera.t = vec_cast(lane_f32, camera.t)
    
    render.start = time.now()
    for row in 0..<tile_rows {
        for col in 0..<tile_cols {
            rect := rectangle_min_dimension(tile_size * {col, row}, tile_size)
            rect  = rectangle_intersection(rect, rectangle_zero_dimension(render.image.width, render.image.height))
            
            entropy := seed_random_series(1842098778 + row * 984612097 + col * 237711 + cast(i32) work_index)
            
            work := &works[work_index]
            work_index += 1
            work ^= { render, lane_camera, rect, entropy }
        }
    }
    
    shift :: 2
    for oy in cast(i32) 0..<shift {
        for ox in cast(i32) 0..<shift {
            for row := oy; row < tile_rows; row += shift {
                for col := ox; col < tile_cols; col += shift {
                    index := row * tile_cols + col
                    work := &works[index]
                    enqueue_work_or_do_immediatly(&render.queue, proc(work: ^Work) {
                        render_tile(work.render, work.camera, work.rect, &work.entropy)
                    }, work)
                }
            }
        }
    }
}

////////////////////////////////////////////////

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