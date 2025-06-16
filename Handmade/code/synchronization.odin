#+vet !unused-procedures
package main

import "base:intrinsics"
import "core:simd/x86"

////////////////////////////////////////////////
// Atomics

atomic_compare_exchange :: proc (dst: ^$T, old, new: T) -> (ok: b32, was: T) {
    ok_: bool
    was, ok_ = intrinsics.atomic_compare_exchange_strong(dst, old, new)
    ok = cast(b32) ok_
    return ok, was
}

atomic_compare_exchange_or_fail :: proc (dst: ^$T, old, new: T) -> (was: T) {
    ok: b32
    ok, was = atomic_compare_exchange(dst, old, new)
    assert(ok)
    return was
}


volatile_load      :: intrinsics.volatile_load
volatile_store     :: intrinsics.volatile_store
atomic_add         :: intrinsics.atomic_add
read_cycle_counter :: intrinsics.read_cycle_counter
atomic_exchange    :: intrinsics.atomic_exchange

// @todo(viktor): Is this correct? How can I validated this?
@(enable_target_feature="sse2,sse")
complete_previous_writes_before_future_writes :: proc "contextless" () {
    x86._mm_sfence()
    x86._mm_lfence()
}
@(enable_target_feature="sse2")
complete_previous_reads_before_future_reads :: proc "contextless" () {
    x86._mm_lfence()
}

////////////////////////////////////////////////

TicketMutex :: struct {
    ticket:  u64,
    serving: u64,
}

@(enable_target_feature="sse2")
begin_ticket_mutex :: proc (mutex: ^TicketMutex) {
    ticket := atomic_add(&mutex.ticket, 1)
    for ticket != volatile_load(&mutex.serving) {
        x86._mm_pause()
    }
}

end_ticket_mutex :: proc (mutex: ^TicketMutex) {
    atomic_add(&mutex.serving, 1)
}