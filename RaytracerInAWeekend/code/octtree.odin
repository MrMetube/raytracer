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

tree_append :: proc (hh: ^[dynamic] Hitable, root_index, hitable_index: Hitable_Index) -> bool {
    D: u32 : 3
    
    todo := make([dynamic] Hitable_Index)
    defer delete(todo)
    
    append(&todo, root_index)
    
    hitable := &hh[hitable_index]
    for len(todo) > 0 {
        it_index := pop(&todo)
        it := &hh[it_index]
        if !aabb_contains(it.bounds, hitable.bounds) do continue
        
        if it.value_count < 256 {
            append_value(it, hitable, hitable_index)
            break
        } else {
            if it.first_subnode == 0 {
                subdivide_tree_node(hh, it_index, D)
            }
            
            sub_could_contain: bool
            for sub_index := it.first_subnode; sub_index != 0; sub_index = hh[sub_index].next_subnode {
                sub := &hh[sub_index]
                could_contain := aabb_contains_aabb(sub.bounds, hitable.bounds)
                sub_could_contain ||= could_contain
                if could_contain {
                    append(&todo, sub_index)
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

subdivide_tree_node :: proc (hh: ^[dynamic] Hitable, it_index: Hitable_Index, $D: u32) {
    spall_proc()
    first_subnode_index := cast(Hitable_Index) len(hh)
    
    count :: 1 << D
    for _ in 0..<count {
        append_nothing(hh)
    }
    
    it := &hh[it_index]
    half := it.extent * .5
    for sector_index in 0 ..< count {
        offset: [D]f32 = ---
        for axis in 0 ..< D {
            mask := 1 << axis
            is_positive := sector_index & mask == 0
            
            // for the x-axis we iterate: - -> + (W -> E)
            // for the y- and z-axis (and further) we iterate: + -> - (N->S, T->B)
            if axis == 0 {
                offset[axis] = half[axis] if !is_positive else -half[axis]
            } else {
                offset[axis] = half[axis] if is_positive else -half[axis]
            }
        }
        
        subnode_index := first_subnode_index + cast(Hitable_Index) sector_index
        subnode := &hh[subnode_index]
        subnode.origin = it.origin + offset
        subnode.extent = half
        
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
