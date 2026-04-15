#+vet explicit-allocators
package main

import "core:time"
import "core:mem"
import rl "vendor:raylib"

Render :: struct {
    active:   bool,
    canceled: bool,
    
    queue: WorkQueue,
}

Render_Stats :: struct {
    bounces_computed: u64,
    loops_computed:   u64,
    tiles_retired:    u32,
    pixels_done:      u32,
    
    using tests: Test_Info,
}

Render_Settings :: struct {
    is_open: bool,
    
    requested: bool,
    active:    bool,
    display_progress: bool,
    
    image:   Image,
    texture: rl.Texture,
    
    image_size_factor: i32,
    
    arena:     mem.Arena,
    allocator: Allocator,
    
    draw_camera: Camera,
    draw_models: [dynamic] Draw_Model,
    
    rays_per_pixel:   u32,
    max_bounce_count: u32,
    
    ////////////////////////////////////////////////
    // Debug / Dev
    stats: Render_Stats,
    start, end: time.Time,
    render_time:  Stat(time.Duration),
    time_per_ray: Stat(time.Duration),
}

Normals :: [3] v3
UVs     :: [3] v2

Model :: struct {
    raw_triangles: [] Triangle,
    raw_normals:   [] Normals,
    raw_uvs:       [] UVs,
    
    using data: Model_Data,
}

Draw_Model :: struct {
    using data: Model_Data,
    
    forward: Transform,
    inverse: Transform,
    normal:  Transform,
    
    material: Material_Id,
}

// @note(viktor): all data is guaranteed to be from the render.allocator
Render_Model :: distinct Draw_Model

Model_Data :: struct {
    triangles: [] lane_Triangle,
    normals:   [] Normals,
    uvs:       [] UVs,
    tree:      [] Tree_Node,
    
    base_color: Image,
}

Image :: struct {
    data:   [] Color,
    width:  i32,
    height: i32,
}

Color :: [4] u8

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
    emit:     v3,
    reflect:  v3,
    transmit: v3,
    
    emission:  f32,
    roughness: f32,
    index_of_refraction: f32,
    transmission:        f32,
    
    brdf: BrdfTable,
}

BrdfTable :: struct {
    count: [3] u32,
    // @note(viktor): a view into the render.brdf_data array
    value_offset: u32,
    value_count:  u32,
}

////////////////////////////////////////////////

Model_Id :: distinct u32
Models: [256] Model
last_used_model_id: Model_Id

the_model_loader: Model_Loader

Model_Loader :: struct {
    valid: bool,
    
    model: ^Model,
    id:    Model_Id,
    
    triangles: [dynamic] Triangle,
    normals:   [dynamic] Normals,
    uvs:       [dynamic] UVs,
}

begin_model :: proc () -> (^Model_Loader) {
    last_used_model_id += 1
    model := &Models[last_used_model_id]
    
    result := &the_model_loader
    result.model = model
    result.id    = last_used_model_id
    
    if !result.valid {
        result.valid = true
        result.triangles = make([dynamic] Triangle, context.temp_allocator)
        result.normals   = make([dynamic] Normals,  context.temp_allocator)
        result.uvs       = make([dynamic] UVs,      context.temp_allocator)
    } else {
        clear(&result.triangles)
        clear(&result.normals)
        clear(&result.uvs)
    }
    
    return result
}

end_model :: proc (loader: ^Model_Loader) {
    model := loader.model
    model.raw_triangles = make_shallow_copy(loader.triangles[:], context.allocator)
    model.raw_normals   = make_shallow_copy(loader.normals[:],   context.allocator)
    model.raw_uvs       = make_shallow_copy(loader.uvs[:],       context.allocator)
    
    if model.base_color.data == nil {
        pixel := make([] Color, 1, context.allocator)
        pixel[0] = 255
        model.base_color = { pixel, 1, 1 }
    }
    
    model_rebuild_tree(model)
}

model_rebuild_tree :: proc (model: ^Model) {
    allocator := context.allocator
    
    // @api
    delete(model.triangles,   allocator)
    delete(model.normals,     allocator)
    delete(model.uvs,         allocator)
    delete(model.tree, allocator)
    
    model.triangles, model.normals, model.uvs, model.tree = tree_build(model.raw_triangles, model.raw_normals, model.raw_uvs, allocator)
}

////////////////////////////////////////////////

