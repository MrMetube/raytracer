package main

World :: struct {
    models: [dynamic] Model,
    
    materials: [dynamic] Material,
    brdf_data: [dynamic] v3,
    
    material_names: [] string,
}

////////////////////////////////////////////////

world_init :: proc (world: ^World) {
    append(&world.materials, Material{ emit    = { .3  , .4  , .5  }, emit_factor = 2   })
    append(&world.materials, Material{ reflect = { .5  , .5  , .5  }, scatter = .99     })
    append(&world.materials, Material{ reflect = { .7  , .5  , .3  }, scatter = .8      })
    append(&world.materials, Material{ emit    = { .35 , .2 ,  .01 }, emit_factor = 1000 })
    append(&world.materials, Material{ reflect = { .2  , .8  , .2  }, scatter = .75     })
    append(&world.materials, Material{ reflect = { .65 , .1  , .7  }, scatter = 1.      })
    append(&world.materials, Material{ reflect = { .9  , .9  , .8  }, scatter = .6      })
    
    world.material_names = make([] string, len(world.materials), context.allocator)
    
    world_load_brdf(world, 0, "nil")
    world_load_brdf(world, 1, "gray-plastic")
    world_load_brdf(world, 2, "brass")
    world_load_brdf(world, 3, "gold-paint")
    world_load_brdf(world, 4, "green-latex")
    world_load_brdf(world, 5, "purple-paint")
    world_load_brdf(world, 6, "white-marble")
}

world_load_brdf :: proc (world: ^World, material_index: u32, name: string) {
    load_brdf_merl(tprint("./BRDFDatabase/brdfs/%v.binary", name), &world.materials[material_index].brdf, &world.brdf_data)
    world.material_names[material_index] = name
}

world_create_model :: proc (world: ^World) -> ^Model {
    model_index := len(world.models)
    append_nothing(&world.models)
    result := &world.models[model_index]
    result.scale_x = {1,0,0}
    result.scale_y = {0,1,0}
    result.scale_z = {0,0,1}
    return result
}

////////////////////////////////////////////////

default_scene :: proc (world: ^World) {
    // @todo(viktor): fixed Buffer of models and return indices
    reserve(&world.models, 128)
    
    // @cleanup make the model setup less fragile
    
    triangles := make([dynamic] Triangle, context.temp_allocator)
    normals   := make([dynamic] Normals, context.temp_allocator)
    
    {
        // 0 =   3488 triangles
        // 1 =  19480 triangles, 5.5x 0
        // 2 = 145620 triangles, 7.5x 1
        
        model := world_create_model(world)
        model.material = 2
        model.translation = {-3,0,1.5}
        
        load_obj("./models/teapot0.obj", &triangles, &normals)
        
        tree_build(&model.tree, triangles[:], normals[:])
        model.triangles = make_shallow_copy(triangles[:], context.allocator)
        model.normals   = make_shallow_copy(normals[:], context.allocator)
    }
    
    {
        model := world_create_model(world)
        model.translation = {2,0,1}
        model.material = 4
        
        load_obj("./models/suzanne.obj", &triangles, &normals)
        
        tree_build(&model.tree, triangles[:], normals[:])
        model.triangles = make_shallow_copy(triangles[:], context.allocator)
        model.normals   = make_shallow_copy(normals[:], context.allocator)
    }
    
    { // light
        model := world_create_model(world)
        model.material = 3
        model.scale_x = {.5,0,0}
        model.scale_y = {0,.5,0}
        model.scale_z = {0,0,.5}
        model.translation = {0,0,3}
        
        load_obj("./models/sphere.obj", &triangles, &normals)
        
        tree_build(&model.tree, triangles[:], normals[:])
        model.triangles = make_shallow_copy(triangles[:], context.allocator)
        model.normals   = make_shallow_copy(normals[:],   context.allocator)
    }
    
    {
        model := world_create_model(world)
        model.material = 5
        model.translation = {0,0,1}
        
        // load_obj("./models/uvsphere.obj", &triangles, &normals)
        load_obj("./models/cube_smooth.obj", &triangles, &normals)
        
        tree_build(&model.tree, triangles[:], normals[:])
        model.triangles = make_shallow_copy(triangles[:], context.allocator)
        model.normals   = make_shallow_copy(normals[:],   context.allocator)
    }
    
    { // ground
        model := world_create_model(world)
        model.material = 1
        model.scale_x = {50,0,0}
        model.scale_y = {0,50,0}
        
        load_obj("./models/plane.obj", &triangles, &normals)
        
        tree_build(&model.tree, triangles[:], normals[:])
        model.triangles = make_shallow_copy(triangles[:], context.allocator)
        model.normals   = make_shallow_copy(normals[:],   context.allocator)
    }
}