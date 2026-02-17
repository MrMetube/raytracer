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

ray_intersects_rectangle :: proc (b: Rectangle(v3), r: Ray, t_min, t_max: f32) -> bool {
    b_min, b_max := b.min, b.max
    
    inv_dir := 1/r.direction
    
    t1 := (b_min - r.origin) * inv_dir
    t2 := (b_max - r.origin) * inv_dir
    
    t_enter := max(t_min, min(t1.x, t2.x), min(t1.y, t2.y), min(t1.z, t2.z))
    t_exit  := min(t_max, max(t1.x, t2.x), max(t1.y, t2.y), max(t1.z, t2.z))
    
    result := t_exit > t_enter
    return result
}