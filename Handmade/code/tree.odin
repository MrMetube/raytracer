package main

Node_Index  :: distinct u16
Value_Index :: distinct u32
/// bounds = 2 * 3 * 4
/// node = bounds + 4 * 3
/// node

// @note(viktor): A sphere node currently fits into 32 bytes, whilst a triangle node is a bit too large at 44 bytes and requires 64 bytes(with alignment).
Tree_Node :: struct #align(32) {
    bounds:        Rectangle3,
    first_value:   Value_Index,
    value_count:   u16,
    // @note(viktor): the other one must follow directly after the first
    first_subnode: Node_Index,
}

Nil_Index  :: 0
Root_Index :: 1

Subnodes_Per_Node :: 2

Tree_Build_Info :: struct {
    allocator: Allocator,
    temp_stack:      [dynamic] Node_Index,
    values:          map [Node_Index] [dynamic] Value_Index,
    values_per_node: u16,
}

tree_init :: proc (tree: ^[dynamic] Tree_Node, values_per_node: u16, bounds: Rectangle3, build_allocator: Allocator = context.temp_allocator) -> Tree_Build_Info {
    result: Tree_Build_Info
    result.allocator = build_allocator
    result.temp_stack.allocator   = result.allocator
    result.values.allocator = result.allocator
    result.values_per_node = values_per_node
    
    tree_append_node(&result, tree, {})     // nil
    tree_append_node(&result, tree, bounds) // root
    
    return result
}

tree_append_value :: proc (info: ^Tree_Build_Info, tree: ^[dynamic] Tree_Node, node_index: Node_Index, value_index: Value_Index) {
    values, ok := &info.values[node_index]
    assert(ok)
    append(values, value_index)
    node := &tree[node_index]
    node.value_count += 1
}

tree_append_node :: proc (info: ^Tree_Build_Info, tree: ^[dynamic] Tree_Node, bounds: Rectangle3) {
    node_index := cast(Node_Index) len(tree)
    append(tree, Tree_Node{ bounds = bounds })
    info.values[node_index] = make_dynamic_array(info.allocator, [dynamic] Value_Index, 0, 4)
}

