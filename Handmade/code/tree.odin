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

// @note(viktor): determined to be optimal with the stanford lucy model
Values_Per_Node   :: 32 
Subnodes_Per_Node :: 8

Tree_Max_Depth :: 32

////////////////////////////////////////////////

// @important @volatile The triangles buffer is sorted at the end.
// You need to pass all per vertex data along, so that it can be sorted alongside the vertices.
tree_build :: proc (triangles: [] Triangle, normals: [] Normals, uvs: [] UVs, tree_allocator := context.allocator) -> ([] lane_Triangle, [] Normals, [] UVs, [] Tree_Node) {
    spall_proc()
    
    assert(len(triangles) != 0)
    
    allocator := context.temp_allocator
    
    Node_Info :: struct {
        // used by stack traversal
        index: u32,
        depth: u32,
        
        // used by splitting
        cost:    f32,
        indices: [] u32,
        
        // used by both splitting and stack traversal
        bounds:  Rectangle3,
        
        // used by work_tree
        count:  u32, // @note(viktor): if value_count == 0 then its subnodes, else its values
        first:  u32, // @note(viktor): either subnodes or values
    }
    
    // @note(viktor): 
    // S = Subnodes_Per_Node
    // N = len(triangles)
    // leaves   = atmost N
    // branches = N/S parents + N/S² grandparents + ...
    // -> N leaves + branches <= 2N nodes
    // @todo(viktor): why is this not enough for large models(>100k triangles)
    
    work_tree := make([dynamic] Node_Info, 0, len(triangles)*8, allocator)
    
    ////////////////////////////////////////////////
    spall_begin("prepass")
    triangle_centers: [3] [] f32
    for i in 0..<3 do triangle_centers[i] = make([] f32, len(triangles), allocator)
    triangle_bounds  := make([] Rectangle3, len(triangles), allocator)
    
    root: Node_Info
    root.index = Root_Index
    root.depth = 0
    {
        root.bounds = rect_inverted_infinity(Rectangle3)
        
        root.indices = make([] u32, len(triangles), allocator)
        for triangle, value_index in triangles {
            root.indices[value_index] = cast(u32) value_index
            
            center := triangle.a + (triangle.ab + triangle.ac) / 3
            for i in 0..<3 {
                triangle_centers[i][value_index] = center[i]
            }
            
            bounds := rect_inverted_infinity(Rectangle3)
            bounds = rect_union_point(bounds, triangle.a)
            bounds = rect_union_point(bounds, triangle.a + triangle.ab)
            bounds = rect_union_point(bounds, triangle.a + triangle.ac)
            triangle_bounds[value_index] = bounds
            
            root.bounds = rect_union(root.bounds, bounds)
        }
        
        dim := rect_get_dimension(root.bounds)
        half_area := dim.y * dim.z + dim.x * (dim.z + dim.y)
        root.cost = half_area * cast(f32) len(root.indices)
    }
    append(&work_tree, root)
    
    spall_end()
    
    ////////////////////////////////////////////////
    spall_begin("allocate buffers")
    final_indices := make(map[u32] [] u32, allocator)
    
    stack := make([dynamic] Node_Info, 0, Tree_Max_Depth, allocator)
    append(&stack, root)
    
    // @note(viktor): used by split_node, allocate only once
    temp_prefix := make([] Node_Info, len(triangles), allocator)
    temp_suffix := make([] Node_Info, len(triangles), allocator)
    spall_end()
    
    aligned_size: u32
    
    spall_begin("stack loop")
    for len(&stack) > 0 {
        it := pop(&stack)
        
        node := &work_tree[it.index]
        
        better: bool
        subs: [Subnodes_Per_Node] Node_Info
        
        // @note(viktor): iteratively split subs: 0 -> 0,1 -> 0,1,2,3 -> 0,1,2,3,4,5,6,7
        split: if it.depth < Tree_Max_Depth && len(it.indices) > Values_Per_Node {
            subs[0] = it
            
            for count := 1; count <= Subnodes_Per_Node/2; count *= 2 {
                for i in 0..<count {
                    sort_along_axis :: #force_inline proc (a, b: u32, data: pmm) -> bool {
                        centers := cast(^[] f32) data
                        result := centers[a] < centers[b]
                        return result
                    }
                    
                    get_half_area :: proc (bounds: Rectangle3) -> f32 {
                        dim := rect_get_dimension(bounds)
                        result := fused_mul_add(dim.y, dim.z, dim.x * (dim.z + dim.y))
                        return result
                    }
                    
                    best_a, best_b: Node_Info
                    best_split_axis: int
                    
                    ////////////////////////////////////////////////
                    
                    indices  := subs[i].indices
                    min_cost := subs[i].cost
                    
                    node_count := cast(u32) len(indices)
                    suffix := temp_suffix[:node_count]
                    prefix := temp_prefix[:node_count]
                    
                    for split_axis in 0..<3 {
                        spall_begin("sort axis")
                        slice.sort_by_with_data(indices, sort_along_axis, &triangle_centers[split_axis])
                        spall_end()
                        
                        spall_begin("prefix and suffix")
                        s_bounds := rect_inverted_infinity(Rectangle3)
                        p_bounds := rect_inverted_infinity(Rectangle3)
                        for p_index in 0..<len(indices) {
                            s_index := len(indices) - 1 - p_index
                            prefix_index := indices[p_index]
                            suffix_index := indices[s_index]
                            
                            p_bounds = rect_union(p_bounds, triangle_bounds[prefix_index])
                            s_bounds = rect_union(s_bounds, triangle_bounds[suffix_index])
                            
                            a_count := cast(f32) p_index
                            b_count := cast(f32) p_index + 1
                            
                            prefix[p_index].cost   = get_half_area(p_bounds) * a_count
                            suffix[s_index].cost   = get_half_area(s_bounds) * b_count
                            prefix[p_index].bounds = p_bounds
                            suffix[s_index].bounds = s_bounds
                        }
                        spall_end()
                        
                        spall_begin("search cost")
                        for i in 0..<node_count-1 {
                            a_count := i + 1
                            a := prefix[a_count]
                            b := suffix[a_count]
                            
                            cost := a.cost + b.cost
                            if min_cost > cost {
                                min_cost = cost
                                
                                best_split_axis = split_axis
                                best_a = a
                                best_b = b
                                best_a.indices = indices[:a_count]
                                best_b.indices = indices[a_count:]
                            }
                        }
                        spall_end()
                    }
                    
                    ////////////////////////////////////////////////
                    // @note(viktor): only accept splits that are better
                    
                    if min_cost == subs[i].cost do break split
                    
                    spall_begin("better split")
                    spall_begin("final sort")
                    slice.sort_by_with_data(indices, sort_along_axis, &triangle_centers[best_split_axis])
                    spall_end()
                    
                    subs[i+0]     = best_a
                    subs[i+count] = best_b
                    spall_end()
                }
            }
            
            spall_begin("better finalize")
            better = true
            node.first = cast(u32) len(work_tree)
            
            node.bounds = rect_inverted_infinity(Rectangle3)
            for sub in subs {
                append(&work_tree, sub)
                node.bounds = rect_union(node.bounds, sub.bounds)
            }
            
            for &sub, index in subs {
                sub.index = node.first + auto_cast index
                sub.depth = it.depth + 1
                append(&stack, sub)
            }
            spall_end()
        }
        
        if !better {
            final_indices[it.index] = it.indices
            aligned_size += align(LaneWidth, cast(u32) len(it.indices))
        }
    }
    spall_end()
    
    ////////////////////////////////////////////////
    
    spall_begin("post pass")
    aligned_count := align(Subnodes_Per_Node, len(work_tree) - 1) + 1
    tree := make([] Node_Info, aligned_count, allocator)
    copy(tree, work_tree[:])
    
    ////////////////////////////////////////////////
    
    lane_triangles := make([] lane_Triangle, aligned_size / LaneWidth, tree_allocator)
    padded_normals := make([] Normals, aligned_size, tree_allocator)
    padded_uvs     := make([] UVs, aligned_size, tree_allocator)
    
    next_free_value_index: u32
    for &node, node_index in tree {
        indices := final_indices[cast(u32) node_index] or_continue
        assert(len(indices) > 0)
        
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
        root_node := tree[0]
        
        wide.bounds_min = vec_cast(lane_f32, root_node.bounds.min)
        wide.bounds_max = vec_cast(lane_f32, root_node.bounds.max)
        wide.first      = root_node.first
        wide.count      = root_node.count
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
    
    spall_end()
    
    return lane_triangles, padded_normals, padded_uvs, packed_tree
}

// 2.2s
// 1.8s keep triangles centers per axis

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
