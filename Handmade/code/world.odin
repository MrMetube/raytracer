package main

import "core:fmt"
import "core:time"

// @volatile also update the render's world copying
World :: struct {
    models: [dynamic] Model,
    
    materials: [dynamic] Material,
    material_names: [] string,
    all_brdf_values: [dynamic] v3,
}

Model :: struct {
    triangles: [dynamic] Triangle,
    tree:      [] Tree_Node,
    translation: v3,
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
    
    world.material_names = make_slice(context.allocator, [] string, len(world.materials))
    
    world_load_brdf(world, 0, "nil")
    world_load_brdf(world, 1, "gray-plastic")
    world_load_brdf(world, 2, "brass")
    world_load_brdf(world, 3, "gold-paint")
    world_load_brdf(world, 4, "green-latex")
    world_load_brdf(world, 5, "purple-paint")
    world_load_brdf(world, 6, "white-marble")
}

world_load_brdf :: proc (world: ^World, material_index: u32, name: string) {
    load_brdf_merl(tprint("./BRDFDatabase/brdfs/%.binary", name), &world.materials[material_index].brdf, &world.all_brdf_values)
    world.material_names[material_index] = name
}

world_create_model :: proc (world: ^World) -> ^Model {
    model_index := len(world.models)
    append_nothing(&world.models)
    result := &world.models[model_index]
    return result
}

////////////////////////////////////////////////

teapot_scene :: proc (world: ^World) -> (^Model, time.Duration) {
    // @todo(viktor): fixed Buffer of models and return indices
    reserve(&world.models, 128)
    
    // @cleanup 
    { // light
        plane := world_create_model(world)
        
        v0 := v3 {-1, -1, 0}
        v1 := v3 {-1,  1, 0}
        v2 := v3 { 1,  1, 0}
        v3 := v3 { 1, -1, 0}
        
        append(&plane.triangles, Triangle{ a = v0, b = v2, c = v3, material = 3})
        append(&plane.triangles, Triangle{ a = v0, b = v1, c = v2, material = 3})
        
        plane.translation = {0,0,4}
        tree_build(&plane.tree, plane.triangles)
    }
    { // ground
        plane := world_create_model(world)
        
        v0 := v3 {-1, -1, 0}
        v1 := v3 {-1,  1, 0}
        v2 := v3 { 1,  1, 0}
        v3 := v3 { 1, -1, 0}
        
        append(&plane.triangles, Triangle{ a = v0, b = v2, c = v3, material = 1})
        append(&plane.triangles, Triangle{ a = v0, b = v1, c = v2, material = 1})
        
        for &t in plane.triangles {
            t.a.xy *= 500
            t.b.xy *= 500
            t.c.xy *= 500
        }
        
        tree_build(&plane.tree, plane.triangles)
    }
    if !false {
        { // top
            plane := world_create_model(world)
            
            v0 := v3 {-1, -1, 0}
            v1 := v3 {-1,  1, 0}
            v2 := v3 { 1,  1, 0}
            v3 := v3 { 1, -1, 0}
            
            append(&plane.triangles, Triangle{ a = v0, b = v2, c = v3, material = 6})
            append(&plane.triangles, Triangle{ a = v0, b = v1, c = v2, material = 6})
            
            plane.translation = {0,0,4}
            for &t in plane.triangles {
                t.a.xy *= 4
                t.b.xy *= 4
                t.c.xy *= 4
            }
            
            tree_build(&plane.tree, plane.triangles)
        }
        { // back
            plane := world_create_model(world)
            
            v0 := v3 {-1, 0, -1}
            v1 := v3 {-1, 0,  1}
            v2 := v3 { 1, 0,  1}
            v3 := v3 { 1, 0, -1}
            
            append(&plane.triangles, Triangle{ a = v0, b = v2, c = v3, material = 6})
            append(&plane.triangles, Triangle{ a = v0, b = v1, c = v2, material = 6})
            
            plane.translation = {0,4,0}
            for &t in plane.triangles {
                t.a.xz *= 4
                t.b.xz *= 4
                t.c.xz *= 4
            }
            
            tree_build(&plane.tree, plane.triangles)
        }
        { // right
            plane := world_create_model(world)
            
            v0 := v3 {0, -1, -1}
            v1 := v3 {0, -1,  1}
            v2 := v3 {0,  1,  1}
            v3 := v3 {0,  1, -1}
            
            append(&plane.triangles, Triangle{ a = v0, b = v2, c = v3, material = 5})
            append(&plane.triangles, Triangle{ a = v0, b = v1, c = v2, material = 5})
            
            plane.translation = {4,0,0}
            for &t in plane.triangles {
                t.a.yz *= 4
                t.b.yz *= 4
                t.c.yz *= 4
            }
            
            tree_build(&plane.tree, plane.triangles)
        }
        { // left
            plane := world_create_model(world)
            
            v0 := v3 {0, -1, -1}
            v1 := v3 {0, -1,  1}
            v2 := v3 {0,  1,  1}
            v3 := v3 {0,  1, -1}
            
            append(&plane.triangles, Triangle{ a = v0, b = v2, c = v3, material = 4})
            append(&plane.triangles, Triangle{ a = v0, b = v1, c = v2, material = 4})
            
            plane.translation = {-4,0,0}
            for &t in plane.triangles {
                t.a.yz *= 4
                t.b.yz *= 4
                t.c.yz *= 4
            }
            
            tree_build(&plane.tree, plane.triangles)
        }
    }
    
    
    
    // 0 =   3488 triangles
    // 1 =  19480 triangles, 5.5x 0
    // 2 = 145620 triangles, 7.5x 1
    
    teapot := world_create_model(world)
    load_teapot(&teapot.triangles, 0, 2)
    
    start := time.now()
    tree_build(&teapot.tree, teapot.triangles)
    build_time := time.since(start)
    print("build time %\n", fmt.tprint(build_time))
    
    return teapot, build_time
}