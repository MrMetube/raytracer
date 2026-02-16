#+no-instrumentation

package main

import "core:math"
import "core:math/linalg"

Infinity :: math.INF_F32

v3 :: [3] f32
v4 :: [4] f32

vector_near_zero :: proc(v: v3) -> b32 {
	epsilon :: 1e-8
	return abs(v.x) < epsilon && abs(v.y) < epsilon && abs(v.z) < epsilon
}

Ray :: struct {
	origin:    v3,
	direction: v3,
}

ray_at :: proc (r: Ray, t: f32) -> v3 {
	return r.origin + t * r.direction
}

square :: proc (x: $T) -> T { return x * x }

length_squared :: proc (v: $V/ [$N] $E) -> E {
    result := dot(v, v)
    return result
}

dot :: proc (a, b: $V/ [$N] $E) -> E #no_bounds_check {
    result: E
    result += a[0] * b[0]
    when N > 1 do result += a[1] * b[1]
    when N > 2 do result += a[2] * b[2]
    when N > 3 do result += a[3] * b[3]
    return result
}