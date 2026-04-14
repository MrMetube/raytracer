#+vet !unused-procedures
#+no-instrumentation
package main

SpallDisabled :: true

////////////////////////////////////////////////

import "core:prof/spall"
import "core:time"
import "core:fmt"

@(private="file") SpallBufferSize :: 3 * Gigabyte

@(private="file") spall_ctx: spall.Context
@(private="file", thread_local) spall_buffer: spall.Buffer
@(private="file", thread_local) backing_buffer: [] u8

////////////////////////////////////////////////
    
when false {
    @(instrumentation_enter)
    @(disabled=SpallDisabled)
    spall_enter :: proc "contextless" (proc_address, call_site_return_address: rawptr, loc := #caller_location) {
        spall._buffer_begin(&spall_ctx, &spall_buffer, "", "", loc)
    }
    
    @(instrumentation_exit)
    @(disabled=SpallDisabled)
    spall_exit :: proc "contextless" (proc_address, call_site_return_address: rawptr, loc := #caller_location) {
        spall._buffer_end(&spall_ctx, &spall_buffer)
    }
}

////////////////////////////////////////////////

@(deferred_none = spall_deinit)
@(disabled=SpallDisabled)
spall_init :: proc (thread_index: u32 = 0, output_name := "trace", location := #caller_location) {
    file_name := fmt.tprintf("./%v.spall", output_name)
    spall_ctx  = spall.context_create(file_name, 10 * time.Millisecond)
    
    err := make_by_pointer(&backing_buffer, SpallBufferSize); assert(err == nil)
    
    spall_buffer = spall.buffer_create(backing_buffer, thread_index)
}
@(deferred_out = spall_deinit_thread)
spall_init_thread :: proc (thread_index: u32, begin_deffered := true, location := #caller_location) -> bool {
    when SpallDisabled do return false
    
    assert(thread_index != 0)
    err := make_by_pointer(&backing_buffer, SpallBufferSize); assert(err == nil)
    
    spall_buffer = spall.buffer_create(backing_buffer, thread_index)
    if begin_deffered {
        spall_begin(location.procedure)
    }
    return begin_deffered
}

@(disabled=SpallDisabled)
spall_deinit :: proc () {
    spall.buffer_destroy(&spall_ctx, &spall_buffer)
    delete(backing_buffer)
    spall.context_destroy(&spall_ctx)
}
@(disabled=SpallDisabled)
spall_deinit_thread :: proc (began_deffered := false) {
    if began_deffered do spall_end()
    spall.buffer_destroy(&spall_ctx, &spall_buffer)
    delete(backing_buffer)
}

////////////////////////////////////////////////

@(disabled=SpallDisabled) @(deferred_none = spall_end)
spall_proc :: proc (location := #caller_location) { spall_begin(location.procedure, location) }

@(disabled=SpallDisabled) @(deferred_none = spall_end)
spall_scope :: proc (name: string, location := #caller_location) { spall_begin(name, location) }

@(disabled=SpallDisabled)
spall_hit :: proc (name: string, location := #caller_location) { spall_scope(name) }

@(disabled=SpallDisabled)
spall_begin :: proc (name: string, location := #caller_location) { spall._buffer_begin(&spall_ctx, &spall_buffer, name, "", location) }

@(disabled=SpallDisabled)
spall_end :: proc () { spall._buffer_end(&spall_ctx, &spall_buffer) }

@(disabled=SpallDisabled)
spall_flush :: proc () { spall.buffer_flush(&spall_ctx, &spall_buffer) }
