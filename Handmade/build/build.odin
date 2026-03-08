package build

native   :: true
optimize :: !false
pedantic :: false

import "core:os"

main :: proc () {
    init_build(run_from_data = true, wait = true)
    
    parse_run_and_debug_arguments()
    
    metaprogram: Metaprogram
    if !metaprogram_collect_files_and_parse_package(&metaprogram, "code", "main") do os.exit(1)
    if !check_printlikes(&metaprogram, "main") do os.exit(1)
    
    if begin_build(cmd, "code", "ray.exe", .Kill) {
        build_meander()
        
        build_optimizations(optimize)
        build_native(native)
        append(cmd, "-custom-attribute:printlike")
        build_pedantic(pedantic)
        if false {
            append(cmd, "-vet-packages:main -vet-unused-procedures")
        }
        
        end_build(cmd)
    }
    
    run_or_debug_according_to_args()
}