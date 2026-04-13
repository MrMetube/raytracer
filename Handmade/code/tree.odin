package main

import "core:slice"
import "core:time"



Tree_Node :: struct #align(32) {
    bounds_min: lane_v3,
    bounds_max: lane_v3,
    count:      lane_u32, // @note(viktor): if value_count == 0 then its subnodes, else its values
    first:      lane_u32, // @note(viktor): either subnodes or values
}

Root_Index  :: 0

// @note(viktor): determined to be optimal(along side 64 V/N) with the stanford lucy scene
Values_Per_Node   :: 32 
Subnodes_Per_Node :: 8

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
tree_build :: proc (triangles: [] Triangle, normals: [] Normals, uvs: [] UVs, tree_allocator := context.allocator) -> ([] lane_Triangle, [] Normals, [] UVs, [] Tree_Node) {
    assert(len(triangles) != 0)
    
    allocator := context.temp_allocator
    
    // @note(viktor): 
    // S = Subnodes_Per_Node
    // N = len(triangles)
    // leaves   = atmost N
    // branches = N/S parents + N/S² grandparents + ...
    // -> N leaves + branches <= 2N nodes
    // @todo(viktor): why is this not enough for large models(>100k triangles)
    Work_Node :: struct {
        bounds: Rectangle3,
        count:  u32, // @note(viktor): if value_count == 0 then its subnodes, else its values
        first:  u32, // @note(viktor): either subnodes or values
    }
    work_tree := make([dynamic] Work_Node, 0, len(triangles)*8, allocator)
    
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
    
    ////////////////////////////////////////////////
    final_indices := make(map[u32] [] u32, allocator)
    
    stack := make([dynamic] Node_Info, 0, Tree_Max_Depth, allocator)
    append(&stack, Node_Info { Root_Index, 0, root_cost, root_values })
    
    // @note(viktor): used by split_node, allocate only once
    temp_prefix := make([] Split_Node, len(triangles), allocator)
    temp_suffix := make([] Split_Node, len(triangles), allocator)
    
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
                    Sort_Data :: struct {
                        split_axis: int,
                        triangle_centers: [] v3,
                    }
                    
                    sort_along_axis :: proc (a, b: u32, data_p: pmm) -> bool {
                        data := cast(^Sort_Data) data_p
                        
                        a_center := data.triangle_centers[a]
                        b_center := data.triangle_centers[b]
                        axis := data.split_axis
                        
                        return a_center[axis] < b_center[axis]
                    }
                    
                    get_half_area :: proc (bounds: Rectangle3) -> f32 {
                        dim := rect_get_dimension(bounds)
                        result := fused_mul_add(dim.y, dim.z, dim.x * (dim.z + dim.y))
                        return result
                    }
                    
                    best_a, best_b: Split_Node
                    best_split_axis: int
                    
                    ////////////////////////////////////////////////
                    
                    indices  := subs[i].indices
                    min_cost := subs[i].cost
                    
                    node_count := cast(u32) len(indices)
                    best_a_count: u32
                    suffix := temp_suffix[:node_count]
                    prefix := temp_prefix[:node_count]
                    
                    for split_axis in 0..<3 {
                        data := Sort_Data { split_axis, triangle_centers }
                        slice.sort_by_with_data(indices, sort_along_axis, &data)
                        
                        s_bounds := rect_inverted_infinity(Rectangle3)
                        p_bounds := rect_inverted_infinity(Rectangle3)
                        for p_index in 0..<len(indices) {
                            s_index := len(indices) - 1 - p_index
                            prefix_value := indices[p_index]
                            suffix_value := indices[s_index]
                            
                            p_bounds = rect_union(p_bounds, triangle_bounds[prefix_value])
                            s_bounds = rect_union(s_bounds, triangle_bounds[suffix_value])
                            
                            a_count := cast(f32) p_index
                            b_count := cast(f32) p_index + 1
                            
                            prefix[p_index].cost   = get_half_area(p_bounds) * a_count
                            suffix[s_index].cost   = get_half_area(s_bounds) * b_count
                            prefix[p_index].bounds = p_bounds
                            suffix[s_index].bounds = s_bounds
                        }
                        
                        for i in 0..<node_count-1 {
                            a_count := i + 1
                            a := prefix[a_count]
                            b := suffix[a_count]
                            
                            cost := a.cost + b.cost
                            if min_cost > cost {
                                min_cost = cost
                                
                                best_split_axis = split_axis
                                best_a_count = a_count
                                best_a = a
                                best_b = b
                            }
                        }
                    }
                    
                    // @note(viktor): only accept splits that are better
                    if min_cost == subs[i].cost do break split
                    
                    data := Sort_Data { best_split_axis, triangle_centers }
                    slice.sort_by_with_data(indices, sort_along_axis, &data)
                    
                    best_a.indices = indices[:best_a_count]
                    best_b.indices = indices[best_a_count:]
                    
                    ////////////////////////////////////////////////
                    
                    subs[i+0]     = best_a
                    subs[i+count] = best_b
                }
            }
            
            better = true
            node.first = cast(u32) len(work_tree)
            
            node.bounds = rect_inverted_infinity(Rectangle3)
            for sub in subs {
                append(&work_tree, Work_Node { bounds = sub.bounds })
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
    tree := make([] Work_Node, aligned_count, allocator)
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
    // @cleanup this cannot be called multiple times, because we add a bunch of padding 
    lane_triangles := make([] lane_Triangle, aligned_size / LaneWidth, tree_allocator)
    padded_normals := make([] Normals, aligned_size, tree_allocator)
    padded_uvs     := make([] UVs, aligned_size, tree_allocator)
    
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
            padded_uvs[value_index]     = uvs[buffer_index]
            
            lane_index  := value_index / LaneWidth
            lane_offset := value_index % LaneWidth
            replace(&lane_triangles[lane_index].a,  lane_offset, triangles[buffer_index].a)
            replace(&lane_triangles[lane_index].ab, lane_offset, triangles[buffer_index].ab)
            replace(&lane_triangles[lane_index].ac, lane_offset, triangles[buffer_index].ac)
        }
    }
    assert(next_free_value_index == aligned_size)
    
    packed_count := (len(tree)+7)/8 + 1
    if tree[0].count != 0 { 
        packed_count = 1 // @note(viktor): all triangles fit into the root
    }
    
    packed_tree := make([] Tree_Node, packed_count, tree_allocator)
    {
        wide := &packed_tree[0]
        root := tree[0]
        
        wide.bounds_min = vec_cast(lane_f32, root.bounds.min)
        wide.bounds_max = vec_cast(lane_f32, root.bounds.max)
        wide.first      = root.first
        wide.count      = root.count
    }
    
    for i := 1; i < len(tree); i += Subnodes_Per_Node {
        wide := &packed_tree[1 + (i - 1) / Subnodes_Per_Node]
        
        for lane in 0..<Subnodes_Per_Node {
            child_index := i + lane
            if child_index >= len(tree) do break
            
            child := tree[child_index]
            
            replace(&wide.bounds_min, lane, child.bounds.min)
            replace(&wide.bounds_max, lane, child.bounds.max)
            replace(&wide.first,      lane, child.first)
            replace(&wide.count,      lane, child.count)
        }
    }
    
    return lane_triangles, padded_normals, padded_uvs, packed_tree
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
