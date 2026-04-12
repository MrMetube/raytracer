package main

import "core:os"
import "core:strings"
import "core:strconv"
import stbi "vendor:stb/image"

load_obj :: proc (textures: ^map[string] Image, dir, filename: string, triangles: ^[dynamic] Triangle, triangle_normals: ^[dynamic] Normals, triangle_uvs: ^[dynamic] UVs, texture: ^Image, flip_yz := false) {
    clear(triangles)
    clear(triangle_normals)
    clear(triangle_uvs)
    texture^ = {}
    
    path, path_err := os.join_path({dir, filename}, context.temp_allocator)
    assert(path_err == nil)
    
    data, err := os.read_entire_file_from_path(path, context.temp_allocator)
    assert(err == nil)
    
    text := cast(string) data
    
    vertices := make([dynamic] v3, context.temp_allocator)
    normals  := make([dynamic] v3, context.temp_allocator)
    uvs      := make([dynamic] v2, context.temp_allocator)
    
    for len(text) != 0 {
        line := chop(&text, "\n")
        
        kind := chop(&line, " ")
        switch kind {
        case "#": continue // comment
        case "o": continue // object
        case "g": continue // group
        
        // @todo(viktor): 
        case "s": // smooth shading
        
        case "mtllib":
            load_mtl(textures, dir, line)
            
        case "usemtl":
            // @todo(viktor): handle different groups using different materials
            texture^ = textures[line]
            
        case "v": // vertex
            v := parse_v3(&line)
            if flip_yz do v.yz = {-v.z, v.y}
            append(&vertices, v)
            
        case "vn": // vertex normal
            v := parse_v3(&line)
            if flip_yz do v.yz = {-v.z, v.y}
            append(&normals, v)
            
        case "vt": // texture uv
            v := parse_v2(&line)
            append(&uvs, v)
        
        case "f": // face
            v0 := chop(&line, " ")
            v1 := chop(&line, " ")
            v2 := chop(&line, " ")
            
            v1p := chop(&v0, "/")
            v1t := chop(&v0, "/")
            v1n := chop(&v0, "/")
            
            v2p := chop(&v1, "/")
            v2t := chop(&v1, "/")
            v2n := chop(&v1, "/")
            
            v3p := chop(&v2, "/")
            v3t := chop(&v2, "/")
            v3n := chop(&v2, "/")
            
            t: Triangle
            t.a  = vertices[parse_i32(v1p)-1]
            t.ab = vertices[parse_i32(v2p)-1] - t.a
            t.ac = vertices[parse_i32(v3p)-1] - t.a
            append(triangles, t)
            
            n: Normals
            n[0] = normals[parse_i32(v1n)-1]
            n[1] = normals[parse_i32(v2n)-1]
            n[2] = normals[parse_i32(v3n)-1]
            append(triangle_normals, n)
            
            uv: UVs
            if v1t != "" do uv[0] = uvs[parse_i32(v1t)-1]
            if v2t != "" do uv[1] = uvs[parse_i32(v2t)-1]
            if v3t != "" do uv[2] = uvs[parse_i32(v3t)-1]
            append(triangle_uvs, uv)
        }
    }
    
    print("Loaded model '%v' with %v triangles\n", path, len(triangles))
    
    // @note(viktor): add a nil value, so we can always load something if needed
    if len(triangle_normals) == 0 {
        append(triangle_normals, Normals{})
    }
    
    if len(triangle_uvs) == 0 {
        append(triangle_uvs, UVs{})
    }
    
    assert(len(triangles) != 0)
    
}

load_mtl :: proc (textures: ^map[string] Image, dir: string, file: string) {
    path, path_err := os.join_path({dir, file}, context.temp_allocator)
    assert(path_err == nil)
    
    file_data, err := os.read_entire_file_from_path(path, context.temp_allocator)
    assert(err == nil)
    
    text := cast(string) file_data
    
    current: ^Image
    // @todo(viktor): handle files with multiple materials and textures and also store the tint
    print("parsing %v\n", path)
    for len(text) != 0 {
        line := chop(&text, "\n")
        
        kind := chop(&line, " ")
        switch kind {
        case "#": continue
        case "Kd": print("mtl: unhandled %v\n", kind)
        case "newmtl":
            current = map_insert(textures, line, Image{})
            
        case "map_Kd":
            assert(strings.ends_with(line, ".png"))
            if line not_in textures {
                texture_path, t_err := os.join_path({dir, line}, context.temp_allocator)
                assert(t_err == nil)
                
                cpath := ctprint("%v", texture_path)
                
                x, y, channels: i32
                
                stbi.info(cpath, &x, &y, &channels)
                assert(channels == 4)
                data := make([] Color, x * y, context.allocator)
                
                image_data := stbi.load(cpath, &x, &y, &channels, 4)
                defer stbi.image_free(image_data)
                
                for py in 0..<y {
                    for px in 0..<x {
                        i := py * x + px
                        c := cast(^Color) &image_data[i*4]
                        j := (y-1-py) * x + px
                        data[j] = c^
                    }
                }
                
                current^ = {
                    width  = x,
                    height = y,
                    data   = data,
                }
            }
        }
    }
}


parse_v3 :: proc (line: ^string) -> v3 {
    sx := chop(line, " ")
    sy := chop(line, " ")
    sz := chop(line, " ")
    
    v: v3
    v.x = parse_f32(sx)
    v.y = parse_f32(sy)
    v.z = parse_f32(sz)
    
    return v
}

parse_v2 :: proc (line: ^string) -> v2 {
    sx := chop(line, " ")
    sy := chop(line, " ")
    
    v: v2
    v.x = parse_f32(sx)
    v.y = parse_f32(sy)
    
    return v
}

parse_f32 :: proc(str: string) -> f32 {
    result, ok := strconv.parse_f32(str)
    assert(ok)
    return result
}

parse_i32 :: proc(str: string) -> i32 {
    result, ok := strconv.parse_int(str)
    assert(ok)
    return cast(i32) result
}

chop :: proc (str: ^string, sep: string) -> string {
    result: string
    result, _, str^ = strings.partition(str^, sep)
    return result
}