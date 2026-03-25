package main

import "core:slice"
import "core:time"

Node_Index  :: distinct u32
Value_Index :: distinct u32

lane_Node_Index  :: #simd [LaneWidth] Node_Index

// @important 
// Currently the subnodes always start on even indices.
// That means that they are pairwise on the same cacheline.
// This is because Nil and Root are appended as a pair and then
// all subnodes are always appended as pairs.

Tree :: [] Tree_Node

Tree_Node :: struct #align(32) {
    bounds:      Rectangle3,
    value_count: u32, // @note(viktor): if value_count == 0 then its subnode, else its value
    first: struct #raw_union {
        value:   Value_Index,
        subnode: Node_Index, // @note(viktor): the other 7 must follow directly after the first
    },
}

Root_Index  :: 0

Subnodes_Per_Node :: 8
Values_Per_Node   :: 128 // determined through experimentation, higher is better, after this point there were no more gains, this may be because the most complex model is then reduced to a depth 1 tree

Tree_Max_Depth :: 32

Node_Info :: struct {
    index: Node_Index,
    depth: u32,
    
    cost:  f32,
    indices: [] Value_Index,
}

Split_Node :: struct {
    bounds: Rectangle3,
    
    cost: f32,
    indices: [] Value_Index,
}

////////////////////////////////////////////////

