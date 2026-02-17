package main

/* 

  - A Hitable is either a Node of the octtree or a Value (i.e. a sphere).
  - Hitable_Index 0 is reserved for the nil-value / nil-node.
  - The root of the tree is defined as index 1.
  - It is currently not allowed to tree_append a non-value node.
  
  - The nodes of the tree may have subnodes
  - These are reached through the first_subnode from the parent and 
      then through the next_subnode until an index of 0 is reache.
  - Only tree nodes have the first/next_subnode and first_value set.
  
  - The values of a node are structured similarly and are reached through
      the first_child and then the next_child.
  - Values only ever point to their next sibling.

*/

Root_Index :: 1

tree_append :: proc (stack: ^[dynamic] Hitable_Index, hh: ^[dynamic] Hitable, hitable_index: Hitable_Index) -> bool {
    Dimensions: u32 : 3
    
    clear(stack)
    append(stack, Root_Index)
    
    hitable := &hh[hitable_index]
    for len(stack) > 0 {
        it_index := pop(stack)
        it := &hh[it_index]
        if !aabb_contains(it.bounds, hitable.bounds) do continue
        
        // @todo(viktor): its seems to not matter how large a node is at the current scale of value nodes
        if it.value_count <= 32 {
            append_value(it, hitable, hitable_index)
            break
        } else {
            if it.first_subnode == 0 {
                subdivide_tree_node(hh, it_index, Dimensions)
            }
            
            sub_could_contain: bool
            for sub_index := it.first_subnode; sub_index != 0; sub_index = hh[sub_index].next_subnode {
                sub := &hh[sub_index]
                could_contain := aabb_contains_aabb(sub.bounds, hitable.bounds)
                sub_could_contain ||= could_contain
                if could_contain {
                    append(stack, sub_index)
                    break
                }
            }
            
            if !sub_could_contain {
                append_value(it, hitable, hitable_index)
                break
            }
        }
    }
    
    return true
}

subdivide_tree_node :: proc (hh: ^[dynamic] Hitable, it_index: Hitable_Index, $Dimensions: u32) {
    spall_proc()
    first_subnode_index := cast(Hitable_Index) len(hh)
    
    count :: 1 << Dimensions
    for _ in 0..<count {
        append_nothing(hh)
    }
    
    it := &hh[it_index]
    half := get_dimension(it.bounds) * 0.5
    
    for sector_index in 0 ..< count {
        offset: [Dimensions] f32
        for axis in 0 ..< Dimensions {
            mask := 1 << axis
            is_positive := sector_index & mask == 0
            offset[axis] = is_positive ? half[axis] : -half[axis]
        }
        
        // @note(viktor): reverse the indices so that they appear in order in the linked list
        subnode_index := first_subnode_index + cast(Hitable_Index) (count - 1 - sector_index)
        subnode := &hh[subnode_index]
        subnode.bounds = center_dimension(get_center(it.bounds) + offset, half)
        
        append_child(it, subnode, subnode_index)
    }
}

append_child :: proc (t: ^Hitable, it: ^Hitable, it_index: Hitable_Index) {
    assert(it_index != 0)
    
    it.next_subnode = t.first_subnode
    t.first_subnode = it_index
}

append_value :: proc (t: ^Hitable, it: ^Hitable, it_index: Hitable_Index) {
    assert(it_index != 0)
    
    it.next_value = t.first_value
    t.first_value = it_index
    
    t.value_count += 1
}
