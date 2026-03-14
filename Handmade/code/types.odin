#+vet !unused-procedures
package main

////////////////////////////////////////////////
// [First] <- [..] ... <- [..] <- [Last] 
Deque :: struct($L: typeid) {
    first, last: ^L,
}

deque_prepend :: proc (deque: ^Deque($L), element: ^L) {
    if deque.first == nil {
        assert(deque.last == nil)
        deque.last  = element
        deque.first = element
    }  else {
        element.next = deque.last
        deque.last   = element
    }
}

deque_append :: proc (deque: ^Deque($L), element: ^L) {
    if deque.first == nil {
        assert(deque.last == nil)
        deque.last  = element
        deque.first = element
    }  else {
        deque.first.next = element
        deque.first      = element
    }
}

deque_remove_from_end :: proc (deque: ^Deque($L)) -> (result: ^L) {
    result = deque.last
    
    if result != nil {
        deque.last = result.next

        if result == deque.first {
            assert(result.next == nil)
            deque.first = nil
        }
    }
    
    return result
}

////////////////////////////////////////////////
// Double Linked List
// [Sentinel] -> <- [..] ->
//  -> <- [..] -> ...    <-

list_init_sentinel :: proc (sentinel: ^$T) {
    sentinel.next = sentinel
    sentinel.prev = sentinel
}

list_prepend :: proc (list: ^$T, element: ^T) {
    element.prev = list.prev
    element.next = list
    
    element.next.prev = element
    element.prev.next = element
}

list_append :: proc (list: ^$T, element: ^T) {
    element.next = list.next
    element.prev = list
    
    element.next.prev = element
    element.prev.next = element
}

list_remove :: proc (element: ^$T) {
    element.prev.next = element.next
    element.next.prev = element.prev
    
    element.next = nil
    element.prev = nil
}

///////////////////////////////////////////////
// Single Linked List
// [Head] -> [..] ... -> [..] -> [Tail]

list_push :: proc { list_push_next, list_push_custom_member }
list_push_next          :: proc (head: ^^$T, element: ^T)             { list_push(head, element, offset_of(T, next)) }
list_push_custom_member :: proc (head: ^^$T, element: ^T, $next: umm) {
    element_next := get(element, next) 
    #assert(type_of(element_next^) == ^T)

    element_next ^= head^
    head         ^= element
}

list_pop_head :: proc { list_pop_head_custom_member, list_pop_head_next }
list_pop_head_next          :: proc (head: ^^$T)             -> (result: ^T, ok: b32) #optional_ok { return list_pop_head(head, offset_of(head^.next)) }
list_pop_head_custom_member :: proc (head: ^^$T, $next: umm) -> (result: ^T, ok: b32) #optional_ok {
    if head^ != nil {
        result = head^
        head ^= get(result, next)^
        
        ok = true
    }
    return result, ok
}

///////////////////////////////////////////////

@(private="file") 
get :: proc (type: ^$T, $offset: umm ) -> (result: ^^T) {
    raw_link := cast([^]u8) type
    slot := cast(^^T) &raw_link[offset]
    return slot
}
