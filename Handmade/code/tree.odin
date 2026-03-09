package main

import "core:slice"

Node_Index  :: distinct u32
Value_Index :: distinct u32

// @important 
// Currently the 2 subnodes are always append on even-odd indices.
// That means they are on the same cacheline.
// This is because Nil and Root are appended as a pair and then
// all subnodes are always appended as pairs.

Tree_Node :: struct #align(32) {
    bounds:        Rectangle3,
    // @note(viktor): if value_count == 0 then its subnode, else its value
    value_count: u32,
    first: struct #raw_union {
        value:   Value_Index,
        // @note(viktor): the other one must follow directly after the first
        subnode: Node_Index,
    },
}

Nil_Index  :: 0
Root_Index :: 1

Subnodes_Per_Node :: 2

// @note(viktor): this is not idempotic, as the values are reordered.
// A second build may encounter values in a different order compared to the first build.
tree_build :: proc (tree: ^[dynamic] Tree_Node, triangles: [dynamic] Triangle) {
    clear(tree)
    
    max_depth := Tree_Max_Depth
    allocator := context.temp_allocator
    
    append_nothing(tree) // nil
    append_nothing(tree) // root
    if len(triangles) == 0 do return
    
    ////////////////////////////////////////////////
    
    triangle_centers := make_slice(allocator, [] v3, len(triangles))
    triangle_bounds  := make_slice(allocator, [] Rectangle3, len(triangles))
    
    root := &tree[Root_Index]
    root.bounds = rectangle_inverted_infinity(Rectangle3)
    
    root_values := make_slice(allocator, [] Value_Index, len(triangles))
    for value_index in cast(Value_Index) 0 ..< cast(Value_Index) len(triangles) {
        triangle := triangles[value_index]
        center := (triangle.a + triangle.b + triangle.c) / 3
        bounds := rectangle_inverted_infinity(Rectangle3)
        bounds = rectangle_union_point(bounds, triangle.a)
        bounds = rectangle_union_point(bounds, triangle.b)
        bounds = rectangle_union_point(bounds, triangle.c)
        
        root.bounds = rectangle_union(root.bounds, bounds)
        
        root_values[value_index] = value_index
        triangle_bounds[value_index] = bounds
        triangle_centers[value_index] = center
    }
    
    root_area_half: f32
    {
        dim := rectangle_get_dimension(root.bounds)
        root_area_half = dim.y * dim.z + dim.x * (dim.z + dim.y)
    }
    root_cost := root_area_half * cast(f32) len(triangles)
    
    final_indices: map[Node_Index] [] Value_Index
    final_indices.allocator = allocator
        
    _stack  := make_dynamic_array(allocator, [dynamic] Node_Info, 0, max_depth)
    stack  := &_stack
    
    append(stack, Node_Info { Root_Index, root_cost, 0, root_values })
    
    temp_indices := make_slice(allocator, [] Value_Index, len(triangles))
    
    for len(stack) > 0 {
        it := pop(stack)
        
        node := &tree[it.index]
        
        better, sub_a, sub_b := split_node(tree[:], node, it, triangle_centers, triangle_bounds, temp_indices)
        
        if better {
            node.first.subnode = cast(Node_Index) len(tree)
            
            sub_a_values := sub_a.values
            sub_b_values := sub_b.values
            
            append(tree, Tree_Node { bounds = sub_a.bounds })
            append(tree, Tree_Node { bounds = sub_b.bounds })
            
            // @cleanup tree may have been reallocated
            node = &tree[it.index]
            
            if it.depth+1 < max_depth {
                append(stack, Node_Info { node.first.subnode+0, sub_a.min_cost, it.depth+1, sub_a_values })
                append(stack, Node_Info { node.first.subnode+1, sub_b.min_cost, it.depth+1, sub_b_values })
            } else {
                final_indices[node.first.subnode+0] = sub_a_values
                final_indices[node.first.subnode+1] = sub_b_values
            }
        } else {
            final_indices[it.index] = it.indices
        }
    }
    
    ////////////////////////////////////////////////
    
    buffer := make_shallow_copy(triangles, allocator)
    zero(triangles[:])
    
    next_free_index: Value_Index
    
    clear(stack)
    append(stack, Node_Info{ index = Root_Index })
    
    for len(stack) > 0 {
        it := pop(stack)
        node := &tree[it.index]
        
        indices := final_indices[it.index] or_else {}
        
        node.value_count = cast(u32) len(indices)
        if node.value_count != 0 {
            node.first.value = next_free_index
            
            for buffer_index, offset in indices {
                value_index := node.first.value + cast(Value_Index) offset
                assert(triangles[value_index] == {})
                value := buffer[buffer_index]
                triangles[value_index] = value
            }
            
            next_free_index += cast(Value_Index) node.value_count
        } else {
            if node.first.subnode != Nil_Index {
                append(stack, Node_Info { index = node.first.subnode+0 })
                append(stack, Node_Info { index = node.first.subnode+1 })
            }
        }
    }
    
    assert(next_free_index == cast(Value_Index) len(buffer))
    
    // refit
    for node_index := len(tree)-1; node_index > 0; node_index -= 1 {
        node := &tree[node_index]
        
        bounds := rectangle_inverted_infinity(Rectangle3)
        if node.value_count != 0 {
            for offset in 0..<node.value_count {
                value := triangles[node.first.value + auto_cast offset]
                bounds = rectangle_union_point(bounds, value.a)
                bounds = rectangle_union_point(bounds, value.b)
                bounds = rectangle_union_point(bounds, value.c)
            }
        } else {
            bounds = rectangle_union(bounds, tree[node.first.subnode+0].bounds)
            bounds = rectangle_union(bounds, tree[node.first.subnode+1].bounds)
        }
        node.bounds = bounds
    }
    
}

