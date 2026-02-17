package build

import "core:fmt"
import os "core:os/os2"
import "core:strings"
import win "core:sys/windows"

////////////////////////////////////////////////

// @todo(viktor): 
// think about command line beyond just running "name.exe" (run:xx debug:xx)
// readd metaprogram stuff
//     improve custom attributes flags "-custom-attribute:printlike"
// readd raddbg: find the newest version that can just stop with -ipc instead of killing
//               actually set the desired program to be run and not just the last active
// readd renderdoc, and maybe simplify it
// windows subsystem: "-subsystem:windows", "-subsystem:console"



cmd := &the_state.cmd
procs := &the_state.procs

////////////////////////////////////////////////
// Internal state

Procs :: [dynamic] os.Process
Cmd   :: [dynamic] string

the_state := struct {
    cmd: Cmd,
    procs: Procs,

    current_output: string,
    outputs: map [string] bool,

    wait_on_procs: bool,
    run_from_data: bool
} {
    // Defaults
}

Handle_Running_Exe :: enum {
    Skip,
    Abort, 
    Kill,
}

////////////////////////////////////////////////

@(deferred_none=deinit_build)
init_build :: proc (run_from_data := false, wait := false) {
    gitignore_path := "./build/.gitignore"
    if !os.exists(gitignore_path) {
        data := "*\n!*.odin\n"
        _ = os.write_entire_file(gitignore_path, transmute([] u8) data)
    }
    
    if run_from_data {
        make_directory_if_not_exists("./data")
        the_state.run_from_data = true
    }
    the_state.wait_on_procs = wait
}

deinit_build :: proc () {
    if len(cmd) != 0 {
        fmt.printf("INFO: cmd was not cleared: `%v`\n", strings.join(cmd[:], " "))
    }
    
    if the_state.wait_on_procs {
        procs_flush(procs)
    } else {
        procs_close(procs)
    }
}

////////////////////////////////////////////////

begin_build :: proc (cmd: ^Cmd, package_directory: string, output_name: string, handling: Handle_Running_Exe = .Skip) -> bool {
    // @todo(viktor): check that we do not nest, or make this stateless(see current_output)
    result: bool
    
    if handle_running_exe_gracefully(output_name, handling) {
        os.change_directory("./build")
        
        append(cmd, "odin", "build")
        append(cmd, fmt.tprintf("../%v", package_directory))
        append(cmd, fmt.tprintf("-out:%v", output_name))
        result = true
        
        the_state.outputs[output_name] = true
        the_state.current_output = output_name
    }
    
    return result
}

build_meander :: proc (debug := "-debug", Cast := "-vet-cast", shadowing := "-vet-shadowing") {
    append(cmd, debug, Cast, shadowing)
}

build_optimizations :: proc (optimize: bool, optimized := "-o:speed", unoptimized := "-o:none") {
    append(cmd, optimize ? optimized : unoptimized)
}

build_native :: proc (native: bool, target := "-target:windows_amd64", microarch := "-microarch:native") {
    if native {
        append(cmd, target, microarch)
    }
}

build_pedantic :: proc (pedantic: bool, imports := "-vet-unused-imports", semicolon := "-vet-semicolon", variables := "-vet-unused-variables", style := "-vet-style") {
    if pedantic {
        append(cmd, imports, semicolon, variables, style)
    }
}

end_build :: proc (cmd: ^Cmd) {
    if run_command(cmd) {
        fmt.printf("  Build successful %v.\n", the_state.current_output)
    } else {
        the_state.outputs[the_state.current_output] = false
    }
    
    os.change_directory("..")
    the_state.current_output = ""
}

run_build_according_to_args :: proc () {
    for arg in os.args[1:] {
        if success, found := the_state.outputs[arg]; found {
            if success {
                if the_state.run_from_data {
                    os.change_directory("./data")
                }
            
                append(cmd, fmt.tprintf("../build/%v", arg))
                run_command(cmd, async = procs)
            } else {
                // @todo(viktor): notify user?
            }
        } else {
            // @todo(viktor): notify user?
        }
    }
}

