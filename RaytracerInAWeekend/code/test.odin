package main

import "core:fmt"
import "core:testing"
// TODO - aabb contains and intersects
// TODO - binary tree append

@(test)
test_binary_tree_select_1D :: proc(t: ^testing.T) {
	b := BiTree(u64, 0, 2)
	binary_tree_subdivide(&b)

	west := BiTree(u64, -1, 1)
	east := BiTree(u64, 1, 1)

	testing.expect_value(t, binary_tree_select(&b, .W).origin, west.origin)
	testing.expect_value(t, binary_tree_select(&b, .NW).origin, west.origin)
	testing.expect_value(t, binary_tree_select(&b, .SW).origin, west.origin)
	testing.expect_value(t, binary_tree_select(&b, .TNW).origin, west.origin)
	testing.expect_value(t, binary_tree_select(&b, .TSW).origin, west.origin)
	testing.expect_value(t, binary_tree_select(&b, .BNW).origin, west.origin)
	testing.expect_value(t, binary_tree_select(&b, .BSW).origin, west.origin)

	testing.expect_value(t, binary_tree_select(&b, .E).origin, east.origin)
	testing.expect_value(t, binary_tree_select(&b, .NE).origin, east.origin)
	testing.expect_value(t, binary_tree_select(&b, .SE).origin, east.origin)
	testing.expect_value(t, binary_tree_select(&b, .TNE).origin, east.origin)
	testing.expect_value(t, binary_tree_select(&b, .TSE).origin, east.origin)
	testing.expect_value(t, binary_tree_select(&b, .BNE).origin, east.origin)
	testing.expect_value(t, binary_tree_select(&b, .BSE).origin, east.origin)

	direction := []Sector{.W, .E}
	for i in 0 ..< len(direction) {
		testing.expect_value(
			t,
			binary_tree_select(&b, Sector(i)).origin,
			binary_tree_select(&b, direction[i]).origin,
		)
	}
}

@(test)
test_binary_tree_select_2D :: proc(t: ^testing.T) {
	b := QuadTree(u64, 0, 2)
	binary_tree_subdivide(&b)

	north_west := QuadTree(u64, [2]f32{-1, 1}, 1)
	north_east := QuadTree(u64, [2]f32{1, 1}, 1)
	south_west := QuadTree(u64, [2]f32{-1, -1}, 1)
	south_east := QuadTree(u64, [2]f32{1, -1}, 1)

	testing.expect_value(t, binary_tree_select(&b, .NW).origin, north_west.origin)
	testing.expect_value(t, binary_tree_select(&b, .TNW).origin, north_west.origin)
	testing.expect_value(t, binary_tree_select(&b, .BNW).origin, north_west.origin)

	testing.expect_value(t, binary_tree_select(&b, .SW).origin, south_west.origin)
	testing.expect_value(t, binary_tree_select(&b, .TSW).origin, south_west.origin)
	testing.expect_value(t, binary_tree_select(&b, .BSW).origin, south_west.origin)

	testing.expect_value(t, binary_tree_select(&b, .NE).origin, north_east.origin)
	testing.expect_value(t, binary_tree_select(&b, .TNE).origin, north_east.origin)
	testing.expect_value(t, binary_tree_select(&b, .BNE).origin, north_east.origin)

	testing.expect_value(t, binary_tree_select(&b, .SE).origin, south_east.origin)
	testing.expect_value(t, binary_tree_select(&b, .TSE).origin, south_east.origin)
	testing.expect_value(t, binary_tree_select(&b, .BSE).origin, south_east.origin)

	direction := []Sector{.NW, .NE, .SW, .SE}
	for i in 0 ..< len(direction) {
		testing.expect_value(
			t,
			binary_tree_select(&b, Sector(i)).origin,
			binary_tree_select(&b, direction[i]).origin,
		)
	}
}

@(test)
test_binary_tree_select_3D :: proc(t: ^testing.T) {
	b := OctTree(u64, 0, 2)
	binary_tree_subdivide(&b)

	top_north_west := OctTree(u64, [3]f32{-1, 1, 1}, 1)
	top_north_east := OctTree(u64, [3]f32{1, 1, 1}, 1)
	top_south_west := OctTree(u64, [3]f32{-1, -1, 1}, 1)
	top_south_east := OctTree(u64, [3]f32{1, -1, 1}, 1)

	bottom_north_west := OctTree(u64, [3]f32{-1, 1, -1}, 1)
	bottom_north_east := OctTree(u64, [3]f32{1, 1, -1}, 1)
	bottom_south_west := OctTree(u64, [3]f32{-1, -1, -1}, 1)
	bottom_south_east := OctTree(u64, [3]f32{1, -1, -1}, 1)

	testing.expect_value(t, binary_tree_select(&b, .TNW).origin, top_north_west.origin)
	testing.expect_value(t, binary_tree_select(&b, .TNE).origin, top_north_east.origin)
	testing.expect_value(t, binary_tree_select(&b, .TSW).origin, top_south_west.origin)
	testing.expect_value(t, binary_tree_select(&b, .TSE).origin, top_south_east.origin)

	testing.expect_value(t, binary_tree_select(&b, .BNW).origin, bottom_north_west.origin)
	testing.expect_value(t, binary_tree_select(&b, .BNE).origin, bottom_north_east.origin)
	testing.expect_value(t, binary_tree_select(&b, .BSW).origin, bottom_south_west.origin)
	testing.expect_value(t, binary_tree_select(&b, .BSE).origin, bottom_south_east.origin)

	direction := []Sector{.TNW, .TNE, .TSW, .TSE, .BNW, .BNE, .BSW, .BSE}
	for i in 0 ..< len(direction) {
		testing.expect_value(
			t,
			binary_tree_select(&b, Sector(i)).origin,
			binary_tree_select(&b, direction[i]).origin,
		)
	}
}

