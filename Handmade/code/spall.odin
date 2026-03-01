#+vet !unused-procedures
#+no-instrumentation
package main

import "core:prof/spall"
import "core:time"

SpallDisabled   :: true
SpallBufferSize :: 1 * Gigabyte

spall_ctx: spall.Context
@(thread_local) spall_buffer: spall.Buffer
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

@(deferred_none = delete_spall)
@(disabled=SpallDisabled)
init_spall :: proc (thread_index: u32 = 0, location := #caller_location) {
    spall_ctx = spall.context_create("trace.spall", 10 * time.Millisecond)
    err := make_by_pointer(&backing_buffer, SpallBufferSize)
    assert(err == nil)
    spall_buffer = spall.buffer_create(backing_buffer, thread_index)
}
@(deferred_out = delete_spall_thread)
init_spall_thread :: proc (thread_index := cast(u32) context.user_index, begin_deffered := true, location := #caller_location) -> bool {
    when !SpallDisabled {
        assert(thread_index != 0)
        err := make_by_pointer(&backing_buffer, SpallBufferSize)
        assert(err == nil)
        spall_buffer = spall.buffer_create(backing_buffer, thread_index)
        if begin_deffered {
            spall_begin(location.procedure)
        }
        return begin_deffered
    } else {
        return false
    }
}

@(disabled=SpallDisabled)
delete_spall :: proc () {
    spall.buffer_destroy(&spall_ctx, &spall_buffer)
    delete(backing_buffer)
    spall.context_destroy(&spall_ctx)
}
@(disabled=SpallDisabled)
delete_spall_thread :: proc (began_deffered := false) {
    if began_deffered do spall_end()
    spall.buffer_destroy(&spall_ctx, &spall_buffer)
    delete(backing_buffer)
}

////////////////////////////////////////////////

@(deferred_none = spall_end)
@(disabled=SpallDisabled)
spall_proc :: proc (name: string = "", location := #caller_location) {
    spall_begin(name == "" ? location.procedure : name, location)
}

@(deferred_none = spall_end)
@(disabled=SpallDisabled)
spall_scope :: proc (name: string, location := #caller_location) {
    spall_begin(name, location)
}

@(disabled=SpallDisabled)
spall_hit :: proc (name: string, location := #caller_location) {
    spall_begin(name)
    spall_end()
}

@(disabled=SpallDisabled)
spall_begin :: proc (name: string, location := #caller_location) {
	spall._buffer_begin(&spall_ctx, &spall_buffer, name, "", location)
}

@(disabled=SpallDisabled)
spall_end :: proc () {
	spall._buffer_end(&spall_ctx, &spall_buffer)
}

@(disabled=SpallDisabled)
spall_flush :: proc () {
    spall.buffer_flush(&spall_ctx, &spall_buffer)
}
