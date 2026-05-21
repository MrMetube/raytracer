#+vet !unused-procedures
package main

import "base:runtime"
import "core:thread"
import "core:sync"
import win "core:sys/windows"

WorkQueueCallback :: #type proc (data: pmm)

WorkQueue :: struct {
    name: string,
    
    semaphore: sync.Sema,
    
    completion_goal:  u32,
    completion_count: u32,
     
    next_entry_to_write: u32,
    next_entry_to_read:  u32,
    
    entries: [4096] WorkQueueEntry,
    
    closed: bool,
    thread_count: u32,
    opened_thread_count: u32,
    closed_thread_count: u32,
}

WorkQueueEntry :: struct {
    callback: WorkQueueCallback,
    data:     pmm,
}

CreateThreadInfo :: struct {
    queue: ^WorkQueue,
    index: u32,
    name_index: u32,
}

@(private="file") created_thread_count: u32 = 1
@(private="file") infos: [1024] CreateThreadInfo

init_work_queue :: proc (queue: ^WorkQueue, name: string, count: u32) {
    queue.name         = name
    queue.thread_count = count
    
    for &info, index in infos[created_thread_count:][:count] {
        info.queue = queue
        info.index = created_thread_count
        info.name_index = 1 + auto_cast index
        created_thread_count += 1
        
        thread.create_and_start_with_data(&info, worker_thread)
    }
}

close_work_queue_and_wait_for_threads :: proc (queue: ^WorkQueue) {
    queue.closed = true
    
    complete_previous_writes_before_future_writes()
    
    for queue.closed_thread_count != queue.opened_thread_count {
        sync.sema_post(&queue.semaphore, 1)
    }
}

////////////////////////////////////////////////

enqueue_work_or_do_immediatly :: proc { enqueue_work_or_do_immediatly_t, enqueue_work_or_do_immediatly_any }
enqueue_work_or_do_immediatly_t   :: proc (queue: ^WorkQueue, callback: proc (data: ^$T),  data: ^T)  { enqueue_work_or_do_immediatly_any(queue, auto_cast callback, data) }
enqueue_work_or_do_immediatly_any :: proc (queue: ^WorkQueue, callback: WorkQueueCallback, data: pmm) {
    if queue != nil {
        enqueue_work(queue, callback, data)
    } else {
        callback(data)
    }
}

enqueue_work :: proc { enqueue_work_t, enqueue_work_any }
enqueue_work_t   :: proc (queue: ^WorkQueue, callback: proc (data: ^$T),  data: ^T)  { enqueue_work_any(queue, auto_cast callback, data) }
enqueue_work_any :: proc (queue: ^WorkQueue, callback: WorkQueueCallback, data: pmm) {
    old_next_entry := queue.next_entry_to_write
    new_next_entry := (old_next_entry + 1) % len(queue.entries)
    assert(new_next_entry != queue.next_entry_to_read, "too many units of work enqueued") 

    entry := &queue.entries[old_next_entry] 
    entry ^= { callback, data }
    
    atomic_compare_exchange_or_fail(&queue.completion_goal, queue.completion_goal, queue.completion_goal+1)
    atomic_compare_exchange_or_fail(&queue.next_entry_to_write, old_next_entry, new_next_entry)
    
    sync.sema_post(&queue.semaphore, 1)
}

complete_all_work :: proc (queue: ^WorkQueue) {
    if queue == nil do return
    
    for !work_is_completed(queue) {
        do_next_work_queue_entry(queue)
    }
    
    atomic_compare_exchange_or_fail(&queue.completion_goal,  queue.completion_goal,  0)
    atomic_compare_exchange_or_fail(&queue.completion_count, queue.completion_count, 0)
}

work_is_completed :: proc (queue: ^WorkQueue) -> bool {
    return queue.completion_count == queue.completion_goal
}

do_next_work_queue_entry :: proc (queue: ^WorkQueue) -> (should_sleep: b32) {
    old_next_entry := queue.next_entry_to_read
    
    if old_next_entry != queue.next_entry_to_write {
        new_next_entry := (old_next_entry + 1) % len(queue.entries)
        ok, index := atomic_compare_exchange(&queue.next_entry_to_read, old_next_entry, new_next_entry)
    
        if ok {
            assert(index == old_next_entry)
            
            entry := &queue.entries[index]
            entry.callback(entry.data)
            
            atomic_add(&queue.completion_count, 1)
        }
    } else {
        should_sleep = true
    }
    
    return should_sleep
}

worker_thread :: proc (parameter: pmm) {
    context = runtime.default_context()
    
    info := cast(^CreateThreadInfo) parameter
    queue := info.queue
    
    spall_init_thread(info.index)
    defer spall_deinit_thread()
    
    atomic_add(&queue.opened_thread_count, 1)
    
    win.SetThreadDescription(win.GetCurrentThread(), win.utf8_to_wstring(sprint("%v: %v", queue.name, info.name_index)))
    
    for {
        should_sleep := do_next_work_queue_entry(queue)
        if queue.closed do break
        if should_sleep {
            sync.sema_wait(&queue.semaphore)
        }
    }
    
    atomic_add(&queue.closed_thread_count, 1)
}

atomic_compare_exchange_or_fail :: proc (destination: ^$T, old_value, new_value: T) -> (was_value: T) {
    ok: bool
    ok, was_value = atomic_compare_exchange(destination, old_value, new_value)
    assert(ok)
    return was_value
}
