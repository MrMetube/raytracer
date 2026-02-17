#+no-instrumentation

package main

Ray :: struct {
	origin:    v3,
	direction: v3,
}

ray_at :: proc (r: Ray, t: f32) -> v3 {
	return r.origin + t * r.direction
}

vector_near_zero :: proc(v: v3) -> b32 {
	epsilon :: 1e-8
	return abs(v.x) < epsilon && abs(v.y) < epsilon && abs(v.z) < epsilon
}
