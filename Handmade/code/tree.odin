package main

// @speed we wont ever have 4 billion nodes, we may have more than 65 thousand...
Node_Index :: distinct u32

// @note(viktor): A sphere node currently fits into 32 bytes, whilst a triangle node is a bit too large at 44 bytes and requires 64 bytes(with alignment).
Tree_Node :: struct ($Value: typeid) #align(32) #raw_union {
    node:  Tree_Node_X,
    value: Tree_Value(Value),
}

Tree_Value :: struct ($Value: typeid) {
    next_value: Node_Index,
    value:      Value,
}

Tree_Node_X :: struct {
    // @note(viktor): the other one must follow directly after the first
    first_subnode: Node_Index,
    first_value:   Node_Index,
    bounds:        Rectangle3,
}

Nil_Index  :: 0
Root_Index :: 1

Subnodes_Per_Node :: 2

/* 
  @todo(viktor): Again update once the layout has been settled.
  
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

Tree_Build_Info :: struct {
    temp_stack:      [dynamic] Node_Index,
    value_counts:    [dynamic] u32,
    values_per_node: u32,
}

tree_init :: proc (tree: ^[dynamic] Tree_Node($Value), values_per_node: u32, bounds: Rectangle3, build_allocator: Allocator = context.temp_allocator) -> Tree_Build_Info {
    result: Tree_Build_Info
    result.temp_stack.allocator   = build_allocator
    result.value_counts.allocator = build_allocator
    result.values_per_node = values_per_node
    
    tree_append_node(&result, tree, {})     // nil
    tree_append_node(&result, tree, bounds) // root
    
    return result
}

tree_append_value :: proc (build_info: ^Tree_Build_Info, tree: ^[dynamic] Tree_Node($Value), value: Value) {
    append(tree, Tree_Node(Value) { value = { value = value } })
    append_nothing(&build_info.value_counts)
}

tree_append_node :: proc (build_info: ^Tree_Build_Info, tree: ^[dynamic] Tree_Node($Value), bounds: Rectangle3) {
    append(tree, Tree_Node(Value) { node = { bounds = bounds } })
    append_nothing(&build_info.value_counts)
}

tree_append :: proc (info: ^Tree_Build_Info, tree: ^[dynamic] Tree_Node($Value), value: Value, value_bounds: Rectangle3) {
    clear(&info.temp_stack)
    append(&info.temp_stack, Root_Index)
    
    value_index := cast(Node_Index) len(tree)
    tree_append_value(info, tree, value)
    
    into_index: Node_Index
    for len(&info.temp_stack) > 0 {
        it_index := pop(&info.temp_stack)
        it := &tree[it_index]
        node := &it.node
        if !contains_rect(node.bounds, value_bounds) do continue
        
        value_count := info.value_counts[it_index]
        if value_count < info.values_per_node {
            into_index = it_index
            break
        }
        
        // @note(viktor): subdivide node
        if node.first_subnode == Nil_Index {
            dimension := rectangle_get_dimension(node.bounds)
            
            max_axis := 0
            max_dim  := dimension[max_axis]
            for axis in 1..<len(dimension) {
                dim := dimension[axis]
                if max_dim < dim {
                    max_dim  = dim
                    max_axis = axis
                }
            }
            
            // @todo(viktor): this is a heuristic, maybe iterate through other options and measure their quality for a better split point
            sub_dim := dimension
            sub_dim[max_axis] *= .5
            offset: v3
            offset[max_axis] = sub_dim[max_axis]
            sub_bounds_0 := rectangle_min_dimension(node.bounds.min + 0 * offset, sub_dim)
            sub_bounds_1 := rectangle_min_dimension(node.bounds.min + 1 * offset, sub_dim)
            
            node.first_subnode = cast(Node_Index) len(tree)
            tree_append_node(info, tree, sub_bounds_0)
            // @cleanup tree may have been reallocated
            it = &tree[it_index]
            node = &it.node
            tree_append_node(info, tree, sub_bounds_1)
            // @cleanup tree may have been reallocated
            it = &tree[it_index]
            node = &it.node
        }
        
        sub_could_contain: bool
        subs: for sub_index in node.first_subnode ..< node.first_subnode + Subnodes_Per_Node {
            sub := tree[sub_index]
            if contains_rect(sub.node.bounds, value_bounds) {
                sub_could_contain = true
                append(&info.temp_stack, sub_index)
                break subs
            }
        }
        
        if !sub_could_contain {
            into_index = it_index
            break
        }
    }
    
    assert(into_index != Nil_Index)
    
    into  := &tree[into_index]
    value := &tree[value_index]
    value.value.next_value = into.node.first_value
    into.node.first_value = value_index
    
    info.value_counts[into_index] += 1
}

tree_is_empty :: proc (tree: [] Tree_Node($Value)) -> bool {
    root := tree[Root_Index].node
    result := root.first_value == Nil_Index
    if result {
        assert(root.first_subnode == 0)
    }
    return result
}

////////////////////////////////////////////////

print_node :: proc (nodes: [] $T, level: int, it_index: Node_Index) {
    it := nodes[it_index]
    
    for _ in 0..<level * 4 do print(" ")
    print("node %\n", it_index)
    for _ in 0..<level * 4 do print(" ")
    print("bounds %\n", it.node.bounds)
    
    // if it.node.first_value != 0 {
    //     for _ in 0..<level * 4 do print(" ")
    //     print("values:\n")
    //     for _ in 0..<(level+1) * 4 do print(" ")
    //     for link := it.node.first_value; link != 0; link = nodes[link].value.next_value {
    //         print("%, ", link)
    //     }
    //     print("\n")
    // }
    
    if it.node.first_subnode != 0 {
        for _ in 0..<level * 4 do print(" ")
        print("subnodes:\n")
        for subnode in it.node.first_subnode ..< it.node.first_subnode + Subnodes_Per_Node {
            print_node(nodes, level + 1, subnode)
        }
        for _ in 0..<level * 4 do print(" ")
        print(";\n")
    }
}

Tree_Info :: struct {
    values_per_node: Stat(u32),
    depth: Stat(u32),
    
    node_count:     u32,
    overfull_nodes: u32, 
}

inspect :: proc (info: Tree_Build_Info, nodes: [] Tree_Node($Value), it_index: Node_Index, depth : u32 = 0) -> Tree_Info {
    it := nodes[it_index]
    value_count := info.value_counts[it_index]
    
    result: Tree_Info
    
    result.depth = stat_init(depth)
    result.values_per_node = stat_init(value_count)
    result.node_count = 1
    if value_count > info.values_per_node {
        result.overfull_nodes += 1
    }
    
    if it.node.first_subnode != Nil_Index {
        for sub_index in it.node.first_subnode..< it.node.first_subnode + Subnodes_Per_Node {
            sub_info := inspect(info, nodes, sub_index, depth + 1)
            
            result.overfull_nodes += sub_info.overfull_nodes
            result.node_count     += sub_info.node_count
            
            stat_update(&result.values_per_node, sub_info.values_per_node)
            stat_update(&result.depth, sub_info.depth)
        }
    }
    
    stat_finalize(&result.values_per_node)
    stat_finalize(&result.depth)
    
    return result
}

Stat :: struct ($T: typeid) {
    min, max, sum, count: T,
    avg: f64,
}

stat_init :: proc (value: $T) -> Stat(T) {
    result: Stat(T)
    stat_update(&result, value)
    return result
}

stat_update :: proc { stat_update_stat, stat_update_value }
stat_update_stat :: proc (stat: ^Stat($T), other: Stat(T)) {
    stat.min    = min(stat.min, other.min)
    stat.max    = max(stat.max, other.max)
    stat.sum   += other.sum
    stat.count += other.count
}
stat_update_value :: proc (stat: ^Stat($T), other: T) {
    stat.min    = min(stat.min, other)
    stat.max    = max(stat.max, other)
    stat.sum   += other
    stat.count += 1
}

stat_finalize :: proc (stat: ^Stat($T)) {
    if stat.count > 0 {
        stat.avg = cast(f64) stat.sum / cast(f64) stat.count
    }
}