render_begin :: proc (render: ^Render, settings: ^Render_Settings) -> bool {
    if settings.active {
        reload := false
        if work_is_completed(&render.queue) {
            reload = true
            
            render.active = false
            settings.active = false
            settings.end = time.now()
            total_time := time.diff(settings.start, settings.end)
            stat_update(&settings.render_time, total_time)
            stat_finalize(&settings.render_time)
            time_per_ray := get_time_per_ray_and_print_stats(&settings.stats, total_time)
            stat_update(&settings.time_per_ray, time_per_ray)
            stat_finalize(&settings.time_per_ray)
            
            free_all(settings.allocator)
        }
        
        if reload || settings.display_progress {
            rl.UnloadTexture(settings.texture)
    
            rl_image := rl.Image {
                data    = raw_data(settings.image.data),
                width   = settings.image.width,
                height  = settings.image.height,
                mipmaps = 1,
                format  = .UNCOMPRESSED_R8G8B8A8,
            }
            
            settings.texture = rl.LoadTextureFromImage(rl_image)
        }
    }
    
    result := settings.requested && !render.active
    return result
}

draw_model :: proc (settings: ^Render_Settings, model_id: Model_Id, material: Material_Id, transform: Transform) {
    assert(settings.requested)
    assert(!settings.active)
    
    if model_id == 0 do return
    model := &Models[model_id]
    
    dm: Draw_Model
    dm.data       = model.data
    dm.base_color = model.base_color
    
    dm.forward = transform
    dm.inverse = transform_invert(dm.forward)
    dm.normal  = transform_transpose(Transform{ dm.inverse.x, dm.inverse.y, dm.inverse.z, 0 })
    
    dm.material = material
    
    append(&settings.draw_models, dm)
}

set_camera :: proc (settings: ^Render_Settings, camera: Camera) {
    assert(settings.requested)
    assert(!settings.active)
    
    settings.draw_camera = camera
}

render_end :: proc (render: ^Render, settings: ^Render_Settings, brdf_data: [] v3, materials: [] Material) {
    assert(settings.requested)
    assert(!settings.active)
    
    // @speed build tree of models once there are enough models in a scene
    
    render_start(render, settings, settings.draw_camera, settings.draw_models[:], brdf_data, materials)
    clear(&settings.draw_models)
}

////////////////////////////////////////////////

init_render_settings :: proc (settings: ^Render_Settings, rays_per_pixel: u32, max_bounce_count: u32, window_size: v2i, image_size_factor: i32) {
    settings.rays_per_pixel    = rays_per_pixel
    settings.max_bounce_count  = max_bounce_count
    settings.image_size_factor = image_size_factor
    
    backing, err := make([] u8, 1 * Gigabyte, context.allocator); assert(err == nil)
    mem.arena_init(&settings.arena, backing)
    settings.allocator = mem.arena_allocator(&settings.arena)
    
    init_render_image(settings, window_size)
}

init_render :: proc (render: ^Render, thread_count: u32) {
    init_work_queue(&render.queue, "Render", thread_count)
}

init_render_image :: proc (settings: ^Render_Settings, window_size: v2i) {
    assert(!settings.active)
    
    delete(settings.image.data, context.allocator)
    
    image_size := window_size / settings.image_size_factor
    settings.image.width  = image_size.x
    settings.image.height = image_size.y
    settings.image.data   = make([] Color, settings.image.width * settings.image.height, context.allocator)
}

