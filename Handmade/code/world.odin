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

begin_object :: proc (world: ^World) -> ^Object {
    world.last_used_object_index += 1
    result := &world.objects[world.last_used_object_index]
    
    result.transform.x = {1,0,0}
    result.transform.y = {0,1,0}
    result.transform.z = {0,0,1}
    
    return result
}

////////////////////////////////////////////////

benchmark_scene :: proc (world: ^World) {
    // @cleanup make the model setup less fragile
    triangles := make([dynamic] Triangle, context.temp_allocator)
    normals   := make([dynamic] Normals,  context.temp_allocator)
    uvs       := make([dynamic] UVs,      context.temp_allocator)
    textures := make(map[string] Image, context.temp_allocator)
    texture: Image
    
    {
        // load_obj(&textures, "./models", "stanford/bunny.obj", &triangles, &normals, &uvs, &texture)
        load_obj(&textures, "./models", "stanford/lucy_280k.obj", &triangles, &normals, &uvs, &texture)
        
        object := begin_object(world)
        model, index := begin_model()
        object.model = index
        object.transform.t = {0,0,0}
        object.material = 2
        end_model(model, triangles[:], normals[:], uvs[:], texture)
    }
    
    { // light
        load_obj(&textures, "./models", "sphere.obj", &triangles, &normals, &uvs, &texture)
        
        object := begin_object(world)
        model, index := begin_model()
        object.model = index
        object.material = 3
        object.transform.x = {.5,0,0}
        object.transform.y = {0,.5,0}
        object.transform.z = {0,0,.5}
        object.transform.t = {0,0,16}
        end_model(model, triangles[:], normals[:], uvs[:], texture)
    }
    
    { // ground
        load_obj(&textures, "./models", "plane.obj", &triangles, &normals, &uvs, &texture)
        
        
        object := begin_object(world)
        model, index := begin_model()
        object.model = index
        object.material = 1
        object.transform.x = {50,0,0}
        object.transform.y = {0,50,0}
        end_model(model, triangles[:], normals[:], uvs[:], texture)
    }
}

kenney_scene :: proc (world: ^World) {
    // @cleanup make the model setup less fragile
    triangles := make([dynamic] Triangle, context.temp_allocator)
    normals   := make([dynamic] Normals,  context.temp_allocator)
    uvs       := make([dynamic] UVs,      context.temp_allocator)
    textures := make(map[string] Image, context.temp_allocator)
    texture: Image
    
    {
        load_obj(&textures, "./models/kenney_graveyard-kit/Models/OBJ format", "pine-crooked.obj", &triangles, &normals, &uvs, &texture, flip_yz = true)
        
        object := begin_object(world)
        model, index := begin_model()
        object.model = index
        object.material = 1
        object.transform.t = {0,0,.1}
        object.transform.x = {3,0,0}
        object.transform.y = {0,3,0}
        object.transform.z = {0,0,3}
        end_model(model, triangles[:], normals[:], uvs[:], texture)
    }
    { // ground
        load_obj(&textures, "./models", "plane.obj", &triangles, &normals, &uvs, &texture)
        
        
        object := begin_object(world)
        model, index := begin_model()
        object.model = index
        object.material = 4
        object.transform.x = {50,0,0}
        object.transform.y = {0,50,0}
        end_model(model, triangles[:], normals[:], uvs[:], texture)
    }
}

default_scene :: proc (world: ^World) {
    // @cleanup make the model setup less fragile
    triangles := make([dynamic] Triangle, context.temp_allocator)
    normals   := make([dynamic] Normals,  context.temp_allocator)
    uvs       := make([dynamic] UVs,      context.temp_allocator)
    textures := make(map[string] Image, context.temp_allocator)
    texture: Image
    
    {
        load_obj(&textures, "./models", "suzanne.obj", &triangles, &normals, &uvs, &texture)
        
        
        object := begin_object(world)
        model, index := begin_model()
        object.model = index
        object.transform.t = {2.5,0,1}
        object.material = 4
        end_model(model, triangles[:], normals[:], uvs[:], texture)
    }
    
    { // light
        load_obj(&textures, "./models", "sphere.obj", &triangles, &normals, &uvs, &texture)
        
        object := begin_object(world)
        model, index := begin_model()
        object.model = index
        object.material = 3
        object.transform.x = {.5,0,0}
        object.transform.y = {0,.5,0}
        object.transform.z = {0,0,.5}
        object.transform.t = {0,0,3}
        end_model(model, triangles[:], normals[:], uvs[:], texture)
    }
    
    {
        // load_obj(&textures, "./models", "uvsphere.obj", &triangles, &normals, &uvs, &texture)
        load_obj(&textures, "./models", "cube_smooth.obj", &triangles, &normals, &uvs, &texture)
     
        
        object := begin_object(world)
        model, index := begin_model()
        object.model = index
        object.material = 5
        object.transform.t = {-1,0,1}
        end_model(model, triangles[:], normals[:], uvs[:], texture)
    }
    
    { // ground
        load_obj(&textures, "./models", "plane.obj", &triangles, &normals, &uvs, &texture)
        
        
        object := begin_object(world)
        model, index := begin_model()
        object.model = index
        object.material = 1
        object.transform.x = {50,0,0}
        object.transform.y = {0,50,0}
        end_model(model, triangles[:], normals[:], uvs[:], texture)
    }
}