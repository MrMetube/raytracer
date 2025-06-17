package build

import "base:intrinsics"

import "core:fmt"
import "core:log"
import "core:os"
import "core:os/os2"
import "core:strings"
import "core:time"

import win "core:sys/windows"

optimizations := !false ? ` -o:speed ` : ` -o:none `
Pedantic :: false

flags    :: ` -error-pos-style:unix -vet-cast -vet-shadowing -vet-semicolon  -ignore-vs-search -use-single-module `
debug    :: ` -debug `
pedantic :: ` -warnings-as-errors -vet-unused-imports -vet-unused-variables -vet-style -vet-packages:main -vet-unused-procedures` 
commoner :: ` -custom-attribute:printlike `

src_path :: `.\build\`   
exe_path :: `.\build\build.exe`

build_dir :: `.\build\`
data_dir :: `.\data\`

main :: proc() {
    context.allocator = context.temp_allocator
    context.logger = log.create_console_logger(opt = {.Level, .Terminal_Color})
    context.logger.lowest_level = .Info
    
    go_rebuild_yourself()

    make_directory_if_not_exists(data_dir)
    
    err := os.set_current_directory(build_dir)
    assert(err == nil)
    
    if !check_printlikes() do os.exit(1)
    
    run_command_or_exit(`C:\Odin\odin.exe`, `odin build ..\code -out:.\`, "debug.exe" , flags, debug, optimizations, commoner , (pedantic when Pedantic else ""))
    
}



















Error :: union { os2.Error, os.Error }

go_rebuild_yourself :: proc() -> Error {
    log.Level_Headers = { 0..<50 = "" }
    
    if strings.ends_with(os.get_current_directory(), "build") {
        os.set_current_directory("..") or_return
    }
    
    gitignore := fmt.tprint(build_dir, `\.gitignore`, sep="")
    if !os.exists(gitignore) {
        contents := "*\n!*.odin"
        os.write_entire_file(gitignore, transmute([]u8) contents)
    }
    
    needs_rebuild := false
    build_exe_info, err := os.stat(exe_path)
    if err != nil {
        needs_rebuild = true
    }
    
    if !needs_rebuild {
        src_dir := os2.read_all_directory_by_path(src_path, context.allocator) or_return
        for file in src_dir {
            if strings.ends_with(file.name, ".odin") {
                if time.diff(file.modification_time, build_exe_info.modification_time) < 0 {
                    needs_rebuild = true
                    break
                }
            }
        }
    }
    
    if needs_rebuild {
        log.info("Rebuilding!")
        
        pdb_path, _ := strings.replace_all(exe_path, ".exe", ".pdb")
        remove_if_exists(pdb_path)
        
        old_path := fmt.tprintf("%s-old", exe_path)
        os.rename(exe_path, old_path) or_return
        
        if !run_command(`C:\Odin\odin.exe`, "odin run ", src_path, " -out:", exe_path, debug, pedantic) {
            os.rename(old_path, exe_path) or_return
        }
        
        remove_if_exists(old_path)
        
        os.exit(0)
    }
    
    return nil
}

remove_if_exists :: proc(path: string) {
    if os.exists(path) do os.remove(path)
}

delete_all_like :: proc(pattern: string) {
    find_data := win.WIN32_FIND_DATAW{}

    handle := win.FindFirstFileW(win.utf8_to_wstring(pattern), &find_data)
    if handle == win.INVALID_HANDLE_VALUE do return
    defer win.FindClose(handle)
    
    for {
        file_name, err := win.utf16_to_utf8(find_data.cFileName[:])
        assert(err == nil)
        file_path := fmt.tprintf(`.\%v`, file_name)
        
        os.remove(file_path)
        if !win.FindNextFileW(handle, &find_data){
            break 
        }
    }
}

is_running :: proc(exe_name: string) -> (running: b32) {
    snapshot := win.CreateToolhelp32Snapshot(win.TH32CS_SNAPALL, 0)
    log.assert(snapshot != win.INVALID_HANDLE_VALUE, "could not take a snapshot of the running programms")
    defer win.CloseHandle(snapshot)

    process_entry := win.PROCESSENTRY32W{ dwSize = size_of(win.PROCESSENTRY32W)}

    if win.Process32FirstW(snapshot, &process_entry) {
        for {
            test_name, err := win.utf16_to_utf8(process_entry.szExeFile[:])
            log.assert(err == nil)
            if exe_name == test_name {
                return true
            }
            if !win.Process32NextW(snapshot, &process_entry) {
                break
            }
        }
    }

    return false
}

run_command_or_exit :: proc(program: string, args: ..string) {
    if !run_command(program, ..args) {
        os.exit(1)
    }
}

run_command :: proc(program: string, args: ..string) -> (success: b32) {
    startup_info := win.STARTUPINFOW{ cb = size_of(win.STARTUPINFOW) }
    process_info := win.PROCESS_INFORMATION{}
    
    
    working_directory := win.utf8_to_wstring(os.get_current_directory())
    joined_args := strings.join(args, "")
    
    log.info("CMD:", program, " - ", joined_args)
    
    if win.CreateProcessW(
        win.utf8_to_wstring(program), 
        win.utf8_to_wstring(joined_args), 
        nil, nil, 
        win.TRUE, 0, 
        nil, working_directory, 
        &startup_info, &process_info,
    ) {
        
        win.WaitForSingleObject(process_info.hProcess, win.INFINITE)
        
        exit_code: win.DWORD
        win.GetExitCodeProcess(process_info.hProcess, &exit_code)
        success = exit_code == 0
        
        win.CloseHandle(process_info.hProcess)
        win.CloseHandle(process_info.hThread)
    } else {
        log.errorf("Failed to execute the command: %s %s with error %s", program, args, os.error_string(os.get_last_error()))
        success = false
    }
    return
}

make_directory_if_not_exists :: proc(path: string) -> (result: b32) {
    if !os.exists(path) {
        os.make_directory(path)
        result = true
    }
    return result
}

random_number :: proc() -> (result: u32) {
    return cast(u32) intrinsics.read_cycle_counter() % 255
}