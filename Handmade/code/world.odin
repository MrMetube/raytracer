package main

World :: struct {
    objects:                [1024] Object,
    last_used_object_index: Object_Id,
    
    materials: [dynamic] Material,
    
    material_names: [dynamic] string,
}

Object_Id   :: distinct u32
Material_Id :: distinct u32

Object :: struct {
    model:     Model_Id,
    transform: Transform,
    material:  Material_Id,
}

////////////////////////////////////////////////

world_init :: proc (world: ^World) {
    append(&world.materials, Material{ emit_color = { .3  , .4  , .5  }, emit_strength = 2 })
    append(&world.material_names, "nil")
}

load_default_materials :: proc (world: ^World) {
    append(&world.materials, Material{ base_tint = { .5  , .5  , .5  }, roughness = .9 })
    append(&world.materials, Material{ base_tint = { .7  , .5  , .3  }, roughness = .3})
    append(&world.materials, Material{ emit_color = { .35 , .2 ,  .01 }, roughness = .8, emit_strength = 200, })
    append(&world.materials, Material{ base_tint = { .2  , .8  , .2  }, roughness = .4})
    append(&world.materials, Material{ base_tint = { .65 , .1  , .7  }, roughness = .95})
    append(&world.materials, Material{ base_tint = { .9  , .9  , .8  }, roughness = .25})
    // append(&world.materials, Material{ base_tint = { .8  , .9  , .8  }, roughness = .05, transmit = {0.8, 1.0, 0.9}, transmission = 1, index_of_refraction = 1.5 })
    
    append(&world.material_names, "gray-plastic")
    append(&world.material_names, "brass")
    append(&world.material_names, "gold-paint")
    append(&world.material_names, "green-latex")
    append(&world.material_names, "purple-paint")
    append(&world.material_names, "white-marble")
    // append(&world.material_names, "glass")
}

clone_string :: proc (s: string, allocator := context.allocator) -> string {
    bytes := make([] u8, len(s), allocator)
    copy(bytes, transmute([] u8) s)
    result := transmute(string) bytes
    return result
}

make_object :: proc (world: ^World) -> ^Object {
    world.last_used_object_index += 1
    result := &world.objects[world.last_used_object_index]
    
    result.transform = transform_set_scale(result.transform, v3{1, 1, 1})
    
    return result
}

////////////////////////////////////////////////

benchmark_scene :: proc (world: ^World) {
    load_default_materials(world)
    
    {
        ctx := begin_model()
        load_obj(ctx, "./models", "stanford/lucy_280k.obj")
        end_model(ctx)
        
        object := make_object(world)
        object.model = ctx.id
        object.material = 5
        object.transform.t.y =  5
        object.transform.t.z = -10
    }
    
    { // light
        ctx := begin_model()
        load_obj(ctx, "./models", "plane.obj")
        end_model(ctx)
        
        object := make_object(world)
        object.model = ctx.id
        object.material = 3
        object.transform = transform_set_scale(object.transform, v3{16, 16, 1})
        object.transform.t.z = 16
    }
}

kenney_scene :: proc (world: ^World) {
    load_default_materials(world)
    
    {
        ctx := begin_model()
        Kenney ::"./models/kenney_graveyard-kit/Models/OBJ format" 
        load_obj(ctx, Kenney, "pine-crooked.obj", flip_yz = true)
        ctx.model.base_color = load_texture_from_png(Kenney+"/Textures/colormap.png")
        end_model(ctx)
        
        object := make_object(world)
        object.model = ctx.id
        object.material = 1
        object.transform.t = {0,0,.1}
        object.transform = transform_set_scale(object.transform, v3{3, 3, 3})
    }
    { // ground
        ctx := begin_model()
        load_obj(ctx, "./models", "plane.obj")
        end_model(ctx)
        
        object := make_object(world)
        object.model = ctx.id
        object.material = 4
        object.transform = transform_set_scale(object.transform, v3{50, 50, 1})
    }
}

default_scene :: proc (world: ^World) {
    load_default_materials(world)
    
    {
        ctx := begin_model()
        load_obj(ctx, "./models", "suzanne.obj")
        end_model(ctx)
        
        object := make_object(world)
        object.model = ctx.id
        object.transform.t = {2.5, 0, 1}
        object.material = 4
    }
    
    { // light
        ctx := begin_model()
        load_obj(ctx, "./models", "sphere.obj")
        end_model(ctx)
        
        object := make_object(world)
        object.model = ctx.id
        object.material = 3
        object.transform = transform_set_scale(object.transform, v3{.5, .5, .5})
        object.transform.t = {0, 0, 3}
    }
    
    {
        ctx := begin_model()
        load_obj(ctx, "./models", "cube_smooth.obj")
        end_model(ctx)
        
        entropy := seed_random_series(23)
        for _ in 0..<5 {
            object := make_object(world)
            object.model = ctx.id
            object.material = cast(Material_Id) random_between_u32(&entropy, 4, 5)
            
            radius := random_unilateral(&entropy, f32) + .5
            object.transform = transform_set_scale(object.transform, v3{radius, radius, radius})
            object.transform.t.xy = random_bilateral(&entropy, v2) * 10
            object.transform.t.z = radius
        }
    }
    
    { // ground
        ctx := begin_model()
        load_obj(ctx, "./models", "plane.obj")
        end_model(ctx)
        
        object := make_object(world)
        object.model = ctx.id
        object.material = 1
        object.transform = transform_set_scale(object.transform, v3{50, 50, 1})
    }
}