package main

import "core:os"
import "core:strings"
import "core:strconv"

load_teapot :: proc (triangles: ^[dynamic] Triangle, utah: u32, material: u32) {
    data, err := os.read_entire_file_from_path(tprint("./teapot_bezier%.tris", utah), context.temp_allocator)
    assert(err == nil)
    
    text := cast(string) data
    count_text: string
    count_text, _, text = strings.partition(text, "\n")
    
    count, count_ok := strconv.parse_int(count_text)
    assert(count_ok)
    
    for _ in 0..<count {
        vs: [3] v3
        
        for i in 0..<3 {
            
            // @note(viktor): the file is specified with y = up, but we want z = up
            line := chop(&text, "\n")
            vs[i].x = parse_f32(chop(&line, " "))
            vs[i].z = parse_f32(chop(&line, " "))
            vs[i].y = parse_f32(line)
        }
        chop(&text, "\n")
        
        append(triangles, Triangle{ a = vs[0], b = vs[1], c = vs[2], material = material})
    }
}

parse_f32 :: proc(str: string) -> f32 {
    result, ok := strconv.parse_f32(str)
    assert(ok)
    return result
}

chop :: proc (str: ^string, sep: string) -> string {
    result: string
    result, _, str^ = strings.partition(str^, sep)
    return result
}