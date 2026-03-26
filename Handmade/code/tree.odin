package main

import "core:slice"
import "core:time"

// @important 
// Currently the subnodes always start on even indices.
// That means that they are pairwise on the same cacheline.
// This is because Nil and Root are appended as a pair and then
// all subnodes are always appended as pairs.

Tree :: [] Tree_Node

Tree_Node :: struct #align(32) {
    bounds:      Rectangle3,
    count: u32, // @note(viktor): if value_count == 0 then its subnodes, else its values
    first: u32, // @note(viktor): either subnodes or values
}

Root_Index  :: 0

Subnodes_Per_Node :: 8
Values_Per_Node   :: 128 // determined through experimentation, higher is better, after this point there were no more gains, this may be because the most complex model is then reduced to a depth 1 tree

Tree_Max_Depth :: 32

Node_Info :: struct {
    index: u32,
    depth: u32,
    
    cost:  f32,
    indices: [] u32,
}

Split_Node :: struct {
    bounds: Rectangle3,
    
    cost: f32,
    indices: [] u32,
}

////////////////////////////////////////////////

// @important @volatile The triangles buffer is sorted at the end.
// You need to pass all per vertex data along, so that it can be sorted alongside the vertices.
tree_build :: proc (triangles: [] Triangle, normals: [] Normals, tree_allocator := context.allocator) -> ([] Tree_Node, [] lane_Triangle, [] Normals) {
    assert(len(triangles) != 0)
    
    allocator := context.temp_allocator
    
    // @note(viktor): 
    // S = Subnodes_Per_Node
    // N = len(triangles)
    // leaves = atmost N
    // branches = N/S parents + N/S² grandparents + ...
    // -> N leaves + branches <= 2N nodes
    work_tree := make([dynamic] Tree_Node, 0, len(triangles)*2, allocator)
    
    ////////////////////////////////////////////////
    triangle_centers := make([] v3,         len(triangles), allocator)
    triangle_bounds  := make([] Rectangle3, len(triangles), allocator)
    
    append_nothing(&work_tree)
    root_values: [] u32
    root_cost:   f32
    {
        root := &work_tree[Root_Index]
        root.bounds = rect_inverted_infinity(Rectangle3)
        
        root_values = make([] u32, len(triangles), allocator)
        for triangle, value_index in triangles {
            root_values[value_index] = cast(u32) value_index
            
            center := triangle.a + (triangle.ab + triangle.ac) / 3
            triangle_centers[value_index] = center
            
            bounds := rect_inverted_infinity(Rectangle3)
            bounds = rect_union_point(bounds, triangle.a)
            bounds = rect_union_point(bounds, triangle.a + triangle.ab)
            bounds = rect_union_point(bounds, triangle.a + triangle.ac)
            triangle_bounds[value_index] = bounds
            
            root.bounds = rect_union(root.bounds, bounds)
        }
        
        dim := rect_get_dimension(root.bounds)
        half_area := dim.y * dim.z + dim.x * (dim.z + dim.y)
        root_cost = half_area * cast(f32) len(root_values)
    }
    
    final_indices := make(map[u32] [] u32, allocator)
    
    stack := make([dynamic] Node_Info, 0, Tree_Max_Depth, allocator)
    append(&stack, Node_Info { Root_Index, 0, root_cost, root_values })
    
    // @note(viktor): used by split_node, allocate only once
    temp_indices := make([] u32,        len(triangles), allocator)
    temp_prefix  := make([] Split_Node, len(triangles), allocator)
    temp_suffix  := make([] Split_Node, len(triangles), allocator)
    for len(&stack) > 0 {
        it := pop(&stack)
        
        node := &work_tree[it.index]
        
        better: bool
        subs: [Subnodes_Per_Node] Split_Node
        
        split: if len(it.indices) > Values_Per_Node {
            subs[0].cost    = it.cost
            subs[0].indices = it.indices
            
            for count := 1; count < Subnodes_Per_Node; count *= 2 {
                for i in 0..<count {
                    best_a, best_b: Split_Node
                    
                    ////////////////////////////////////////////////
                    it_indices := subs[i].indices
                    min_cost   := subs[i].cost
                    
                    node_count := cast(u32) len(it_indices)
                    best_a_count: u32
                    best_indices := temp_indices[:node_count]
                    suffix       := temp_suffix[:node_count]
                    prefix       := temp_prefix[:node_count]
                    
                    for split_axis in 0..<3 {
                        Data :: struct {
                            split_axis: int,
                            triangle_centers: [] v3,
                        }
                        
                        data := Data { split_axis, triangle_centers }
                        slice.sort_by_with_data(it_indices, proc (a, b: u32, data_p: pmm) -> bool {
                            data := cast(^Data) data_p
                            a_center := data.triangle_centers[a]
                            b_center := data.triangle_centers[b]
                            axis := data.split_axis
                            
                            return a_center[axis] < b_center[axis]
                        }, &data)
                        
                        get_half_area :: proc (bounds: Rectangle3) -> f32 {
                            dim := rect_get_dimension(bounds)
                            result := fused_mul_add(dim.y, dim.z, dim.x * (dim.z + dim.y))
                            return result
                        }
                        
                        s_bounds := rect_inverted_infinity(Rectangle3)
                        #reverse for value_index, a_count in it_indices {
                            s_bounds = rect_union(s_bounds, triangle_bounds[value_index])
                            
                            b_count := node_count - cast(u32) a_count
                            suffix[a_count].cost   = get_half_area(s_bounds) * cast(f32) b_count
                            suffix[a_count].bounds = s_bounds
                        }
                        
                        p_bounds := rect_inverted_infinity(Rectangle3)
                        for value_index, a_count in it_indices {
                            p_bounds = rect_union(p_bounds, triangle_bounds[value_index])
                            
                            prefix[a_count].cost   = get_half_area(p_bounds) * cast(f32) a_count
                            prefix[a_count].bounds = p_bounds
                        }
                        
                        for i in 0..<node_count-1 {
                            node_index := it_indices[i]
                            
                            a_count := i + 1
                            
                            split_a := prefix[a_count]
                            split_b := suffix[a_count]
                            
                            cost := split_a.cost + split_b.cost
                            if min_cost > cost {
                                min_cost = cost
                                
                                best_a_count = a_count
                                best_a = split_a
                                best_b = split_b
                                
                                copy(best_indices, it_indices)
                            }
                        }
                    }
                    
                    // @note(viktor): only accept splits that are better
                    if min_cost == subs[i].cost do break split
                    
                    copy(it_indices, best_indices)
                    best_a.indices = it_indices[:best_a_count]
                    best_b.indices = it_indices[best_a_count:]
                    
                    ////////////////////////////////////////////////
                    
                    subs[i+0]     = best_a
                    subs[i+count] = best_b
                }
            }
            
            better = true
            node.first = cast(u32) len(work_tree)
            
            node.bounds = rect_inverted_infinity(Rectangle3)
            for sub in subs {
                append(&work_tree, Tree_Node { bounds = sub.bounds })
                node.bounds = rect_union(node.bounds, sub.bounds)
            }
            
            if it.depth+1 < Tree_Max_Depth {
                for sub, index in subs {
                    sub_index := node.first + auto_cast index
                    append(&stack, Node_Info { sub_index, it.depth+1, sub.cost, sub.indices })
                }
            } else {
                for sub, index in subs {
                    sub_index := node.first + auto_cast index
                    final_indices[sub_index] = sub.indices
                }
            }
        }
        
        if !better {
            final_indices[it.index] = it.indices
        }
    }
    
    ////////////////////////////////////////////////
    
    aligned_count := align(Subnodes_Per_Node, len(work_tree) - 1) + 1
    tree := make([] Tree_Node, aligned_count, tree_allocator)
    copy(tree, work_tree[:])
    
    ////////////////////////////////////////////////
    
    aligned_size: u32
    for _, node_index in tree {
        indices := final_indices[cast(u32) node_index] or_continue
        aligned_size += align(LaneWidth, cast(u32) len(indices))
    }
    
    ////////////////////////////////////////////////
    
    // @cleanup this cannot be called multiple times, because we add a bunch of padding 
    // triangles into the middle and those are then part of the tree in the next call.
    
    lane_triangles := make([] lane_Triangle, aligned_size / LaneWidth, tree_allocator)
    padded_normals := make([] Normals, aligned_size, tree_allocator)
    
    next_free_value_index: u32
    for &node, node_index in tree {
        indices := final_indices[cast(u32) node_index] or_continue
        if len(indices) == 0 do continue
        
        node.count = align(LaneWidth, cast(u32) len(indices))
        node.first = next_free_value_index
        next_free_value_index += node.count
        
        for buffer_index, offset in indices {
            value_index := node.first + cast(u32) offset
            
            padded_normals[value_index] = normals[buffer_index]
            
            lane_index  := value_index / LaneWidth
            lane_offset := value_index % LaneWidth
            replace(&lane_triangles[lane_index].a,  lane_offset, triangles[buffer_index].a)
            replace(&lane_triangles[lane_index].ab, lane_offset, triangles[buffer_index].ab)
            replace(&lane_triangles[lane_index].ac, lane_offset, triangles[buffer_index].ac)
        }
    }
    assert(next_free_value_index == aligned_size)
    
    return tree, lane_triangles, padded_normals
}

////////////////////////////////////////////////

Tree_Info :: struct {
    values_per_node: Stat(u32),
    depth: Stat(u32),
    
    node_count: u32,
}

inspect :: proc (nodes: [] Tree_Node, it_index: u32 = Root_Index, depth : u32 = 0) -> Tree_Info {
    it := nodes[it_index]
    value_count := it.count
    
    result: Tree_Info
    
    result.depth = stat_make(depth)
    result.values_per_node = stat_make(value_count)
    result.node_count = 1
    
    if it.count == 0 && it.first != Root_Index {
        for sub_index in it.first..< it.first + Subnodes_Per_Node {
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