// @important @volatile The triangles buffer is sorted at the end.
// You need to pass all per vertex data along, so that it can be sorted alongside the vertices.
tree_build :: proc (triangles: ^[] Triangle, normals: ^[] Normals, tree_allocator := context.allocator) -> [] Tree_Node {
    allocator := context.temp_allocator
    
    // @note(viktor): 
    // S = Subnodes_Per_Node
    // N = len(triangles)
    // leaves = atmost N
    // branches = N/S parents + N/S² grandparents + ...
    // -> N leaves + branches <= 2N nodes
    work_tree := make([] Tree_Node, len(triangles)*2, allocator)
    if len(triangles) == 0 do return nil
    
    ////////////////////////////////////////////////
    next_free_tree_index := cast(Node_Index) 1 // root
    
    triangle_centers := make([] v3, len(triangles), allocator)
    triangle_bounds  := make([] Rectangle3, len(triangles), allocator)
    
    root := &work_tree[Root_Index]
    root.bounds = rectangle_inverted_infinity(Rectangle3)
    
    root_values := make([] Value_Index, len(triangles), allocator)
    for value_index in 0 ..< cast(Value_Index) len(triangles) {
        root_values[value_index] = value_index
        
        triangle := triangles[value_index]
        
        center := triangle.a + (triangle.ab + triangle.ac) / 3
        triangle_centers[value_index] = center
        
        bounds := rectangle_inverted_infinity(Rectangle3)
        bounds = rectangle_union_point(bounds, triangle.a)
        bounds = rectangle_union_point(bounds, triangle.a + triangle.ab)
        bounds = rectangle_union_point(bounds, triangle.a + triangle.ac)
        triangle_bounds[value_index] = bounds
        
        root.bounds = rectangle_union(root.bounds, bounds)
    }
    
    root_area_half: f32
    {
        dim := rectangle_get_dimension(root.bounds)
        root_area_half = dim.y * dim.z + dim.x * (dim.z + dim.y)
    }
    root_cost := root_area_half * cast(f32) len(triangles)
    
    final_indices: map[Node_Index] [] Value_Index
    final_indices.allocator = allocator
        
    _stack := make([dynamic] Node_Info, 0, Tree_Max_Depth, allocator)
    stack  := &_stack
    
    append(stack, Node_Info { Root_Index, 0, root_cost, root_values })
    
    temp_indices := make_slice([] Value_Index, len(triangles), allocator)
    
    for len(stack) > 0 {
        it := pop(stack)
        
        node := &work_tree[it.index]
        
        all_better := false
        subs: [Subnodes_Per_Node] Split_Node
        split: if len(it.indices) > Values_Per_Node {
            s0, s1 := split_node(work_tree, it.cost, it.indices, triangle_centers, triangle_bounds, temp_indices) or_break split
            
            s00, s10 := split_node(work_tree, s0.cost, s0.indices, triangle_centers, triangle_bounds, temp_indices) or_break split
            s01, s11 := split_node(work_tree, s1.cost, s1.indices, triangle_centers, triangle_bounds, temp_indices) or_break split
            
            s0, s1  = split_node(work_tree, s00.cost, s00.indices, triangle_centers, triangle_bounds, temp_indices) or_break split
            s2, s3 := split_node(work_tree, s01.cost, s01.indices, triangle_centers, triangle_bounds, temp_indices) or_break split
            s4, s5 := split_node(work_tree, s10.cost, s10.indices, triangle_centers, triangle_bounds, temp_indices) or_break split
            s6, s7 := split_node(work_tree, s11.cost, s11.indices, triangle_centers, triangle_bounds, temp_indices) or_break split
            
            subs[0] = s0
            subs[1] = s1 
            subs[2] = s2
            subs[3] = s3
            subs[4] = s4
            subs[5] = s5
            subs[6] = s6
            subs[7] = s7
            all_better = true
        }
        
        if all_better {
            node.first.subnode = next_free_tree_index
            
            for sub in subs {
                work_tree[next_free_tree_index] = Tree_Node { bounds = sub.bounds }
                next_free_tree_index += 1
            }
            
            if it.depth+1 < Tree_Max_Depth {
                for sub, index in subs {
                    sub_index := node.first.subnode + auto_cast index
                    sub_info := Node_Info { sub_index, it.depth+1, sub.cost, sub.indices }
                    append(stack, sub_info)
                }
            } else {
                for sub, index in subs {
                    sub_index := node.first.subnode + auto_cast index
                    final_indices[sub_index] = sub.indices
                }
            }
        } else {
            final_indices[it.index] = it.indices
        }
    }
    
    ////////////////////////////////////////////////
    
    count := align(Subnodes_Per_Node, len(work_tree) - 1) + 1
    tree  := make([] Tree_Node, count, tree_allocator)
    copy(tree, work_tree)
    
    aligned_size: u32
    for &node, node_index in tree {
        indices := final_indices[cast(Node_Index) node_index] or_continue
        aligned_size += align(LaneWidth, cast(u32) len(indices))
    }
    
    // @cleanup call site
    buffer_t := make([] Triangle, aligned_size, allocator)
    buffer_n := make([] Normals,  aligned_size, allocator)
    copy(buffer_t, triangles^)
    copy(buffer_n, normals^)
    delete(triangles^)
    delete(normals^)
    triangles^ = make([] Triangle, aligned_size, tree_allocator)
    normals^   = make([] Normals,  aligned_size, tree_allocator)
    
    next_free_value_index: Value_Index
    
    for &node, node_index in tree {
        indices := final_indices[cast(Node_Index) node_index] or_continue
        
        node.value_count = align(LaneWidth, cast(u32) len(indices))
        if node.value_count != 0 {
            node.first.value       = next_free_value_index
            next_free_value_index += cast(Value_Index) node.value_count
            
            for buffer_index, offset in indices {
                value_index := node.first.value + cast(Value_Index) offset
                assert(triangles[value_index] == {})
                assert(normals[value_index] == {})
                triangles[value_index] = buffer_t[buffer_index]
                normals[value_index]   = buffer_n[buffer_index]
            }
        }
    }
    assert(next_free_value_index == cast(Value_Index) len(buffer_t))
    
    #reverse for &node in tree {
        // @note(viktor): leaf nodes are already fitted
        if node.value_count == 0 {
            bounds := rectangle_inverted_infinity(Rectangle3)
            for subnode in cast(Node_Index) 0 ..< Subnodes_Per_Node {
                sub := tree[node.first.subnode + subnode]
                bounds = rectangle_union(bounds, sub.bounds)
            }
            node.bounds = bounds
        }
    }
    
    return tree
}