render_start :: proc (render: ^Render, settings: ^Render_Settings, camera: Camera, models: [] Draw_Model, brdf_data: [] v3, materials: [] Material) {
    free_all(settings.allocator)
    
    render.active   = true
    render.canceled = false
    settings.active    = true
    settings.requested = false
    
    settings.stats = {}
    
    total_count_triangle: u32
    total_count_normals:  u32
    total_count_uvs:      u32
    total_count_tree:     u32
    for model in models {
        total_count_triangle += cast(u32) len(model.triangles)
        total_count_normals  += cast(u32) len(model.normals)
        total_count_uvs      += cast(u32) len(model.uvs)
        total_count_tree     += cast(u32) len(model.tree)
    }
    
    render_triangles := make([] lane_Triangle, total_count_triangle, settings.allocator)
    render_normals   := make([] Normals,       total_count_normals,  settings.allocator)
    render_uvs       := make([] UVs,           total_count_uvs,      settings.allocator)
    render_trees     := make([] Tree_Node,    total_count_tree,     settings.allocator)
    
    next_free_triangles := render_triangles
    next_free_normals   := render_normals
    next_free_uvs       := render_uvs
    next_free_trees     := render_trees
    
    render_models := make([] Render_Model, len(models), settings.allocator)
    for model, model_index in models {
        rm := &render_models[model_index]
        
        rm.base_color = model.base_color
        rm.material   = model.material
        
        rm.forward = model.forward
        rm.inverse = model.inverse
        rm.normal  = model.normal
        
        copy_over_slice :: proc (s: ^[] $T, next_free: ^[] T, source: [] T) {
            count := len(source)
            
            s^         = next_free[:count]
            next_free^ = next_free[count:]
            
            copy(s^, source)
        }
        
        copy_over_slice(&rm.normals,   &next_free_normals,   model.normals)
        copy_over_slice(&rm.uvs,       &next_free_uvs,       model.uvs)
        copy_over_slice(&rm.triangles, &next_free_triangles, model.triangles)
        copy_over_slice(&rm.tree,      &next_free_trees,     model.tree)
    }
    
    assert(len(next_free_normals)   == 0)
    assert(len(next_free_uvs)       == 0)
    assert(len(next_free_triangles) == 0)
    assert(len(next_free_trees)     == 0)
    
    render_materials := make_shallow_copy(materials, settings.allocator)
    
    // @todo(viktor): make this a copy and preserve the image until this is completed and so canceling isn't so bad
    zero_slice(settings.image.data)
    
    tile_size := cast(v2i) max(settings.image.width, settings.image.height) / cast(i32) render.queue.thread_count / 2
    tile_cols  := (settings.image.width  + tile_size.x - 1) / tile_size.x
    tile_rows  := (settings.image.height + tile_size.y - 1) / tile_size.y
    tile_count := tile_cols * tile_rows
    
    Work :: struct {
        render: ^Render,
        rect:    Rectangle2i, 
        entropy: RandomSeries,
        stats:  ^Render_Stats,
        
        info: Render_Tile_Info,
    }
    
    works := make([dynamic] Work, 0, tile_count, settings.allocator)
    
    image := settings.image
    image_size := vec_cast(f32, image.width, image.height)
    
    film_distance :: 1
    film_center := camera.t - film_distance * camera.z
    film_size := cast(v2) 1
    if image_size.x > image_size.y {
        film_size.x = film_size.y * image_size.x / image_size.y
    } else if image_size.x < image_size.y {
        film_size.y = film_size.x * image_size.y / image_size.x
    }
    
    half_film_size    := .5 * film_size
    pixel_size        := 1 / image_size
    image_size_factor := 1 / image_size
    
    info := Render_Tile_Info {
        image_size_factor = image_size_factor,
        film_center       = film_center,
        pixel_size        = pixel_size,
        image             = image,
        rays_per_pixel    = settings.rays_per_pixel,
        max_bounce_count  = settings.max_bounce_count,
        
        models    = render_models,
        materials = render_materials,
        brdf_data = brdf_data,
        
        camera_x = vec_cast(lane_f32, half_film_size.x * camera.x),
        camera_y = vec_cast(lane_f32, half_film_size.y * camera.y),
        camera_p = vec_cast(lane_f32, camera.t),
    }
    
    for row in 0..<tile_rows {
        for col in 0..<tile_cols {
            rect := rect_min_dimension(tile_size * {col, row}, tile_size)
            rect  = rect_intersection(rect, rect_zero_dimension(settings.image.width, settings.image.height))
            
            entropy := seed_random_series(1842098778 + row * 984612097 + col * 237711 + cast(i32) len(works))
            
            work := Work { 
                render,
                rect,
                entropy,
                &settings.stats,
                
                info,
            }
            append(&works, work)
        }
    }
    
    settings.start = time.now()
    shift :: 3
    for oy in cast(i32) 0..<shift {
        for ox in cast(i32) 0..<shift {
            for row := oy; row < tile_rows; row += shift {
                for col := ox; col < tile_cols; col += shift {
                    index := row * tile_cols + col
                    work := &works[index]
                    enqueue_work_or_do_immediatly(&render.queue, proc(work: ^Work) {
                        render_tile(work.render, work.rect, &work.entropy, work.stats, work.info)
                    }, work)
                }
            }
        }
    }
}

////////////////////////////////////////////////

get_time_per_ray_and_print_stats :: proc (stats: ^Render_Stats, total_time: time.Duration) -> time.Duration {
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
    
    
    
    total_tests := stats.triangles + stats.rectangles
    
    print("Hit tests:\n")
    print("  total tests = %v\n",      view_magnitude(total_tests))
    print("  triangles   = %v (%v)\n", view_magnitude(stats.triangles),  view_percentage(stats.triangles, total_tests))
    print("    hits      = %v (%v)\n", view_magnitude(stats.triangle_hits),  view_percentage(stats.triangle_hits, stats.triangles))
    print("  rectangles  = %v (%v)\n", view_magnitude(stats.rectangles), view_percentage(stats.rectangles, total_tests))
    
    print("\n")
    
    return cast(time.Duration) time_per_ray
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

