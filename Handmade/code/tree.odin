package main

import "core:slice"

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
    
    Work_Node :: struct {
        // used by stack traversal
        depth: u32,
        
        // used by splitting
        cost:     f32,
        index_start: u32,
        index_count: u32,
        is_final: bool,
        
        // used by both splitting and work_tree
        bounds: Rectangle3,
        
        // used by work_tree
        count: u32, // @note(viktor): if value_count == 0 then its subnodes, else its values
        first: u32, // @note(viktor): either subnodes or values
    }
    
    // @note(viktor): 
    // S = Subnodes_Per_Node
    // N = len(triangles)
    // leaves   = atmost N
    // branches = N/S parents + N/S² grandparents + ...
    // -> N leaves + branches <= 2N nodes
    work_tree := make([dynamic] Work_Node, 0, len(triangles)*2, allocator)
    work_tree.allocator = {}
    
    ////////////////////////////////////////////////
    spall_begin("prepass")
    
    triangle_bounds := make([] Rectangle3, len(triangles), allocator)
    triangle_centers: [3] [] f32
    for i in 0..<3 do triangle_centers[i] = make([] f32, len(triangles), allocator)
    
    root: Work_Node
    root.depth = 0
    root.bounds = rect_inverted_infinity(Rectangle3)
    
    all_indices := make([] u32, len(triangles), allocator)
    for triangle, value_index in triangles {
        all_indices[value_index] = cast(u32) value_index
        
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
        root.index_start = 0
        root.index_count = cast(u32) len(all_indices)
    }
    
    get_half_area :: proc (bounds: Rectangle3) -> f32 {
        dim := rect_get_dimension(bounds)
        result := fused_mul_add(dim.y, dim.z, dim.x * (dim.z + dim.y))
        return result
    }
    
    {   
        root_count := cast(f32) root.index_count
        root.cost = get_half_area(root.bounds) * root_count
    }
    append(&work_tree, root)
    
    spall_end()
    
    ////////////////////////////////////////////////
    spall_begin("allocate buffers")
    
    stack := make([dynamic] ^Work_Node, 0, Tree_Max_Depth, allocator)
    append(&stack, &work_tree[Root_Index])
    
    // @note(viktor): used by split_node, allocate only once
    temp_prefix := make([] Work_Node, len(triangles), allocator)
    temp_suffix := make([] Work_Node, len(triangles), allocator)
    spall_end()
    
    next_free_value_index: u32
    
    spall_begin("stack loop")
    for len(&stack) > 0 {
        node := pop_front(&stack)
        
        better: bool
        subs: [Subnodes_Per_Node] Work_Node
        
        // @study(viktor): We could also do a k-means clustering with k=8 for some amount of iterations.
        // Build a separate app that visualizes the splitting of this and k-means.
        
        // @note(viktor): iteratively split subs: 0 -> 0,1 -> 0,1,2,3 -> 0,1,2,3,4,5,6,7
        split: if node.depth < Tree_Max_Depth && node.index_count > Values_Per_Node {
            subs[0] = node^
            
            for count := 1; count <= Subnodes_Per_Node/2; count *= 2 {
                for i in 0..<count {
                    sort_along_axis :: #force_inline proc (a, b: u32, data: pmm) -> bool {
                        centers := cast(^[] f32) data
                        result := centers[a] < centers[b]
                        return result
                    }
                    
                    best_a, best_b: Work_Node
                    best_split_axis: int
                    
                    ////////////////////////////////////////////////
                    
                    index_start := subs[i].index_start
                    index_count := subs[i].index_count
                    
                    min_cost     := subs[i].cost
                    node_indices := all_indices[index_start:][:index_count]
                    
                    suffix := temp_suffix[:index_count]
                    prefix := temp_prefix[:index_count]
                    
                    // @speed we sort 3 times 1*1 + 2*1/2 + 4*1/4 here and once at the end
                    /// 3 * (1/1 + 2/2 + 4/4) + 1
                    // at the limit it tends to 10x the work in sorting
                    for split_axis in 0..<3 {
                        spall_begin("sort axis")
                        slice.sort_by_with_data(node_indices, sort_along_axis, &triangle_centers[split_axis])
                        spall_end()
                        
                        spall_begin("prefix and suffix")
                        s_bounds := rect_inverted_infinity(Rectangle3)
                        p_bounds := rect_inverted_infinity(Rectangle3)
                        for p_index in 0..<index_count {
                            s_index := index_count - 1 - p_index
                            prefix_index := node_indices[p_index]
                            suffix_index := node_indices[s_index]
                            
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
                        for i in 0..<index_count-1 {
                            a_count := i + 1
                            a := prefix[a_count]
                            b := suffix[a_count]
                            
                            cost := a.cost + b.cost
                            if min_cost > cost {
                                min_cost = cost
                                
                                best_split_axis = split_axis
                                best_a = a
                                best_b = b
                                best_a.index_start = index_start
                                best_a.index_count = a_count
                                best_b.index_start = index_start + a_count
                                best_b.index_count = index_count - a_count
                            }
                        }
                        spall_end()
                    }
                    
                    ////////////////////////////////////////////////
                    // @note(viktor): only accept splits that are better
                    
                    if min_cost == subs[i].cost do break split
                    
                    spall_begin("better split")
                    spall_begin("final sort")
                    slice.sort_by_with_data(node_indices, sort_along_axis, &triangle_centers[best_split_axis])
                    spall_end()
                    
                    subs[i+0]     = best_a
                    subs[i+count] = best_b
                    spall_end()
                }
            }
            
            ////////////////////////////////////////////////
            
            spall_begin("better finalize")
            better = true
            
            node.first = cast(u32) len(work_tree)
            node.bounds = rect_inverted_infinity(Rectangle3)
            
            for sub in subs {
                node.bounds = rect_union(node.bounds, sub.bounds)
                
                append(&work_tree, sub)
                added := &work_tree[len(work_tree)-1]
                added.depth = node.depth + 1
                append(&stack, added)
            }
            
            spall_end()
        }
        
        if !better {
            spall_scope("not better")
            node.is_final = true
            aligned := align(LaneWidth, node.index_count)
            
            node.count = aligned
            node.first = next_free_value_index
            next_free_value_index += node.count
        }
    }
    spall_end()
    
    ////////////////////////////////////////////////
    
    spall_begin("pack data")
    lane_triangles := make([] lane_Triangle, next_free_value_index / LaneWidth, tree_allocator)
    padded_normals := make([] Normals,       next_free_value_index,             tree_allocator)
    padded_uvs     := make([] UVs,           next_free_value_index,             tree_allocator)
    
    for &node in work_tree {
        if !node.is_final do continue
        assert(node.index_count > 0)
        
        indices := all_indices[node.index_start:][:node.index_count]
        for buffer_index, offset in indices {
            value_index := node.first + cast(u32) offset
            
            padded_normals[value_index] = normals[buffer_index]
            padded_uvs    [value_index] = uvs    [buffer_index]
            
            lane_index  := value_index / LaneWidth
            lane_offset := value_index % LaneWidth
            replace(&lane_triangles[lane_index].a,  lane_offset, triangles[buffer_index].a)
            replace(&lane_triangles[lane_index].ab, lane_offset, triangles[buffer_index].ab)
            replace(&lane_triangles[lane_index].ac, lane_offset, triangles[buffer_index].ac)
        }
    }
    spall_end()
    
    ////////////////////////////////////////////////
    
    spall_begin("pack tree")
    packed_count := (len(work_tree)+7)/8 + 1
    if work_tree[Root_Index].count != 0 { 
        packed_count = 1 // @note(viktor): all triangles fit into the root
    }
    
    tree := make([] Tree_Node, packed_count, tree_allocator)
    {
        wide      := &tree[Root_Index]
        root_node := work_tree[Root_Index]
        
        wide.bounds_min = vec_cast(lane_f32, root_node.bounds.min)
        wide.bounds_max = vec_cast(lane_f32, root_node.bounds.max)
        wide.first      = root_node.first
        wide.count      = root_node.count
    }
    
    for i := 1; i < len(work_tree); i += Subnodes_Per_Node {
        wide := &tree[1 + (i - 1) / Subnodes_Per_Node]
        
        for lane in 0..<Subnodes_Per_Node {
            child_index := i + lane
            if child_index >= len(work_tree) do break
            
            child := work_tree[child_index]
            
            replace(&wide.bounds_min, lane, child.bounds.min)
            replace(&wide.bounds_max, lane, child.bounds.max)
            replace(&wide.first,      lane, child.first)
            replace(&wide.count,      lane, child.count)
        }
    }
    
    spall_end()
    
    return lane_triangles, padded_normals, padded_uvs, tree
}

// 2.2s
// 1.8s keep triangles centers per axis