split_node :: proc (tree: [] Tree_Node, it_cost: f32, it_indices: [] Value_Index, triangle_centers: [] v3, triangle_bounds: [] Rectangle3, temp_indices: [] Value_Index) -> (Split_Node, Split_Node, bool) {
    min_cost := +Infinity
    best_a_count: u32
    best_split_axis: int
    
    best_indices := temp_indices[:len(it_indices)]
    
    best_subs: [2] Split_Node
    best_a := &best_subs[0]
    best_b := &best_subs[1]
    
    for split_axis in 0..<3 {
        Data :: struct {
            split_axis: int,
            triangle_centers: [] v3,
        }
        
        data := Data { split_axis, triangle_centers }
        slice.sort_by_with_data(it_indices, proc (a, b: Value_Index, data_p: pmm) -> bool {
            data := cast(^Data) data_p
            a_center := data.triangle_centers[a]
            b_center := data.triangle_centers[b]
            
            return a_center[data.split_axis] < b_center[data.split_axis]
        }, &data)
        
        split_subs: [2] Split_Node
        a := &split_subs[0]
        b := &split_subs[1]
        
        a.bounds = rectangle_inverted_infinity(Rectangle3)
        b.bounds = rectangle_inverted_infinity(Rectangle3)
        
        // @leak
        suffix_bounds := make([] Rectangle3, len(it_indices), context.temp_allocator)
        {
            bounds := rectangle_inverted_infinity(Rectangle3)
            #reverse for value_index, it_index in it_indices {
                value_bounds := triangle_bounds[value_index]
                bounds = rectangle_union(bounds, value_bounds)
                suffix_bounds[it_index] = bounds
            }
        }
        
        node_count := cast(u32) len(it_indices)
        for i in 0..<node_count-1 {
            node_index := it_indices[i]
            
            a_count := i + 1
            b_count := node_count - a_count
            
            // a now has node_index
            {
                bounds := triangle_bounds[node_index]
                a.bounds = rectangle_union(a.bounds, bounds)
            }
            
            // b now loses node_index
            b.bounds = suffix_bounds[a_count]
            
            a_dim := rectangle_get_dimension(a.bounds)
            b_dim := rectangle_get_dimension(b.bounds)
            a_area_half := fused_mul_add(a_dim.y, a_dim.z, a_dim.x * (a_dim.z + a_dim.y))
            b_area_half := fused_mul_add(b_dim.y, b_dim.z, b_dim.x * (b_dim.z + b_dim.y))
            
            a.cost = a_area_half * cast(f32) a_count
            b.cost = b_area_half * cast(f32) b_count
            
            cost := a.cost + b.cost
            
            if min_cost > cost {
                min_cost = cost
                
                best_a_count    = a_count
                best_subs       = split_subs
                best_split_axis = split_axis
                
                copy(best_indices, it_indices)
            }
        }
    }
    
    better := min_cost < it_cost
    if better {
        copy(it_indices, best_indices)
        
        best_a.indices = it_indices[:best_a_count]
        best_b.indices = it_indices[best_a_count:]
    }
    
    return best_subs[0], best_subs[1], better
}

////////////////////////////////////////////////

Tree_Info :: struct {
    values_per_node: Stat(u32),
    depth: Stat(u32),
    
    node_count: u32,
}

inspect :: proc (nodes: [] Tree_Node, it_index: Node_Index = Root_Index, depth : u32 = 0) -> Tree_Info {
    it := nodes[it_index]
    value_count := it.value_count
    
    result: Tree_Info
    
    result.depth = stat_make(depth)
    result.values_per_node = stat_make(value_count)
    result.node_count = 1
    
    if it.value_count == 0 && it.first.subnode != Root_Index {
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

////////////////////////////////////////////////

Stat :: struct ($T: typeid) {
    min, max, sum, count: T,
    avg: f64,
}

stat_init :: proc { stat_init_nil, stat_init_value }
stat_init_nil :: proc (stat: ^Stat($T)) {
    stat^ = {
        min = max(T),
        max = min(T),
    }
}
stat_init_value :: proc (stat: ^Stat($T), value: T) {
    stat_init(stat)
    stat_update(stat, value)
}
stat_make :: proc (value: $T) -> Stat(T) {
    result: Stat(T)
    stat_update(&result, value)
    return result
}

stat_update :: proc { stat_update_time, stat_update_stat, stat_update_value }
stat_update_stat :: proc (stat: ^Stat($T), other: Stat(T)) {
    stat.min    = min(stat.min, other.min)
    stat.max    = max(stat.max, other.max)
    stat.sum   += other.sum
    stat.count += other.count
}
stat_update_value :: proc (stat: ^Stat($T), value: T) {
    stat.min    = min(stat.min, value)
    stat.max    = max(stat.max, value)
    stat.sum   += value
    stat.count += 1
}
stat_update_time :: proc (stat: ^Stat(time.Duration), value: time.Duration) {
    stat.min    = min(stat.min, value)
    stat.max    = max(stat.max, value)
    stat.sum   += value
    stat.count += 1
}

stat_finalize :: proc (stat: ^Stat($T)) {
    if stat.count > 0 {
        stat.avg = cast(f64) stat.sum / cast(f64) stat.count
    }
}
