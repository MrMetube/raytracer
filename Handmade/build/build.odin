package build

import os "core:os/os2"

native   :: true
optimize :: !false
pedantic :: false

main :: proc () {
    init_build(run_from_data = true, wait = true)
    
    parse_run_and_debug_arguments()
    
    if !check_printlikes() do os.exit(1)
    
    if begin_build(cmd, "code", "ray.exe", .Kill) {
        build_meander()
        
        build_optimizations(optimize)
        build_native(native)
        append(cmd, "-custom-attribute:printlike")
        build_pedantic(pedantic)
        
        end_build(cmd)
    }
    
    run_or_debug_according_to_args()
}