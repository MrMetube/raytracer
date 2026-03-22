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

teapot_scene :: proc (world: ^World) {
    // @todo(viktor): fixed Buffer of models and return indices
    reserve(&world.models, 128)
    
    triangles := make([dynamic] Triangle, context.temp_allocator)
    
    // @cleanup 
    { // light
        clear(&triangles)
        plane := world_create_model(world)
        plane.material = 3
        plane.translation = {0,0,4}
        
        v0 := v3 {-1, -1, 0}
        v1 := v3 {-1,  1, 0}
        v2 := v3 { 1,  1, 0}
        v3 := v3 { 1, -1, 0}
        
        append(&triangles, Triangle{ a = v0, b = v2, c = v3})
        append(&triangles, Triangle{ a = v0, b = v1, c = v2})
        
        tree_build(&plane.tree, triangles[:])
        plane.triangles = make_shallow_copy(triangles[:], context.allocator) 
    }
    
    { // ground
        clear(&triangles)
        plane := world_create_model(world)
        plane.material = 1
        plane.scale_x = {50,0,0}
        plane.scale_y = {0,50,0}
        v0 := v3 {-1, -1, 0}
        v1 := v3 {-1,  1, 0}
        v2 := v3 { 1,  1, 0}
        v3 := v3 { 1, -1, 0}
        
        append(&triangles, Triangle{ a = v0, b = v2, c = v3})
        append(&triangles, Triangle{ a = v0, b = v1, c = v2})
        
        when !Use_Transform do for &t in triangles {
            t.a.xy *= 50
            t.b.xy *= 50
            t.c.xy *= 50
        }
        
        tree_build(&plane.tree, triangles[:])
        plane.triangles = make_shallow_copy(triangles[:], context.allocator)
    }
    
    if false {
        { // top
            clear(&triangles)
            plane := world_create_model(world)
            plane.material = 6
            plane.translation = {0,0,4}
            plane.scale_x = {4,0,0}
            plane.scale_y = {0,4,0}
            
            v0 := v3 {-1, -1, 0}
            v1 := v3 {-1,  1, 0}
            v2 := v3 { 1,  1, 0}
            v3 := v3 { 1, -1, 0}
            
            append(&triangles, Triangle{ a = v0, b = v2, c = v3})
            append(&triangles, Triangle{ a = v0, b = v1, c = v2})
            
            plane.triangles = make_shallow_copy(triangles[:], context.allocator)
            tree_build(&plane.tree, plane.triangles)
        }
        
        { // back
            clear(&triangles)
            plane := world_create_model(world)
            plane.material = 6
            plane.translation = {0,4,0}
            plane.scale_x = {4,0,0}
            plane.scale_z = {0,0,4}
            
            v0 := v3 {-1, 0, -1}
            v1 := v3 {-1, 0,  1}
            v2 := v3 { 1, 0,  1}
            v3 := v3 { 1, 0, -1}
            
            append(&triangles, Triangle{ a = v0, b = v2, c = v3})
            append(&triangles, Triangle{ a = v0, b = v1, c = v2})
            
            plane.triangles = make_shallow_copy(triangles[:], context.allocator)
            tree_build(&plane.tree, plane.triangles)
        }
        
        { // right
            clear(&triangles)
            plane := world_create_model(world)
            plane.material = 5
            plane.translation = {4,0,0}
            plane.scale_y = {0,4,0}
            plane.scale_z = {0,0,4}
            
            v0 := v3 {0, -1, -1}
            v1 := v3 {0, -1,  1}
            v2 := v3 {0,  1,  1}
            v3 := v3 {0,  1, -1}
            
            append(&triangles, Triangle{ a = v0, b = v2, c = v3})
            append(&triangles, Triangle{ a = v0, b = v1, c = v2})
            
            plane.triangles = make_shallow_copy(triangles[:], context.allocator)
            tree_build(&plane.tree, plane.triangles)
        }
        
        { // left
            clear(&triangles)
            plane := world_create_model(world)
            plane.material = 4
            plane.translation = {-4,0,0}
            plane.scale_y = {0,4,0}
            plane.scale_z = {0,0,4}
            
            v0 := v3 {0, -1, -1}
            v1 := v3 {0, -1,  1}
            v2 := v3 {0,  1,  1}
            v3 := v3 {0,  1, -1}
            
            append(&triangles, Triangle{ a = v0, b = v2, c = v3})
            append(&triangles, Triangle{ a = v0, b = v1, c = v2})
            
            plane.triangles = make_shallow_copy(triangles[:], context.allocator)
            tree_build(&plane.tree, plane.triangles)
        }
    }
    
    {
        clear(&triangles)
        // 0 =   3488 triangles
        // 1 =  19480 triangles, 5.5x 0
        // 2 = 145620 triangles, 7.5x 1
        
        teapot := world_create_model(world)
        teapot.material = 2
        
        load_teapot(&triangles, 0)
        
        teapot.triangles = make_shallow_copy(triangles[:], context.allocator)
        tree_build(&teapot.tree, teapot.triangles)
    }
}

Use_Transform :: !false