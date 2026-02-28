package main

Node_Index :: distinct u32

Base_Node :: struct {
    first_subnode: Node_Index,
    next_subnode:  Node_Index,
    
    first_value: Node_Index,
    next_value:  Node_Index,
    value_count: u8,
    
    bounds: Rectangle3,
}

Oct_Node :: struct ($Value: typeid) {
    subnodes:    [8] Node_Index,
    first_value: Node_Index,
    next_value:  Node_Index,
    value_count: u8,
    
    bounds: Rectangle3,
    value:  Value,
}

/* 
  - A Node is either a octtree node containing values and subnodes 
    or a value node.
  - Node_Index 0 is reserved for the nil-value / nil-node.
  - The root of the tree is defined as index 1.
  - It is currently not allowed to tree_append a octtree node.
  
  - The nodes of the tree may have subnodes.
  - These are reached through the first_subnode from the parent and 
    then through the next_subnode until an index of 0 is reached.
  - Only tree nodes have the first/next_subnode and first_value set.
  
  - The values of a node are structured similarly and are reached 
    through the first_value and then the next_value.
  - Values only ever point to their next sibling.
*/

Nil_Index  :: 0
Root_Index :: 1

tree_init :: proc (tree: ^[dynamic] $Node, bounds: Rectangle3) {
    append_nothing(tree) // nil
    append_nothing(tree) // root
    
    root := &tree[Root_Index]
    root.bounds = bounds
}

tree_append :: proc (temp_stack: ^[dynamic] Node_Index, tree: ^[dynamic] $Node, value: Node, values_per_node: i8 = 32, Dimesions := 3) -> bool {
    Dimensions :: cast(u32) 3
    
    clear(temp_stack)
    append(temp_stack, Root_Index)
    
    value_index := cast(Node_Index) len(tree)
    append(tree, value)
    
    into_index: Node_Index
    for len(temp_stack) > 0 {
        node_index := pop(temp_stack)
        node := &tree[node_index]
        if !contains_rect(node.bounds, value.bounds) do continue
        
        if node.value_count < values_per_node {
            into_index = node_index
            break
        }
        
        // @note(viktor): subdivide node
        if node.first_subnode == Nil_Index {
            first_subnode_index := cast(Node_Index) len(tree)
    
            count :: 1 << Dimensions
            for _ in 0..<count do append_nothing(tree)
            
            half := get_dimension(node.bounds) * 0.5
            
            for sector_index in 0 ..< count {
                // @note(viktor): spread the bits into a vector like 0b101 -> {1, 0, 1}
                factor: [Dimensions] f32
                for axis in 0 ..< Dimensions {
                    mask := 1 << axis
                    factor[axis] = (sector_index & mask) == 0 ? 0 : 1
                }
                
                // @note(viktor): reverse the indices so that they appear in order in the linked list
                subnode_index := first_subnode_index + cast(Node_Index) (count - 1 - sector_index)
                subnode := &tree[subnode_index]
                subnode.bounds = rectangle_min_dimension(node.bounds.min + factor * half, half)
                
                subnode.next_subnode = node.first_subnode
                node.first_subnode   = subnode_index
            }
        }
        
        sub_could_contain: bool
        subs: for sub_index := node.first_subnode; sub_index != Nil_Index; sub_index = tree[sub_index].next_subnode {
            sub := &tree[sub_index]
            if contains_rect(sub.bounds, value.bounds) {
                sub_could_contain = true
                append(temp_stack, sub_index)
                break subs
            }
        }
        
        if !sub_could_contain {
            into_index = node_index
            break
        }
    }
    
    result: bool
    if into_index != Nil_Index {
        result = true
        
        into  := &tree[into_index]
        value := &tree[value_index]
        
        value.next_value = into.first_value
        into.first_value = value_index
        
        into.value_count += 1
    }
    
    return result
}

