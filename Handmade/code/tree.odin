package main

Node_Index  :: distinct u16
Value_Index :: distinct u32

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
    temp_stack2:     [dynamic] u32,
    values:          map [Node_Index] [dynamic] Value_Index,
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

tree_build :: proc (allocator: Allocator, tree: ^[dynamic] Tree_Node, values: [] $Value, max_depth, min_values_per_node, max_values_per_node: u32) -> Tree_Build_Info {
    clear(tree)
    
    // @cleanup
    info: Tree_Build_Info
    info.allocator = allocator
    info.temp_stack.allocator = info.allocator
    info.values.allocator     = info.allocator
    
    tree_append_node(&info, tree, {}) // nil
    tree_append_node(&info, tree, {}) // root
    
    ////////////////////////////////////////////////
    
    stack := &info.temp_stack
    clear(stack)
    append(stack, Root_Index)
    depths := &info.temp_stack2
    clear(depths)
    append(depths, 0)
    
    root_bounds := &tree[Root_Index].bounds
    root_bounds^ = rectangle_inverted_infinity(Rectangle3)
    for value_index in cast(Value_Index) 0 ..< cast(Value_Index) len(values) {
        value_bounds := get_bounds(values[value_index])
        root_bounds^ = rectangle_union(root_bounds^, value_bounds)
        center := rectangle_get_center(value_bounds)
        assert(rectangle_contains_inclusive(root_bounds^, center))
        tree_append_value(&info, tree, Root_Index, value_index)
    }
    
    for len(stack) > 0 {
        it_index := pop(stack)
        depth := pop(depths)
        
        node := &tree[it_index]
        if cast(u32) node.value_count < max_values_per_node {
            if depth >= max_depth do continue
        }
            
        if cast(u32) node.value_count < min_values_per_node do continue
        
        sub_bounds := tree_sub_bounds(node)
        
        node.first_subnode = cast(Node_Index) len(tree)
        tree_append_node(&info, tree, sub_bounds[0])
        // @cleanup tree may have been reallocated
        node = &tree[it_index]
        tree_append_node(&info, tree, sub_bounds[1])
        // @cleanup tree may have been reallocated
        node = &tree[it_index]
        
        node_values, ok := &info.values[it_index]
        assert(ok)
        for value_index in node_values {
            value_bounds := get_bounds(values[value_index])
            
            into_index := node.first_subnode+1
            center := rectangle_get_center(value_bounds)
            if rectangle_contains_inclusive(sub_bounds[0], center) {
                into_index = node.first_subnode+0
            } else {
                assert(rectangle_contains_inclusive(sub_bounds[1], center))
            }
            tree_append_value(&info, tree, into_index, value_index)
        }
        clear(node_values)
        node.value_count = 0
        
        append(stack, node.first_subnode+0)
        append(stack, node.first_subnode+1)
        append(depths, depth+1)
        append(depths, depth+1)
    }
    
    ////////////////////////////////////////////////
    
    buffer := make_slice(info.allocator, [] Value, len(values))
    copy(buffer, values)
    zero(values) 
    
    next_free_index: Value_Index
    
    clear(stack)
    append(stack, Root_Index)
    
    for len(stack) > 0 {
        node_index := pop(stack)
        node := &tree[node_index]
        
        value_indices, ok := info.values[node_index]
        assert(ok)
        
        node.bounds = rectangle_inverted_infinity(Rectangle3)
        node.value_count = cast(u16) len(value_indices)
        if node.value_count != 0 {
            node.first_value = next_free_index
            for buffer_index, offset in value_indices {
                value_index := node.first_value + cast(Value_Index) offset
                assert(values[value_index] == {})
                value := buffer[buffer_index]
                values[value_index] = value
                
                value_bounds := get_bounds(value)
                node.bounds = rectangle_union(node.bounds, value_bounds)
            }
            next_free_index += cast(Value_Index) node.value_count
        }
        
        if node.first_subnode != Nil_Index {
            append(stack, node.first_subnode+0)
            append(stack, node.first_subnode+1)
        }
    }
    
    assert(next_free_index == cast(Value_Index) len(buffer))
    
    return info
}

tree_sub_bounds :: proc (node: ^Tree_Node) -> [2] Rectangle3 {
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
    sub_bounds: [2] Rectangle3
    sub_bounds[0] = rectangle_min_dimension(node.bounds.min + 0 * offset, sub_dim)
    sub_bounds[1] = rectangle_min_dimension(node.bounds.min + 1 * offset, sub_dim)
    
    return sub_bounds
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

////////////////////////////////////////////////

tree_print :: proc (nodes: [] $T, level: int = 0, it_index: Node_Index = Root_Index) {
    it := nodes[it_index]
    
    for _ in 0..<level * 4 do print(" ")
    print("node %\n", it_index)
    for _ in 0..<level * 4 do print(" ")
    print("bounds %\n", it.bounds)
    for _ in 0..<level * 4 do print(" ")
    print("first_value %\n", it.first_value)
    for _ in 0..<level * 4 do print(" ")
    print("value_count %\n", it.value_count)
    
    if it.first_subnode != 0 {
        for _ in 0..<level * 4 do print(" ")
        print("subnodes:\n")
        for subnode in it.first_subnode ..< it.first_subnode + Subnodes_Per_Node {
            tree_print(nodes, level + 1, subnode)
        }
        for _ in 0..<level * 4 do print(" ")
        print(";\n")
    }
}

Tree_Info :: struct {
    values_per_node: Stat(u32),
    depth: Stat(u32),
    
    node_count: u32,
}

inspect :: proc (info: Tree_Build_Info, nodes: [] Tree_Node, it_index: Node_Index = Root_Index, depth : u32 = 0) -> Tree_Info {
    it := nodes[it_index]
    value_count := it.value_count
    
    result: Tree_Info
    
    result.depth = stat_init(depth)
    result.values_per_node = stat_init(cast(u32) value_count)
    result.node_count = 1
    
    if it.first_subnode != Nil_Index {
        for sub_index in it.first_subnode..< it.first_subnode + Subnodes_Per_Node {
            sub_info := inspect(info, nodes, sub_index, depth + 1)
            
            result.node_count += sub_info.node_count
            
            if sub_info.values_per_node.count != 0 {
                stat_update(&result.values_per_node, sub_info.values_per_node)
            }
            stat_update(&result.depth, sub_info.depth)
        }
    }
    
    stat_finalize(&result.values_per_node)
    stat_finalize(&result.depth)
    
    return result
}

print_inspection :: proc (values: [] $Value, nodes: [] Tree_Node, inspection: Tree_Info) {
    if len(values) > 0 {
        print("tree info:\n")
        print("            nodes: %\n", inspection.node_count)
        print("            depth: max = %, avg = %\n", inspection.depth.max, view_float(inspection.depth.avg, precision = 2))
        print("  values per node: max = %, avg = %\n", inspection.values_per_node.max, view_float(inspection.values_per_node.avg, precision = 2))
        print("\n")
    }
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