tree_append :: proc (info: ^Tree_Build_Info, tree: ^[dynamic] Tree_Node, value_index: Value_Index, value_bounds: Rectangle3) {
    clear(&info.temp_stack)
    append(&info.temp_stack, Root_Index)
    
    into_index: Node_Index
    for len(&info.temp_stack) > 0 {
        it_index := pop(&info.temp_stack)
        node := &tree[it_index]
        if !contains_rect(node.bounds, value_bounds) do continue
        
        value_count := node.value_count
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
            node = &tree[it_index]
            tree_append_node(info, tree, sub_bounds_1)
            // @cleanup tree may have been reallocated
            node = &tree[it_index]
        }
        
        sub_could_contain: bool
        subs: for sub_index in node.first_subnode ..< node.first_subnode + Subnodes_Per_Node {
            sub := tree[sub_index]
            if contains_rect(sub.bounds, value_bounds) {
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
    tree_append_value(info, tree, into_index, value_index)
}

tree_finalize :: proc (info: ^Tree_Build_Info, tree: ^[dynamic] Tree_Node, values: [] $Value) {
    buffer := make_slice(info.allocator, [] Value, len(values))
    copy(buffer, values)
    zero(values) 
    
    next_free_index: Value_Index
    
    stack := &info.temp_stack
    clear(stack)
    append(stack, Root_Index)
    
    for len(stack) > 0 {
        node_index := pop(stack)
        node := &tree[node_index]
        
        value_indices, ok := info.values[node_index]
        assert(ok)
        
        node.value_count = cast(u16) len(value_indices)
        if node.value_count != 0 {
            node.first_value = next_free_index
            for buffer_index, offset in value_indices {
                value_index := node.first_value + cast(Value_Index) offset
                assert(values[value_index] == {})
                values[value_index] = buffer[buffer_index]
            }
            next_free_index += cast(Value_Index) node.value_count
        }
        
        if node.first_subnode != Nil_Index {
            append(stack, node.first_subnode+0)
            append(stack, node.first_subnode+1)
        }
    }
    
    assert(next_free_index == cast(Value_Index) len(buffer))
    pretend_to_read(&next_free_index)
}

tree_compact :: proc (nodes: [] Tree_Node, values: [] $Value) -> Stat(f32) {
    compacted: Stat(f32)
    backing: [1024] Node_Index
    stack := dynamic_array_from_parts(Node_Index, raw_data(&backing), 0, len(backing))
    append(&stack, Root_Index)
    for len(stack) != 0 {
        it_index := pop(&stack)
        assert(it_index != Nil_Index)
        it := nodes[it_index]
        if it.first_subnode != Nil_Index {
            append(&stack, it.first_subnode+0)
            append(&stack, it.first_subnode+1)
        }
        
        if it.first_value != Nil_Index {
            bounds := rectangle_inverted_infinity(Rectangle3)
            
            end := it.first_value + cast(Value_Index) it.value_count
            for link in it.first_value..<end {
                value := values[link]
                bounds = rectangle_union(bounds, get_bounds(value))
            }
            
            stat_update(&compacted, rectangle_clamped_area(bounds) / rectangle_clamped_area(it.bounds))
        } else {
            it.bounds = {}
        }
    }
    
    stat_finalize(&compacted)
    
    return compacted
}

get_bounds :: proc { get_bounds_triangle, get_bounds_sphere }
get_bounds_triangle :: proc (triangle: Triangle) -> Rectangle3 {
    bounds := rectangle_inverted_infinity(Rectangle3)
    bounds = rectangle_union_point(bounds, triangle.a)
    bounds = rectangle_union_point(bounds, triangle.b)
    bounds = rectangle_union_point(bounds, triangle.c)
    return bounds
}
get_bounds_sphere :: proc (sphere: Sphere) -> Rectangle3 {
    bounds := rectangle_center_dimension(sphere.center, sphere.radius)
    return bounds
}

tree_is_empty :: proc (tree: [] Tree_Node) -> bool {
    root := tree[Root_Index]
    result := root.value_count == 0
    if result {
        assert(root.first_subnode == Nil_Index)
    }
    return result
}

////////////////////////////////////////////////

print_node :: proc (nodes: [] $T, level: int, it_index: Node_Index) {
    it := nodes[it_index]
    
    for _ in 0..<level * 4 do print(" ")
    print("node %\n", it_index)
    for _ in 0..<level * 4 do print(" ")
    print("bounds %\n", it.bounds)
    
    // if it.first_value != 0 {
    //     for _ in 0..<level * 4 do print(" ")
    //     print("values:\n")
    //     for _ in 0..<(level+1) * 4 do print(" ")
    //     for link := it.first_value; link != 0; link = nodes[link].value.next_value {
    //         print("%, ", link)
    //     }
    //     print("\n")
    // }
    
    if it.first_subnode != 0 {
        for _ in 0..<level * 4 do print(" ")
        print("subnodes:\n")
        for subnode in it.first_subnode ..< it.first_subnode + Subnodes_Per_Node {
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

inspect :: proc (info: Tree_Build_Info, nodes: [] Tree_Node, it_index: Node_Index, depth : u32 = 0) -> Tree_Info {
    it := nodes[it_index]
    value_count := it.value_count
    
    result: Tree_Info
    
    result.depth = stat_init(depth)
    result.values_per_node = stat_init(cast(u32) value_count)
    result.node_count = 1
    if value_count > info.values_per_node {
        result.overfull_nodes += 1
    }
    
    if it.first_subnode != Nil_Index {
        for sub_index in it.first_subnode..< it.first_subnode + Subnodes_Per_Node {
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