package main

import "core:fmt"
import "core:math"

BiTree :: proc($T: typeid, origin: [1]f32, extent: [1]f32) -> BinaryTree(T, 1) {
	return BinaryTree(T, 1){origin = origin, extent = extent}
}
QuadTree :: proc($T: typeid, origin: [2]f32, extent: [2]f32) -> BinaryTree(T, 2) {
	return BinaryTree(T, 2){origin = origin, extent = extent}
}
OctTree :: proc($T: typeid, origin: [3]f32, extent: [3]f32) -> BinaryTree(T, 3) {
	return BinaryTree(T, 3){origin = origin, extent = extent}
}

// TODO maybe constant capacity
// TODO store root / parent - to go back up
BinaryTree :: struct($Type: typeid, $Dimensions: u8) where Dimensions > 0 {
	using bounds: Aabb(Dimensions),
	values:       [dynamic]BinaryTreeItem(Type, Dimensions),
	subnodes:     [1 << Dimensions]^BinaryTree(Type, Dimensions),
}

BinaryTreeItem :: struct($Type: typeid, $Dimensions: u8) {
	bounds: Aabb(Dimensions),
	value:  Type,
}

binary_tree_init :: proc(t: ^BinaryTree($T, $D), origin: [D]f32, extent: [D]f32) {
	t.origin = origin
	t.extent = extent
}
// For higher dimensionals trees just use an index(u16, u32, ...)
Sector :: enum u8 {
	// 1D
	W   = 0,
	E   = 1,
	// 2D
	NW  = 0,
	NE  = 1,
	SW  = 2,
	SE  = 3,
	// 3D
	TNW = 0,
	TNE = 1,
	TSW = 2,
	TSE = 3,
	BNW = 4,
	BNE = 5,
	BSW = 6,
	BSE = 7,
}

binary_tree_select :: proc(t: ^BinaryTree($T, $D), selection: Sector) -> BinaryTree(T, D) {
	when D > 8 {
		unimplemented("Dimensions are limited to 8")
	}
	mask: u8
	for shift in 0 ..< D {
		mask |= 1 << shift
	}
	selection := u8(selection) & mask
	assert(t.subnodes[selection] != nil)
	return t.subnodes[selection]^
}

binary_tree_subdivide :: proc(t: ^BinaryTree($T, $D), allocator := context.allocator) {
	half := t.extent * .5
	for sector_index in 0 ..< (1 << D) {
		offset: [D]f32 = ---
		for axis in 0 ..< D {
			mask := 1 << axis
			is_positive := sector_index & mask == 0

			// for the x-axis we iterate: - -> + (W -> E)
			// for the y- and z-axis (and further) we iterate: + -> - (N->S, T->B)
			if axis == 0 {
				offset[axis] = half[axis] if !is_positive else -half[axis]
			} else {
				offset[axis] = half[axis] if is_positive else -half[axis]
			}
		}
		t.subnodes[sector_index] = new(BinaryTree(T, D), allocator)
		binary_tree_init(t.subnodes[sector_index], t.origin + offset, half)
	}
}

binary_tree_query_range :: proc(
	t: ^BinaryTree($T, $D),
	range: Aabb(D),
	result: ^[dynamic]BinaryTreeItem(T, D),
) {
	if !aabb_intersects(t.bounds, range) do return

	if value, ok := t.value.?; ok {
		if aabb_contains(range, value.position) {
			append(result, value)
		}
	} else if t.subnodes != nil {
		for sub in subnodes {
			binary_tree_query_range(sub, range, result)
		}
	}
}

binary_tree_append :: proc {
	binary_tree_append_by_aabb,
	binary_tree_append_by_position,
}

// TODO no recursion
binary_tree_append_by_position :: proc(t: ^BinaryTree($T, $D), value: T, position: [D]f32) -> b8 {
	if !aabb_contains(t.bounds, position) do return false

	if len(t.values) < len(t.subnodes) {
		item := BinaryTreeItem(T, D) {
			value = value,
			bounds = {origin = position, extent = 1},
		}
		append(&t.values, item)
	} else if t.subnodes == nil {
		binary_tree_subdivide(t)
		return binary_tree_append(t, value, position)
	} else {
		for sub in t.subnodes {
			if binary_tree_append(sub, value, position) do return true
		}
	}
	return true
}

binary_tree_append_by_aabb :: proc(t: ^BinaryTree($T, $D), value: T, bounds: Aabb(D)) -> b8 {
	if !aabb_contains_aabb(t.bounds, bounds) do return false
	todo: [dynamic]^BinaryTree(T, D)
    append(&todo, t)
	for len(todo) > 0 {
		t := pop(&todo)
		if len(t.values) < (1<<D) {
			append(&t.values, BinaryTreeItem(T, D){value = value, bounds = bounds})
			return true
		}
		if t.subnodes == nil do binary_tree_subdivide(t)
		sub_could_contain: b8
		for sub in t.subnodes {
			could_contain := aabb_contains_aabb(sub.bounds, bounds)
			sub_could_contain |= could_contain
			if could_contain {
				append(&todo, sub)
			}
		}
		if !sub_could_contain {
			append(&t.values, BinaryTreeItem(T, D){value = value, bounds = bounds})
			return true
		}
	}
	return false
}