// @copypasta only the subnodes code is actually different from the tree_append code
octtree_append :: proc (temp_stack: ^[dynamic] Node_Index, tree: ^[dynamic] $Node, value: Node, values_per_node: u8, Dimesions := 3) -> bool {
    Dimensions :: cast(u32) 3
    
    clear(temp_stack)
    append(temp_stack, Root_Index)
    
    value_index := cast(Node_Index) len(tree)
    append(tree, value)
    
    into_index: Node_Index
    for len(temp_stack) > 0 {
        node_index := pop(temp_stack)
        node := &tree[node_index]
        if !contains_rect(node.bounds, value.bounds) do continue
        
        if node.value_count < values_per_node {
            into_index = node_index
            break
        }
        
        // @note(viktor): subdivide node
        if node.subnodes[0] == Nil_Index {
            first_subnode_index := cast(Node_Index) len(tree)
            
            count :: 1 << Dimensions
            for _ in 0..<count do append_nothing(tree)
            
            half := get_dimension(node.bounds) * 0.5
            
            for sector_index in 0 ..< count {
                // @note(viktor): spread the bits into a vector like 0b101 -> {1, 0, 1}
                factor: [Dimensions] f32
                for axis in 0 ..< Dimensions {
                    mask := 1 << axis
                    factor[axis] = (sector_index & mask) == 0 ? 0 : 1
                }
                
                subnode_index := first_subnode_index + cast(Node_Index) sector_index
                subnode := &tree[subnode_index]
                subnode.bounds = rectangle_min_dimension(node.bounds.min + factor * half, half)
                
                node.subnodes[sector_index] = subnode_index
            }
        }
        
        sub_could_contain: bool
        subs: for &sub_index in node.subnodes {
            sub := tree[sub_index]
            if contains_rect(sub.bounds, value.bounds) {
                sub_could_contain = true
                append(temp_stack, sub_index)
                break subs
            }
        }
        
        if !sub_could_contain {
            into_index = node_index
            break
        }
    }
    
    result: bool
    if into_index != Nil_Index {
        result = true
        
        into  := &tree[into_index]
        value := &tree[value_index]
        
        value.next_value = into.first_value
        into.first_value = value_index
        
        into.value_count += 1
    }
    
    return result
}


////////////////////////////////////////////////

print_node :: proc (nodes: [dynamic] $T, level: int, it_index: Node_Index) -> u32 {
    it := nodes[it_index]
    count := it.value_count
    
    for _ in 0..<level * 4 do print(" ")
    print("node %\n", it_index)
    
    if it.value_count != 0 {
        for _ in 0..<level * 4 do print(" ")
        print("values:\n")
        for _ in 0..<(level+1) * 4 do print(" ")
        for link := it.first_value; link != 0; link = nodes[link].next_value {
            print("%, ", link)
        }
        print("\n")
    }
    
    if it.first_subnode != 0 {
        for _ in 0..<level * 4 do print(" ")
        print("subnodes:\n")
        for link := it.first_subnode; link != 0; link = nodes[link].next_subnode {
            count += print_node(nodes, level + 1, link)
        }
        for _ in 0..<level * 4 do print(" ")
        print(";\n")
    }
    
    return count
}

Tree_Info :: struct {
    value_count: u32, 
    node_count:  u32,
    overfull_nodes: u32, 
    max_depth: u32,
}

inspect :: proc (nodes: [dynamic] $T, it_index: Node_Index, desired_values_per_node: u8, depth : u32 = 0) -> Tree_Info {
    it := nodes[it_index]
    
    result: Tree_Info
    result.value_count = auto_cast it.value_count
    result.max_depth = depth
    result.node_count = 1
    if it.value_count > desired_values_per_node {
        result.overfull_nodes += 1
    }
    
    if it.subnodes[0] != Nil_Index {
        for sub_index in it.subnodes {
            sub_info := inspect(nodes, sub_index, desired_values_per_node, depth + 1)
            
            result.value_count    += sub_info.value_count
            result.overfull_nodes += sub_info.overfull_nodes
            result.node_count     += sub_info.node_count
            result.max_depth       = max(result.max_depth, sub_info.max_depth)
        }
    }
    
    return result
}