package main

// @volatile also update the render's world copying
World :: struct {
    models: [dynamic] Model,
    
    materials: [dynamic] Material,
    material_names: [] string,
    all_brdf_values: [dynamic] v3,
}

Model :: struct {
    triangles: [] Triangle,
    tree:      [] Tree_Node,
    translation: v3,
    material:    u32,
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
    load_brdf_merl(tprint("./BRDFDatabase/brdfs/%v.binary", name), &world.materials[material_index].brdf, &world.all_brdf_values)
    world.material_names[material_index] = name
}

world_create_model :: proc (world: ^World) -> ^Model {
    model_index := len(world.models)
    append_nothing(&world.models)
    result := &world.models[model_index]
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
        
        append(&triangles, Triangle{ a = v0, b = v2, c = v3, material = plane.material})
        append(&triangles, Triangle{ a = v0, b = v1, c = v2, material = plane.material})
        
        tree_build(&plane.tree, triangles[:])
        plane.triangles = make_shallow_copy(triangles[:], context.allocator) 
    }
    
    { // ground
        clear(&triangles)
        plane := world_create_model(world)
        plane.material = 1
        
        v0 := v3 {-1, -1, 0}
        v1 := v3 {-1,  1, 0}
        v2 := v3 { 1,  1, 0}
        v3 := v3 { 1, -1, 0}
        
        append(&triangles, Triangle{ a = v0, b = v2, c = v3, material = plane.material})
        append(&triangles, Triangle{ a = v0, b = v1, c = v2, material = plane.material})
        
        for &t in triangles {
            t.a.xy *= 500
            t.b.xy *= 500
            t.c.xy *= 500
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
            
            v0 := v3 {-1, -1, 0}
            v1 := v3 {-1,  1, 0}
            v2 := v3 { 1,  1, 0}
            v3 := v3 { 1, -1, 0}
            
            append(&triangles, Triangle{ a = v0, b = v2, c = v3, material = plane.material})
            append(&triangles, Triangle{ a = v0, b = v1, c = v2, material = plane.material})
            
            for &t in triangles {
                t.a.xy *= 4
                t.b.xy *= 4
                t.c.xy *= 4
            }
            
            tree_build(&plane.tree, triangles[:])
            plane.triangles = make_shallow_copy(triangles[:], context.allocator)
        }
        
        { // back
            clear(&triangles)
            plane := world_create_model(world)
            plane.material = 6
            plane.translation = {0,4,0}
            
            v0 := v3 {-1, 0, -1}
            v1 := v3 {-1, 0,  1}
            v2 := v3 { 1, 0,  1}
            v3 := v3 { 1, 0, -1}
            
            append(&triangles, Triangle{ a = v0, b = v2, c = v3, material = plane.material})
            append(&triangles, Triangle{ a = v0, b = v1, c = v2, material = plane.material})
            
            for &t in triangles {
                t.a.xz *= 4
                t.b.xz *= 4
                t.c.xz *= 4
            }
            
            tree_build(&plane.tree, triangles[:])
            plane.triangles = make_shallow_copy(triangles[:], context.allocator)
        }
        
        { // right
            clear(&triangles)
            plane := world_create_model(world)
            plane.material = 5
            plane.translation = {4,0,0}
            
            v0 := v3 {0, -1, -1}
            v1 := v3 {0, -1,  1}
            v2 := v3 {0,  1,  1}
            v3 := v3 {0,  1, -1}
            
            append(&triangles, Triangle{ a = v0, b = v2, c = v3, material = plane.material})
            append(&triangles, Triangle{ a = v0, b = v1, c = v2, material = plane.material})
            
            for &t in triangles {
                t.a.yz *= 4
                t.b.yz *= 4
                t.c.yz *= 4
            }
            
            tree_build(&plane.tree, triangles[:])
            plane.triangles = make_shallow_copy(triangles[:], context.allocator)
        }
        
        { // left
            clear(&triangles)
            plane := world_create_model(world)
            plane.material = 4
            plane.translation = {-4,0,0}
            
            v0 := v3 {0, -1, -1}
            v1 := v3 {0, -1,  1}
            v2 := v3 {0,  1,  1}
            v3 := v3 {0,  1, -1}
            
            append(&triangles, Triangle{ a = v0, b = v2, c = v3, material = plane.material})
            append(&triangles, Triangle{ a = v0, b = v1, c = v2, material = plane.material})
            
            for &t in triangles {
                t.a.yz *= 4
                t.b.yz *= 4
                t.c.yz *= 4
            }
            
            tree_build(&plane.tree, triangles[:])
            plane.triangles = make_shallow_copy(triangles[:], context.allocator)
        }
    }
    
    {
        clear(&triangles)
        // 0 =   3488 triangles
        // 1 =  19480 triangles, 5.5x 0
        // 2 = 145620 triangles, 7.5x 1
        
        teapot := world_create_model(world)
        teapot.material = 2
        
        load_teapot(&triangles, 0, teapot.material)
        
        tree_build(&teapot.tree, triangles[:])
        teapot.triangles = make_shallow_copy(triangles[:], context.allocator)
    }
}