Split_Node :: struct {
    min_cost: f32,
    values: [] Value_Index,
    bounds: Rectangle3,
}

split_node :: proc (tree: [] Tree_Node, node: ^Tree_Node, it: Node_Info, triangle_centers: [] v3, triangle_bounds: [] Rectangle3, temp_indices: [] Value_Index) -> (bool, Split_Node, Split_Node) {
    // @speed we can probably do tests in parallel by doing it LaneWide
    
    min_cost := +Infinity
    min_a_cost: f32
    min_b_cost: f32
    best_a_bounds: Rectangle3
    best_b_bounds: Rectangle3
    best_a_count: u32
    best_split_point: f32
    best_split_axis: int
    
    best_indices := temp_indices[:len(it.indices)]
    
    for split_axis in 0..<3 {
        Data :: struct {
            split_axis: int,
            triangle_centers: [] v3,
        }
        
        data := Data { split_axis, triangle_centers }
        slice.sort_by_with_data(it.indices, proc (a, b: Value_Index, data_p: pmm) -> bool {
            data := cast(^Data) data_p
            a_center := data.triangle_centers[a]
            b_center := data.triangle_centers[b]
            
            return a_center[data.split_axis] < b_center[data.split_axis]
        }, &data)
        
        for i in 0..<len(it.indices)-1 {
            node_index := it.indices[i]
            next_node_index := it.indices[i+1]
            node_center := triangle_centers[node_index][split_axis]
            next_center := triangle_centers[next_node_index][split_axis]
            split_point := linear_blend(node_center, next_center, 0.5)
            
            a_cost, b_cost, a_count := calculate_split_cost(node, split_axis, split_point, it, triangle_centers, triangle_bounds)
            cost := a_cost + b_cost
            
            if min_cost > cost {
                min_cost = cost
                
                copy(best_indices, it.indices)
                best_a_count = a_count
                
                min_a_cost = a_cost
                min_b_cost = b_cost
                best_split_point = split_point
                best_split_axis  = split_axis
            }
        }
    }
    
    better := min_cost < it.cost
    sub_a: Split_Node
    sub_b: Split_Node
    
    if better {
        copy(it.indices, best_indices)
        
        node.first.subnode = cast(Node_Index) len(tree)
        
        sub_a.values = it.indices[:best_a_count]
        sub_b.values = it.indices[best_a_count:]
        sub_a.min_cost = min_a_cost
        sub_b.min_cost = min_b_cost
        sub_a.bounds = best_a_bounds
        sub_b.bounds = best_b_bounds
    }
    
    return better, sub_a, sub_b
}

Node_Info :: struct {
    index: Node_Index,
    cost:  f32,
    depth: u32,
    indices: [] Value_Index,
}
calculate_split_cost :: proc (node: ^Tree_Node, split_axis: int, middle: f32, it: Node_Info, triangle_centers: [] v3, triangle_bounds: [] Rectangle3) -> (f32, f32, u32) {
                    
    node_count := cast(u32) len(it.indices)
    
    // @note(viktor): binary search the sorted indices
    a_count: u32
    for right := node_count; a_count < right; {
        it_index := (a_count + right) / 2
        
        value_index := it.indices[it_index]
        center      := triangle_centers[value_index]
        
        if center[split_axis] < middle {
            a_count = it_index + 1
        } else {
            right = it_index
        }
    }
    b_count := node_count - a_count
    
    a_bounds := rectangle_inverted_infinity(Rectangle3)
    b_bounds := rectangle_inverted_infinity(Rectangle3)
    for index in 0..<a_count {
        value_index := it.indices[index]
        bounds := triangle_bounds[value_index]
        a_bounds = rectangle_union(a_bounds, bounds)
    }
    for index in a_count..<node_count {
        value_index := it.indices[index]
        bounds := triangle_bounds[value_index]
        b_bounds = rectangle_union(b_bounds, bounds)
    }
    
    a_dim := rectangle_get_dimension(a_bounds)
    b_dim := rectangle_get_dimension(b_bounds)
    a_area_half := fused_mul_add(a_dim.y, a_dim.z, a_dim.x * (a_dim.z + a_dim.y))
    b_area_half := fused_mul_add(b_dim.y, b_dim.z, b_dim.x * (b_dim.z + b_dim.y))
    
    a_cost := a_area_half * cast(f32) a_count
    b_cost := b_area_half * cast(f32) b_count
    
    return a_cost, b_cost, a_count
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

inspect :: proc (nodes: [dynamic] Tree_Node, it_index: Node_Index = Root_Index, depth : u32 = 0) -> Tree_Info {
    it := nodes[it_index]
    value_count := it.value_count
    
    result: Tree_Info
    
    result.depth = stat_init(depth)
    result.values_per_node = stat_init(value_count)
    result.node_count = 1
    
    if it.value_count == 0 && it.first.subnode != Nil_Index {
        for sub_index in it.first.subnode..< it.first.subnode + Subnodes_Per_Node {
            sub_info := inspect(nodes, sub_index, depth + 1)
            
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

print_inspection :: proc (values: [dynamic] Triangle, inspection: Tree_Info) {
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
