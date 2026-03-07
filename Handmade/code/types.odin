#+vet !unused-procedures
package main

import "base:builtin"

String_Builder :: [dynamic] u8

append :: proc { 
    append_string, builtin.append_elem, builtin.append_elems, builtin.append_soa_elems, builtin.append_soa_elem,
}
append_string :: proc (a: ^String_Builder, value: string) -> (result: string) {
    append(a, ..(transmute([] u8) value))
    return cast(string) a[:]
}

make_string_builder :: proc { make_string_builder_buffer }
make_string_builder_buffer :: proc (buffer: [] u8) -> (result: String_Builder) {
    raw: Raw_Dynamic_Array
    raw.data = raw_data(buffer)
    raw.cap  = len(buffer)
    
    result = transmute(String_Builder) raw
    return result
}

peek :: proc (a: [dynamic] $T) -> (result: ^T) { 
    assert(len(a) != 0)
    #no_bounds_check result = &a[len(a)-1]
    return result
}

to_string :: proc (sb: String_Builder) -> string {
    return cast(string) sb[:]
}

rest :: proc{ rest_dynamic_array }
rest_dynamic_array :: proc (array: [dynamic] $T) -> [] T {
    return slice_from_parts(raw_data(array), cap(array))
}

set_len :: proc (array: ^[dynamic] $T, len: int) {
    raw := cast(^Raw_Dynamic_Array) array
    raw.len = len
}

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
