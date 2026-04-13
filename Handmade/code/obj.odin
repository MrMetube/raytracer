package main

import "core:os"
import "core:strings"
import "core:strconv"
import stbi "vendor:stb/image"

load_obj :: proc (loader: ^Model_Loader, dir, filename: string, flip_yz := false) {
    clear(&loader.triangles)
    clear(&loader.normals)
    clear(&loader.uvs)
    
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
        
        case "mtllib":
            load_mtl(nil, dir, line)
            
        case:
            print("obj: unhandled %v\n", kind)
            
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
            append(&loader.triangles, t)
            
            n: Normals
            n[0] = normals[parse_i32(v1n)-1]
            n[1] = normals[parse_i32(v2n)-1]
            n[2] = normals[parse_i32(v3n)-1]
            append(&loader.normals, n)
            
            uv: UVs
            if v1t != "" do uv[0] = uvs[parse_i32(v1t)-1]
            if v2t != "" do uv[1] = uvs[parse_i32(v2t)-1]
            if v3t != "" do uv[2] = uvs[parse_i32(v3t)-1]
            append(&loader.uvs, uv)
        }
    }
    
    print("Loaded model '%v' with %v triangles\n", path, len(&loader.triangles))
    
    // @note(viktor): add a nil value, so we can always load something if needed
    if len(&loader.normals) == 0 {
        append(&loader.normals, Normals{})
    }
    
    if len(&loader.uvs) == 0 {
        append(&loader.uvs, UVs{})
    }
    
    assert(len(&loader.triangles) != 0)
}

load_mtl :: proc (textures: ^map[string] Image, dir: string, file: string) {
    path, path_err := os.join_path({dir, file}, context.temp_allocator)
    assert(path_err == nil)
    
    file_data, err := os.read_entire_file_from_path(path, context.temp_allocator)
    assert(err == nil)
    
    text := cast(string) file_data
    
    current: ^Image
    for len(text) != 0 {
        line := chop(&text, "\n")
        
        kind := chop(&line, " ")
        switch kind {
        case "#": continue // comment
        case: print("mtl: unhandled %v\n", kind)
        
        case "newmtl":
            if false {
                current = map_insert(textures, line, Image{})
            }
            
        case "map_Kd":
            if false {
                assert(strings.ends_with(line, ".png"))
                if line not_in textures {
                    texture_path, t_err := os.join_path({dir, line}, context.temp_allocator)
                    assert(t_err == nil)
                    current^ = load_texture_from_png(texture_path)
                }
            }
        }
    }
}

load_texture_from_png :: proc (path: string) -> Image {
    cpath := ctprint("%v", path)
    
    width, height, channels: i32
    stbi.info(cpath, &width, &height, &channels)
    assert(channels == 4)
    
    data := make([] Color, width * height, context.allocator)
    
    bytes := stbi.load(cpath, &width, &height, &channels, 4)
    defer stbi.image_free(bytes)
    image := (cast([^] Color) &bytes[0])[:width * height]
    
    // @note(viktor): flip the y-axis to be +y = up
    for y in 0..<height {
        for x in 0..<width {
            i := x +           y  * width
            j := x + (height-1-y) * width
            data[j] = image[i]
        }
    }
    
    result: Image
    result.width  = width
    result.height = height
    result.data   = data
    
    return result
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