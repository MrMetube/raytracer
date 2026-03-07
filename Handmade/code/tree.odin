package main

import "core:slice"

Node_Index  :: distinct u32
Value_Index :: distinct u32


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
// A second build will encounter values in a different order compared to the first build.
tree_build :: proc (allocator: Allocator, tree: ^[dynamic] Tree_Node, values: [] $Value, max_depth: u32) {
    clear(tree)
    
    append_nothing(tree) // nil
    append_nothing(tree) // root
    if len(values) == 0 do return
    
    ////////////////////////////////////////////////
    
    Value_Info :: struct {
        bounds: Rectangle3,
        center: v3,
    }
        
    value_infos := make_slice(allocator, [] Value_Info, len(values))
    
    root := &tree[Root_Index]
    root.bounds = rectangle_inverted_infinity(Rectangle3)
    
    root_values := make_slice(allocator, [] Value_Index, len(values))
    for value_index in cast(Value_Index) 0 ..< cast(Value_Index) len(values) {
        value_bounds := get_bounds(values[value_index])
        center := rectangle_get_center(value_bounds)
        
        root.bounds = rectangle_union(root.bounds, value_bounds)
        root_values[value_index] = value_index
        value_infos[value_index] = { value_bounds, center }
    }
    
    root_area_half: f32
    {
        dim := rectangle_get_dimension(root.bounds)
        root_area_half = dim.y * dim.z + dim.x * (dim.z + dim.y)
    }
    root_cost := root_area_half * cast(f32) len(values)
    
    final_node_values: map[Node_Index] [] Value_Index
    final_node_values.allocator = allocator
        
    Node_Info :: struct {
        index: Node_Index,
        cost:  f32,
        depth: u32,
        node_values: [] Value_Index,
    }
    _stack  := make_dynamic_array(allocator, [dynamic] Node_Info, 0, max_depth)
    stack  := &_stack
    
    append(stack, Node_Info { Root_Index, root_cost, 0, root_values })
    
    temp_node_values := make_slice(allocator, [] Value_Index, len(values))
    
    for len(stack) > 0 {
        it := pop(stack)
        
        node := &tree[it.index]
        
        // @speed we can probably do tests in parallel by doing it LaneWide
        
        min_cost := +Infinity
        min_a_cost: f32
        min_b_cost: f32
        best_a_count: u32
        best_split_point: f32
        best_split_axis: int
        // @waste we make a second buffer, take two slices of it and throw away the original
        best_node_values := temp_node_values[:len(it.node_values)]
        
        // @todo(viktor): reduce this to something reasonable once we have bigger, or just more models
        attempts :: 16384
        for split_axis in 0..<3 {
            Data :: struct {
                split_axis: int,
                value_infos: [] Value_Info,
            }
            
            data := Data { split_axis, value_infos[:] }
            slice.sort_by_with_data(it.node_values, proc (a, b: Value_Index, data_p: pmm) -> bool {
                data := cast(^Data) data_p
                a_center := data.value_infos[a].center
                b_center := data.value_infos[b].center
                
                return a_center[data.split_axis] < b_center[data.split_axis]
            }, &data)
            
            dimension := rectangle_get_dimension(node.bounds)
            for i in 0 ..< attempts {
                split_point := linear_remap(cast(f32) i, -1, attempts, 0, 1)
                
                a_dim := dimension
                b_dim := dimension
                a_dim[split_axis] *= split_point
                b_dim[split_axis] *= (1-split_point)
                a_area_half := fused_mul_add(a_dim.y, a_dim.z, a_dim.x * (a_dim.z + a_dim.y))
                b_area_half := fused_mul_add(b_dim.y, b_dim.z, b_dim.x * (b_dim.z + b_dim.y))
                
                middle := linear_blend(node.bounds.min[split_axis], node.bounds.max[split_axis], split_point)
                
                node_count := cast(u32) len(it.node_values)
                
                // @note(viktor): binary search the sorted node_values
                a_count: u32
                for right := node_count; a_count < right; {
                    it_index := (a_count + right) / 2
                    
                    value_index  := it.node_values[it_index]
                    value_bounds := value_infos[value_index]
                    center       := value_bounds.center
                    
                    if center[split_axis] < middle {
                        a_count = it_index + 1
                    } else {
                        right = it_index
                    }
                }
                b_count := node_count - a_count
                
                a_cost := a_area_half * cast(f32) a_count
                b_cost := b_area_half * cast(f32) b_count
                cost := a_cost + b_cost
                
                if min_cost > cost {
                    min_cost = cost
                    
                    copy(best_node_values, it.node_values)
                    best_a_count = a_count
                    
                    min_a_cost = a_cost
                    min_b_cost = b_cost
                    best_split_point = split_point
                    best_split_axis  = split_axis
                }
            }
        }
        
        if min_cost < it.cost {
            copy(it.node_values, best_node_values)
            
            middle := linear_blend(node.bounds.min[best_split_axis], node.bounds.max[best_split_axis], best_split_point)
            
            a_bounds := node.bounds
            b_bounds := node.bounds
            a_bounds.max[best_split_axis] = middle
            b_bounds.min[best_split_axis] = middle
            
            node.first.subnode = cast(Node_Index) len(tree)
            
            sub_a_values := it.node_values[:best_a_count]
            sub_b_values := it.node_values[best_a_count:]
            
            append(tree, Tree_Node { bounds = a_bounds })
            append(tree, Tree_Node { bounds = b_bounds })
            
            // @cleanup tree may have been reallocated
            node = &tree[it.index]
            
            if it.depth+1 < max_depth {
                append(stack, Node_Info { node.first.subnode+0, min_a_cost, it.depth+1, sub_a_values })
                append(stack, Node_Info { node.first.subnode+1, min_b_cost, it.depth+1, sub_b_values })
            } else {
                final_node_values[node.first.subnode+0] = sub_a_values
                final_node_values[node.first.subnode+1] = sub_b_values
            }
        } else {
            final_node_values[it.index] = it.node_values
        }
    }
    
    ////////////////////////////////////////////////
    
    buffer := make_slice(allocator, [] Value, len(values))
    copy(buffer, values)
    zero(values) 
    
    next_free_index: Value_Index
    
    clear(stack)
    append(stack, Node_Info{ index = Root_Index })
    
    for len(stack) > 0 {
        it := pop(stack)
        node := &tree[it.index]
        
        node_values := final_node_values[it.index] or_else {}
        
        node.bounds = rectangle_inverted_infinity(Rectangle3)
        node.value_count = cast(u32) len(node_values)
        if node.value_count != 0 {
            node.first.value = next_free_index
            
            for buffer_index, offset in node_values {
                value_index := node.first.value + cast(Value_Index) offset
                assert(values[value_index] == {})
                value := buffer[buffer_index]
                values[value_index] = value
                
                value_bounds := get_bounds(value)
                node.bounds = rectangle_union(node.bounds, value_bounds)
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
}

tree_split_point :: proc (node: ^Tree_Node) -> (max_axis: int, split_point: f32) {
    dimension := rectangle_get_dimension(node.bounds)
    
    max_axis = 0
    max_dim  := dimension[max_axis]
    for axis in 1..<len(dimension) {
        dim := dimension[axis]
        if max_dim < dim {
            max_dim  = dim
            max_axis = axis
        }
    }
    
    return max_axis, .5
}

get_bounds :: proc { get_bounds_triangle }
get_bounds_triangle :: proc (triangle: Triangle) -> Rectangle3 {
    bounds := rectangle_inverted_infinity(Rectangle3)
    bounds = rectangle_union_point(bounds, triangle.a)
    bounds = rectangle_union_point(bounds, triangle.b)
    bounds = rectangle_union_point(bounds, triangle.c)
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

inspect :: proc (nodes: [] Tree_Node, it_index: Node_Index = Root_Index, depth : u32 = 0) -> Tree_Info {
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