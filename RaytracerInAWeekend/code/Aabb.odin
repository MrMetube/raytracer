package main 

Aabb :: struct($Dimension: u8) {
	origin: [Dimension]f32,
	extent: [Dimension]f32,
}

aabb_of :: proc (min, max: [$D]f32) -> Aabb(D) {
	extent := max - min
	return {origin = min + extent / 2, extent = extent / 2}
}

aabb_intersects :: proc{
	aabb_intersects_ray,
	aabb_intersects_ray_min_max,
	aabb_intersects_aabb,
}


aabb_min_max :: proc (a: Aabb($D)) -> (min,max:[D]f32){
	return a.origin - a.extent, a.origin + a.extent
}

aabb_intersects_ray :: proc (b: Aabb(3), r: Ray) -> bool {
    b_min := b.origin - b.extent
    b_max := b.origin + b.extent
    
    inv_dir := 1/r.direction
    
    t1 := (b_min - r.origin) * inv_dir
    t2 := (b_max - r.origin) * inv_dir
    
    t_enter := max(min(t1.x, t2.x), min(t1.y, t2.y), min(t1.z, t2.z))
    t_exit  := min(max(t1.x, t2.x), max(t1.y, t2.y), max(t1.z, t2.z))
    
    result := t_exit > t_enter
    return result
}

aabb_intersects_ray_min_max :: proc (b: Aabb(3), r: Ray, t_min, t_max: f32) -> bool {
    b_min := b.origin - b.extent
    b_max := b.origin + b.extent
    
    inv_dir := 1/r.direction
    
    t1 := (b_min - r.origin) * inv_dir
    t2 := (b_max - r.origin) * inv_dir
    
    t_enter := max(t_min, min(t1.x, t2.x), min(t1.y, t2.y), min(t1.z, t2.z))
    t_exit  := min(t_max, max(t1.x, t2.x), max(t1.y, t2.y), max(t1.z, t2.z))
    
    result := t_exit > t_enter
    return result
}

aabb_intersects_aabb :: proc (a, b: Aabb($D)) -> bool {
    amin, amax := aabb_min_max(a)
    bmin, bmax := aabb_min_max(b)
	result := true
	for dim in 0 ..< D {
		result &&= amin[dim] < bmax[dim] && amax[dim] > bmin[dim]
	}
	return result
}

aabb_contains :: proc{
	aabb_contains_point,
	aabb_contains_aabb,
}

aabb_contains_point :: proc (a: Aabb($D), position: [D]f32) -> bool {
	EPSILON :: 0.000001
	for pos, dim in position {
		min, max := a.origin[dim] - a.extent[dim], a.origin[dim] + a.extent[dim]
		if pos + EPSILON < min || pos - EPSILON >= max {
			return false
		}
	}
	return true
}

aabb_contains_aabb :: proc (outer,inner: Aabb($D)) -> bool {
	smaller := true
	for _, dim in outer.extent {
		smaller &&= outer.extent[dim] >= inner.extent[dim]
	}
	if !smaller do return false

	min, max := aabb_min_max(inner)
	return aabb_contains_point(outer,min) && aabb_contains_point(outer, max)
}
