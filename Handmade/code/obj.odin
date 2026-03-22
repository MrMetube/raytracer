package main

import "core:os"
import "core:strings"
import "core:strconv"

load_obj :: proc (path: string, triangles: ^[dynamic] Triangle, triangle_normals: ^[dynamic] Normals) {
    clear(triangles)
    clear(triangle_normals)
    
    data, err := os.read_entire_file_from_path(path, context.temp_allocator)
    assert(err == nil)
    
    text := cast(string) data
    
    vertices := make([dynamic] v3, context.temp_allocator)
    normals  := make([dynamic] v3, context.temp_allocator)
    
    for len(text) != 0 {
        line := chop(&text, "\n")
        
        kind := chop(&line, " ")
        switch kind {
        case "#": continue
        case "o": continue
        case "v": // vertex
            v := parse_v3(&line)
            append(&vertices, v)
        case "vn": // vertex normal
            v := parse_v3(&line)
            append(&normals, v)
        case "s": // smooth shading
            // @todo(viktor): 
        case "f": // face
            v0 := chop(&line, " ")
            v1 := chop(&line, " ")
            v2 := chop(&line, " ")
            
            v1p := chop(&v0, "/")
            v1t := chop(&v0, "/"); assert(v1t == "")
            v1n := chop(&v0, "/")
            
            v2p := chop(&v1, "/")
            v2t := chop(&v1, "/"); assert(v2t == "")
            v2n := chop(&v1, "/")
            
            v3p := chop(&v2, "/")
            v3t := chop(&v2, "/"); assert(v3t == "")
            v3n := chop(&v2, "/")
            
            t: Triangle
            t.a = vertices[parse_i32(v1p)-1]
            t.b = vertices[parse_i32(v2p)-1]
            t.c = vertices[parse_i32(v3p)-1]
            append(triangles, t)
            
            n:[3] v3
            n[0] = normals[parse_i32(v1n)-1]
            n[1] = normals[parse_i32(v2n)-1]
            n[2] = normals[parse_i32(v3n)-1]
            append(triangle_normals, n)
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