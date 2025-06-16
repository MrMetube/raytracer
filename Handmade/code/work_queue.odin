package main

import "base:runtime"
import "core:thread"
import win "core:sys/windows"

WorkQueueCallback :: #type proc(data: pmm)

WorkQueue :: struct {
    semaphore_handle: win.HANDLE,
    
    completion_goal, 
    completion_count: u32,
     
    next_entry_to_write, 
    next_entry_to_read:  u32,
    
    entries: [4096]WorkQueueEntry,
}

WorkQueueEntry :: struct {
    callback: WorkQueueCallback,
    data:     pmm,
}

CreateThreadInfo :: struct {
    queue: ^WorkQueue,
    index: u32,
}

@(private="file") created_thread_count: u32 = 1

init_work_queue :: proc(queue: ^WorkQueue, infos: []CreateThreadInfo) {
    queue.semaphore_handle = win.CreateSemaphoreW(nil, 0, auto_cast len(infos), nil)
    
    for &info in infos {
        info.queue = queue
        info.index = created_thread_count
        created_thread_count += 1
        
        // @note(viktor): When I use the windows call I can at most create 4 threads at once,
        // any more calls to create thread in this call of the init function fail silently
        // A further call for the low_priority_queue then is able to create 4 more threads.
        //     result := win.CreateThread(nil, 0, thread_proc, info, thread_index, nil)
        
        thread.create_and_start_with_data(&info, worker_thread)
    }
}

enqueue_work_or_do_immediatly :: proc { enqueue_work_or_do_immediatly_t, enqueue_work_or_do_immediatly_any }
enqueue_work_or_do_immediatly_t :: proc(queue: ^WorkQueue, callback: proc(data: ^$T), data: ^T) { enqueue_work_or_do_immediatly_any(queue, auto_cast callback, data) }
enqueue_work_or_do_immediatly_any :: proc(queue: ^WorkQueue, callback: WorkQueueCallback, data: pmm) {
    if queue != nil {
        enqueue_work(queue, callback, data)
    } else {
        callback(data)
    }
}

enqueue_work :: proc { enqueue_work_t, enqueue_work_any }
enqueue_work_t :: proc(queue: ^WorkQueue, callback: proc(data: ^$T), data: ^T) { enqueue_work_any(queue, auto_cast callback, data) }
enqueue_work_any :: proc(queue: ^WorkQueue, callback: WorkQueueCallback, data: pmm) {
    old_next_entry := queue.next_entry_to_write
    new_next_entry := (old_next_entry + 1) % len(queue.entries)
    assert(new_next_entry != queue.next_entry_to_read, "too many units of work enqueued") 

    entry := &queue.entries[old_next_entry] 
    entry ^= { callback, data }
    
    atomic_compare_exchange_or_fail(&queue.completion_goal, queue.completion_goal, queue.completion_goal+1)
    atomic_compare_exchange_or_fail(&queue.next_entry_to_write, old_next_entry, new_next_entry)
    
    win.ReleaseSemaphore(queue.semaphore_handle, 1, nil)
}

complete_all_work :: proc(queue: ^WorkQueue) {
    if queue == nil do return
    
    for queue.completion_count != queue.completion_goal {
        do_next_work_queue_entry(queue)
    }
    
    atomic_compare_exchange_or_fail(&queue.completion_goal, queue.completion_goal, 0)
    atomic_compare_exchange_or_fail(&queue.completion_count, queue.completion_count, 0)
}

do_next_work_queue_entry :: proc(queue: ^WorkQueue) -> (should_sleep: b32) {
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
    context.user_index = cast(int) info.index
    
    for {
        if do_next_work_queue_entry(queue) { 
            INFINITE :: transmute(win.DWORD) i32(-1)
            win.WaitForSingleObjectEx(queue.semaphore_handle, INFINITE, false)
        }
    }
}
