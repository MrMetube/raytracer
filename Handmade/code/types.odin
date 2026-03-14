#+vet !unused-procedures
package main

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