@(test)
test_aabb_contains_point :: proc(t: ^testing.T) {
	{
		a := Aabb(1) {
			origin = 0,
			extent = 1,
		}
		testing.expect_value(t, aabb_contains_point(a, 0), true)
		testing.expect_value(t, aabb_contains_point(a, 0.99999), true)
		testing.expect_value(t, aabb_contains_point(a, 1), true)
		testing.expect_value(t, aabb_contains_point(a, 1.1), false)
		testing.expect_value(t, aabb_contains_point(a, 2), false)
	}

	{
		a2 := Aabb(2) {
			origin = 0,
			extent = 1,
		}
		testing.expect_value(t, aabb_contains_point(a2, 0), true)
		testing.expect_value(t, aabb_contains_point(a2, 0.99999), true)
		testing.expect_value(t, aabb_contains_point(a2, 1), true)
		testing.expect_value(t, aabb_contains_point(a2, 1.1), false)
		testing.expect_value(t, aabb_contains_point(a2, 2), false)
	}

	{
		a3 := Aabb(3) {
			origin = 0,
			extent = 1,
		}
		testing.expect_value(t, aabb_contains_point(a3, 0), true)
		testing.expect_value(t, aabb_contains_point(a3, 0.99999), true)
		testing.expect_value(t, aabb_contains_point(a3, 1), true)
		testing.expect_value(t, aabb_contains_point(a3, 1.1), false)
		testing.expect_value(t, aabb_contains_point(a3, 2), false)
	}
}

@(test)
test_aabb_contains_aabb :: proc(t: ^testing.T) {
	{
		a := Aabb(1) {
			origin = 0,
			extent = 1,
		}
		b1 := Aabb(1) {
			origin = 0,
			extent = .5,
		}
		b2 := Aabb(1) {
			origin = 0,
			extent = .9999,
		}
		b3 := Aabb(1) {
			origin = 0,
			extent = 1,
		}
		b4 := Aabb(1) {
			origin = 0,
			extent = 1.1,
		}
		testing.expect_value(t, aabb_contains_aabb(a,b1), true)
		testing.expect_value(t, aabb_contains_aabb(a,b2), true)
		testing.expect_value(t, aabb_contains_aabb(a,b3), true)
		testing.expect_value(t, aabb_contains_aabb(a,b4), false)
	}

	{
		a := Aabb(2) {
			origin = 0,
			extent = 1,
		}
		b1 := Aabb(2) {
			origin = 0,
			extent = .5,
		}
		b2 := Aabb(2) {
			origin = 0,
			extent = .9999,
		}
		b3 := Aabb(2) {
			origin = 0,
			extent = 1,
		}
		b4 := Aabb(2) {
			origin = 0,
			extent = 1.1,
		}
		b5 := Aabb(2) {
			origin = {0,.5},
			extent = 1,
		}
		testing.expect_value(t, aabb_contains_aabb(a,b1), true)
		testing.expect_value(t, aabb_contains_aabb(a,b2), true)
		testing.expect_value(t, aabb_contains_aabb(a,b3), true)
		testing.expect_value(t, aabb_contains_aabb(a,b4), false)
		testing.expect_value(t, aabb_contains_aabb(a,b5), false)
	}

	{
		a := Aabb(3) {
			origin = 0,
			extent = 1,
		}
		b1 := Aabb(3) {
			origin = 0,
			extent = .5,
		}
		b2 := Aabb(3) {
			origin = 0,
			extent = .9999,
		}
		b3 := Aabb(3) {
			origin = 0,
			extent = 1,
		}
		b4 := Aabb(3) {
			origin = 0,
			extent = 1.1,
		}
		testing.expect_value(t, aabb_contains_aabb(a,b1), true)
		testing.expect_value(t, aabb_contains_aabb(a,b2), true)
		testing.expect_value(t, aabb_contains_aabb(a,b3), true)
		testing.expect_value(t, aabb_contains_aabb(a,b4), false)
	}
}