////////////////////////////////////////////////

is_running :: proc (exe_name: string) -> (running: bool, pid: u32) {
    snapshot := win.CreateToolhelp32Snapshot(win.TH32CS_SNAPALL, 0)
    assert(snapshot != win.INVALID_HANDLE_VALUE, "could not take a snapshot of the running programms")
    defer win.CloseHandle(snapshot)
    
    process_entry := win.PROCESSENTRY32W{ dwSize = size_of(win.PROCESSENTRY32W)}
    
    if win.Process32FirstW(snapshot, &process_entry) {
        for {
            test_name, err := win.utf16_to_utf8(process_entry.szExeFile[:])
            assert(err == nil)
            if exe_name == test_name {
                return true, process_entry.th32ProcessID
            }
            if !win.Process32NextW(snapshot, &process_entry) {
                break
            }
        }
    }
    
    return false, 0
}

handle_running_exe_gracefully :: proc (exe_name: string, handling: Handle_Running_Exe) -> bool {
    for {
        ok, pid := is_running(exe_name)
        if ok {
            fmt.printf("INFO: Tried to build '%v', but the program is already running.\n", exe_name)
            switch handling {
            case .Skip:
                fmt.printf("  Skipping build.\n", exe_name)
                ok = false
                
            case .Abort: 
                fmt.printf("  Aborting build!\n", exe_name)
                os.exit(0)
                
            case .Kill: 
                fmt.printf("  Killing running instance.\n")
                
                process, err := os.process_open(auto_cast pid)
                if err != nil {
                    fmt.printf("  Failed to open '%v': %v\n", exe_name, err)
                    ok = false
                } else {
                    err = os.process_kill(process)
                    if err != nil {
                        fmt.printf("  Failed to kill '%v': %v\n", exe_name, err)
                        ok = false
                    }
                }
            }
        }
        
        if !ok do break
    }
    
    return true
}

procs_flush :: proc (procs: ^Procs) {
    for &p in procs {
        _, _ = os.process_wait(p)
    }
    
    clear(procs)
}

procs_close :: proc (procs: ^Procs) {
    for &p in procs {
        _ = os.process_close(p)
    }
    
    clear(procs)
}

////////////////////////////////////////////////

make_directory_if_not_exists :: proc (path: string) -> (result: b32) {
    if !os.exists(path) {
        os.make_directory(path)
        result = true
    }
    return result
}

////////////////////////////////////////////////

// @todo(viktor): Find where the version where I could also pass os.stdin/stdout here
run_command :: proc (cmd: ^Cmd, or_exit := true, keep := false, stdout: ^string = nil, stderr: ^string = nil, async: ^Procs = nil) -> (success: bool) {
    fmt.printf("CMD: %v\n", strings.join(cmd[:], " "))
    
    process_description := os.Process_Desc { command = cmd[:] }
    process: os.Process
    state:   os.Process_State
	output:  [] byte
	error:   [] byte
    err2:    os.Error
    if async == nil {
        state, output, error, err2 = os.process_exec(process_description, context.allocator)
    } else {
        process, err2 = os.process_start(process_description)
        append(async, process)
    }
    
    if err2 != nil {
        fmt.printf("ERROR: Failed to run command: %v\n", err2)
        return false
    }
    
    if async == nil {
        if output != nil {
            if stdout != nil do stdout ^= cast(string) output
            else do fmt.println(cast(string) output)
        }
        
        if error != nil {
            if stderr != nil do stderr ^= cast(string) error
            else do fmt.println(cast(string) error)
            
            if or_exit do os.exit(state.exit_code)
        }
        
        if or_exit && !state.success do os.exit(state.exit_code)
        
        success = state.success
    } else {
        success = true
    }
    
    if !keep do clear(cmd)
    
    return success
}
