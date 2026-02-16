package main

import "core:math/linalg"

v3 :: [3] f32
v4 :: [4] f32
Vec3 :: [3] f32
Point :: Vec3
Color :: Vec3

vector_near_zero :: proc(v: Vec3) -> b32 {
	epsilon :: 1e-8
	return abs(v.x) < epsilon && abs(v.y) < epsilon && abs(v.z) < epsilon
}

Ray :: struct {
	origin:    Point,
	direction: Vec3,
}

ray_at :: proc "contextless" (r: Ray, t: f32) -> Point {
	return r.origin + t * r.direction
}

square :: proc (x: $T) -> T { return x * x }

length_squared :: linalg.length2