package main

World :: struct {
    objects:                [1024] Object,
    last_used_object_index: Object_Id,
    
    materials: [dynamic] Material,
    brdf_data: [dynamic] v3,
    
    material_names: [] string,
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
    append(&world.materials, Material{ emit    = { .3  , .4  , .5  }, emission = 2    })
    append(&world.materials, Material{ reflect = { .5  , .5  , .5  }, roughness = .9 })
    append(&world.materials, Material{ reflect = { .7  , .5  , .3  }, roughness = .3})
    append(&world.materials, Material{ emit    = { .35 , .2 ,  .01 }, roughness = .8, emission = 200, })
    append(&world.materials, Material{ reflect = { .2  , .8  , .2  }, roughness = .4})
    append(&world.materials, Material{ reflect = { .65 , .1  , .7  }, roughness = .95})
    append(&world.materials, Material{ reflect = { .9  , .9  , .8  }, roughness = .25})
    append(&world.materials, Material{ reflect = { .8  , .9  , .8  }, roughness = .05, transmit = {0.8, 1.0, 0.9}, transmission = 1, index_of_refraction = 1.5 })
    
    world.material_names = make([] string, len(world.materials), context.allocator)
    
    world_load_brdf(world, 0, "nil")
    world_load_brdf(world, 1, "gray-plastic")
    world_load_brdf(world, 2, "brass")
    world_load_brdf(world, 3, "gold-paint")
    world_load_brdf(world, 4, "green-latex")
    world_load_brdf(world, 5, "purple-paint")
    world_load_brdf(world, 6, "white-marble")
    world_load_brdf(world, 7, "glass")
}

world_load_brdf :: proc (world: ^World, material: Material_Id, name: string) {
    load_brdf_merl(tprint("./BRDFDatabase/brdfs/%v.binary", name), &world.materials[material].brdf, &world.brdf_data)
    world.material_names[material] = name
}

make_object :: proc (world: ^World) -> ^Object {
    world.last_used_object_index += 1
    result := &world.objects[world.last_used_object_index]
    
    result.transform = transform_set_scale(result.transform, v3{1, 1, 1})
    
    return result
}

////////////////////////////////////////////////

benchmark_scene :: proc (world: ^World) {
    {
        ctx := begin_model()
        load_obj(ctx, "./models", "stanford/lucy_280k.obj")
        end_model(ctx)
        
        object := make_object(world)
        object.model = ctx.id
        object.material = 2
    }
    
    { // light
        ctx := begin_model()
        load_obj(ctx, "./models", "sphere.obj")
        end_model(ctx)
        
        object := make_object(world)
        object.model = ctx.id
        object.material = 3
        object.transform = transform_set_scale(object.transform, v3{.5, .5, .5})
        object.transform.t = {0, 0, 16}
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

kenney_scene :: proc (world: ^World) {
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