package main

World :: struct {
    objects:                [1024] Object,
    last_used_object_index: Object_Index,
    
    materials: [dynamic] Material,
    brdf_data: [dynamic] v3,
    
    material_names: [] string,
}

Object_Index :: distinct u32

Object :: struct {
    model:     Model_Index,
    transform: Transform,
    material:  u32,
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

begin_object :: proc (world: ^World) -> ^Object {
    world.last_used_object_index += 1
    result := &world.objects[world.last_used_object_index]
    
    result.transform.x = {1,0,0}
    result.transform.y = {0,1,0}
    result.transform.z = {0,0,1}
    
    return result
}

////////////////////////////////////////////////

default_scene :: proc (world: ^World) {
    // @cleanup make the model setup less fragile
    triangles := make([dynamic] Triangle, context.temp_allocator)
    normals   := make([dynamic] Normals, context.temp_allocator)
    
    {
        // 0 =   3488 triangles
        // 1 =  19480 triangles, 5.5x 0
        // 2 = 145620 triangles, 7.5x 1
        
        load_obj("./models/teapot0.obj", &triangles, &normals)
        
        object := begin_object(world)
        model, index := begin_model()
        object.model = index
        object.material = 2
        object.transform.t = {-3,0,1.5}
        end_model(model, triangles[:], normals[:])
    }
    
    {
        load_obj("./models/suzanne.obj", &triangles, &normals)
        
        
        object := begin_object(world)
        model, index := begin_model()
        object.model = index
        object.transform.t = {2,0,1}
        object.material = 4
        end_model(model, triangles[:], normals[:])
    }
    
    { // light
        load_obj("./models/sphere.obj", &triangles, &normals)
        
        object := begin_object(world)
        model, index := begin_model()
        object.model = index
        object.material = 3
        object.transform.x = {.5,0,0}
        object.transform.y = {0,.5,0}
        object.transform.z = {0,0,.5}
        object.transform.t = {0,0,3}
        end_model(model, triangles[:], normals[:])
    }
    
    {
        // load_obj("./models/uvsphere.obj", &triangles, &normals)
        load_obj("./models/cube_smooth.obj", &triangles, &normals)
     
        
        object := begin_object(world)
        model, index := begin_model()
        object.model = index
        object.material = 5
        object.transform.t = {0,0,1}
        end_model(model, triangles[:], normals[:])
    }
    
    { // ground
        load_obj("./models/plane.obj", &triangles, &normals)
        
        
        object := begin_object(world)
        model, index := begin_model()
        object.model = index
        object.material = 1
        object.transform.x = {50,0,0}
        object.transform.y = {0,50,0}
        end_model(model, triangles[:], normals[:])
    }
}