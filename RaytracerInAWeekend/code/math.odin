package main

import "core:math"

Vec3 :: [3]f32
Point :: Vec3
Color :: Vec3

vector_near_zero :: proc(v: Vec3) -> b32 {
	s: f32 = 1e-8
	return abs(v.x) < s && abs(v.y) < s && abs(v.z) < s
}

Ray :: struct {
	origin:    Point,
	direction: Vec3,
}

ray_at :: proc "contextless" (r: Ray, t: f32) -> Point {
	return r.origin + t * r.direction
}
