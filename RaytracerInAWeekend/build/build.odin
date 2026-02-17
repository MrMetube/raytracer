package build

native   :: true
optimize :: false
pedantic :: false

main :: proc () {
    init_build(run_from_data = true)
    
    if begin_build(cmd, "code", "tracer.exe", .Kill) {
        build_meander()
        
        build_optimizations(optimize)
        build_native(native)
        build_pedantic(pedantic)
        
        end_build(cmd)
    }
    
    run_build_according_to_args()
}