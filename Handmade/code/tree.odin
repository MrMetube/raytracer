package main

import "core:slice"

Node_Index  :: distinct u16
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

tree_append_value :: proc (values: ^map [Node_Index] [dynamic] Value_Index, node_index: Node_Index, value_index: Value_Index) {
    node_values, ok := &values[node_index]
    assert(ok)
    append(node_values, value_index)
}

tree_append_node :: proc (values: ^map [Node_Index] [dynamic] Value_Index, tree: ^[dynamic] Tree_Node, bounds: Rectangle3) {
    node_index := cast(Node_Index) len(tree)
    append(tree, Tree_Node{ bounds = bounds })
    values[node_index] = make_dynamic_array(values.allocator, [dynamic] Value_Index, 0, 4)
}

tree_build :: proc (allocator: Allocator, tree: ^[dynamic] Tree_Node, values: [] $Value, max_depth: u32) {
    clear(tree)
    
    // @waste only the leafs need values
    all_values: map [Node_Index] [dynamic] Value_Index
    all_values.allocator = allocator
    
    values_bounds := make_dynamic_array(allocator, [dynamic] Rectangle3, 0, len(values))
    tree_append_node(&all_values, tree, {}) // nil
    tree_append_node(&all_values, tree, {}) // root
    if len(values) == 0 do return
    
    ////////////////////////////////////////////////
    
    root := &tree[Root_Index]
    root.bounds = rectangle_inverted_infinity(Rectangle3)
    for value_index in cast(Value_Index) 0 ..< cast(Value_Index) len(values) {
        value_bounds := get_bounds(values[value_index])
        append(&values_bounds, value_bounds)
        
        root.bounds = rectangle_union(root.bounds, value_bounds)
        center := rectangle_get_center(value_bounds)
        assert(rectangle_contains_inclusive(root.bounds, center))
        tree_append_value(&all_values, Root_Index, value_index)
    }
    root.value_count = cast(u32) len(values)
    
    root_area_half: f32
    {
        dim := rectangle_get_dimension(root.bounds)
        root_area_half = dim.y * dim.z + dim.x * dim.z + dim.x * dim.y
    }
    root_cost := root_area_half * cast(f32) root.value_count
        
    Node_Info :: struct {
        index: Node_Index,
        cost:  f32,
        depth: u32,
    }
    _stack  := make_dynamic_array(allocator, [dynamic] Node_Info, 0, max_depth)
    stack  := &_stack
    
    clear(stack)
    append(stack, Node_Info { Root_Index, root_cost, 0 })
    /* 
    
render time 
    before
    233 ms
    
    after
    220 ms
    
build time
    1024
        building tree took 108.23ms
        tree info:
                    nodes: 93
                    depth: max = 6, avg = 4.95
        values per node: max = 829, avg = 37.51
    
    8192
        building tree took 847.5836ms
        tree info:
                    nodes: 93
                    depth: max = 6, avg = 4.95
        values per node: max = 829, avg = 37.51
        
        building tree took 838.8014ms
        tree info:
                    nodes: 63
                    depth: max = 6, avg = 4.79
        values per node: max = 916, avg = 55.37
        
        building tree took 391.4135ms
        tree info:
                    nodes: 63
                    depth: max = 6, avg = 4.79
        values per node: max = 916, avg = 55.37
        
        building tree took 210.2519ms
        tree info:
                    nodes: 63
                    depth: max = 6, avg = 4.79
        values per node: max = 916, avg = 55.37
        
        building tree took 74.7704ms
        tree info:
                    nodes: 63
                    depth: max = 6, avg = 4.79
        values per node: max = 916, avg = 55.37
        
        building tree took 63.7527ms
        tree info:
                    nodes: 63
                    depth: max = 6, avg = 4.79
        values per node: max = 916, avg = 55.37
    
    16384
        building tree took 125.1959ms
        tree info:
                    nodes: 79
                    depth: max = 6, avg = 4.86
        values per node: max = 829, avg = 44.15
    */
    
    for len(stack) > 0 {
        it := pop(stack)
        
        node := &tree[it.index]
        
        node_values, ok := &all_values[it.index]
        assert(ok)
        
        // @speed we can probably do tests in parallel by doing it LaneWide
        
        min_cost := +Infinity
        min_a_cost: f32
        min_b_cost: f32
        best_split_point: f32
        best_split_axis: int
        
        // @todo(viktor): reduce this to something reasonable once we have bigger, or just more models
        attempts :: 16384
        for split_axis in 0..<3 {
            Data :: struct {
                split_axis: int,
                values_bounds: [] Rectangle3,
            }
            data := Data { split_axis, values_bounds[:] }
            slice.sort_by_with_data(node_values[:], proc(a, b: Value_Index, data_p: pmm) -> bool {
                data := cast(^Data) data_p
                a_center := rectangle_get_center(data.values_bounds[a])
                b_center := rectangle_get_center(data.values_bounds[b])
                
                return a_center[data.split_axis] < b_center[data.split_axis]
            }, &data)
            
            for i in 0 ..< attempts {
                split_point := linear_remap(cast(f32) i, -1, attempts, 0, 1)
                
                dimension := rectangle_get_dimension(node.bounds)
                a_area_half, b_area_half: f32
                {
                    a_dim := dimension
                    a_dim[split_axis] *= split_point
                    a_area_half = a_dim.y * a_dim.z + a_dim.x * a_dim.z + a_dim.x * a_dim.y
                }
                {
                    b_dim := dimension
                    b_dim[split_axis] *= (1-split_point)
                    b_area_half = b_dim.y * b_dim.z + b_dim.x * b_dim.z + b_dim.x * b_dim.y
                }
                middle := linear_blend(node.bounds.min[split_axis], node.bounds.max[split_axis], split_point)
                
                a_count: f32
                {
                    left: int
                    for right := len(node_values); left < right; {
                        it_index := (left + right) / 2
                        
                        value_index  := node_values[it_index]
                        value_bounds := values_bounds[value_index]
                        center := rectangle_get_center(value_bounds)
                        
                        if center[split_axis] < middle {
                            left = it_index + 1
                        } else {
                            right = it_index
                        }
                    }
                    
                    a_count = cast(f32) left
                }
                b_count := cast(f32) len(node_values) - a_count
                
                a_cost := a_area_half * a_count
                b_cost := b_area_half * b_count
                cost := a_cost + b_cost
                
                if min_cost > cost {
                    min_cost = cost
                    min_a_cost = a_cost
                    min_b_cost = b_cost
                    best_split_point = split_point
                    best_split_axis  = split_axis
                }
            }
        }
        
        if min_cost < it.cost {
            middle := linear_blend(node.bounds.min[best_split_axis], node.bounds.max[best_split_axis], best_split_point)
            
            a_bounds := node.bounds
            b_bounds := node.bounds
            a_bounds.max[best_split_axis] = middle
            b_bounds.min[best_split_axis] = middle
            
            
            node.first.subnode = cast(Node_Index) len(tree)
            tree_append_node(&all_values, tree, a_bounds)
            tree_append_node(&all_values, tree, b_bounds)
            // @cleanup tree may have been reallocated
            node = &tree[it.index]
            
            
            
            for value_index in node_values {
                value_bounds := values_bounds[value_index]
                
                into_index := node.first.subnode+1
                center := rectangle_get_center(value_bounds)
                if rectangle_contains_inclusive(a_bounds, center) {
                    into_index = node.first.subnode+0
                } else {
                    assert(rectangle_contains_inclusive(b_bounds, center))
                }
                tree_append_value(&all_values, into_index, value_index)
            }
            clear(node_values)
            node.value_count = 0

            
            
            if it.depth+1 < max_depth {
                append(stack, Node_Info { node.first.subnode+0, min_a_cost, it.depth+1 })
                append(stack, Node_Info { node.first.subnode+1, min_b_cost, it.depth+1 })
            }
        }
    }
    clear(&values_bounds)
    
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
        
        value_indices, ok := all_values[it.index]
        assert(ok)
        
        node.bounds = rectangle_inverted_infinity(Rectangle3)
        node.value_count = cast(u32) len(value_indices)
        if node.value_count != 0 {
            node.first.value = next_free_index
            
            for buffer_index, offset in value_indices {
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