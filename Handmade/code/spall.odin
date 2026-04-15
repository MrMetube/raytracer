#+vet !unused-procedures
#+no-instrumentation
package main

Spall_Disabled   :: true
Spall_Instrument :: false

////////////////////////////////////////////////

import "core:prof/spall"
import "core:time"
import "core:fmt"

@(private="file") SpallBufferSize :: 3 * Gigabyte

@(private="file") spall_context: spall.Context
@(private="file", thread_local) spall_buffer: spall.Buffer
@(private="file", thread_local) backing_buffer: [] u8

////////////////////////////////////////////////
    
when Spall_Instrument {
    @(instrumentation_enter)
    @(disabled=Spall_Disabled)
    spall_enter :: proc "contextless" (proc_address, call_site_return_address: rawptr, loc := #caller_location) {
        spall._buffer_begin(&spall_context, &spall_buffer, "", "", loc)
    }
    
    @(instrumentation_exit)
    @(disabled=Spall_Disabled)
    spall_exit :: proc "contextless" (proc_address, call_site_return_address: rawptr, loc := #caller_location) {
        spall._buffer_end(&spall_context, &spall_buffer)
    }
}

////////////////////////////////////////////////

@(deferred_none = spall_deinit)
@(disabled=Spall_Disabled)
spall_init :: proc (thread_index: u32 = 0, output_name := "trace") {
    file_name := fmt.tprintf("./%v.spall", output_name)
    spall_context  = spall.context_create(file_name, 10 * time.Millisecond)
    
    spall_init_thread(thread_index)
}

@(disabled = Spall_Disabled)
spall_init_thread :: proc (thread_index: u32) {
    allocation_error := make_by_pointer(&backing_buffer, SpallBufferSize)
    assert(allocation_error == nil)
    
    spall_buffer = spall.buffer_create(backing_buffer, thread_index)   
}

@(disabled=Spall_Disabled)
spall_deinit :: proc () {
    spall_deinit_thread()
    
    spall.context_destroy(&spall_context)
}

@(disabled=Spall_Disabled)
spall_deinit_thread :: proc () {
    spall.buffer_destroy(&spall_context, &spall_buffer)
    delete(backing_buffer)
}

////////////////////////////////////////////////

@(deferred_none = spall_end)
@(disabled=Spall_Disabled) spall_proc  :: proc (location := #caller_location) { spall_begin(location.procedure, location) }
@(deferred_none = spall_end)
@(disabled=Spall_Disabled) spall_scope :: proc (name: string, location := #caller_location) { spall_begin(name, location) }
@(disabled=Spall_Disabled) spall_begin :: proc (name: string, location := #caller_location) { spall._buffer_begin(&spall_context, &spall_buffer, name, "", location) }
@(disabled=Spall_Disabled) spall_end   :: proc () { spall._buffer_end(&spall_context, &spall_buffer) }
@(disabled=Spall_Disabled) spall_flush :: proc () { spall.buffer_flush(&spall_context, &spall_buffer) }
