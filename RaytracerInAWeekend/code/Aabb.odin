package main 

Aabb2 :: Rectangle(v2)
Aabb3 :: Rectangle(v3)

aabb_of :: proc (min, max: $T) -> Rectangle(T) {
	extent := max - min
	return rectangle_center_dimension(min + extent / 2,extent / 2)
}

aabb_intersects :: proc{
	aabb_intersects_ray,
	aabb_intersects_ray_min_max,
	aabb_intersects_aabb,
}

center_dimension :: proc (center: v3, dimension: v3) -> Rectangle3 {
    return rectangle_center_dimension(center, dimension)
}
    
aabb_min_max :: proc (a: $R/Rectangle($T)) -> (min, max: T){
	return a.min, a.max
}

aabb_intersects_ray :: proc (b: Rectangle(v3), r: Ray) -> bool {
    b_min, b_max := aabb_min_max(b)
    
    inv_dir := 1/r.direction
    
    t1 := (b_min - r.origin) * inv_dir
    t2 := (b_max - r.origin) * inv_dir
    
    t_enter := max(min(t1.x, t2.x), min(t1.y, t2.y), min(t1.z, t2.z))
    t_exit  := min(max(t1.x, t2.x), max(t1.y, t2.y), max(t1.z, t2.z))
    
    result := t_exit > t_enter
    return result
}

aabb_intersects_ray_min_max :: proc (b: Rectangle(v3), r: Ray, t_min, t_max: f32) -> bool {
    b_min, b_max := aabb_min_max(b)
    
    inv_dir := 1/r.direction
    
    t1 := (b_min - r.origin) * inv_dir
    t2 := (b_max - r.origin) * inv_dir
    
    t_enter := max(t_min, min(t1.x, t2.x), min(t1.y, t2.y), min(t1.z, t2.z))
    t_exit  := min(t_max, max(t1.x, t2.x), max(t1.y, t2.y), max(t1.z, t2.z))
    
    result := t_exit > t_enter
    return result
}

aabb_intersects_aabb :: proc (a, b: $R/Rectangle($T)) -> bool {
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

aabb_contains_point :: proc (a: $R/Rectangle($T), position: T) -> bool {
	EPSILON :: 0.000001
    min, max := aabb_min_max(a)
	for pos, dim in position {
		if pos + EPSILON < min[dim] || pos - EPSILON >= max[dim] {
			return false
		}
	}
	return true
}

aabb_contains_aabb :: proc (outer,inner: $R/Rectangle($T)) -> bool {
	smaller := true
    outer_extent := get_dimension(outer)
    inner_extent := get_dimension(inner)
	for _, dim in outer_extent {
		smaller &&= outer_extent[dim] >= inner_extent[dim]
	}
	if !smaller do return false

	min, max := aabb_min_max(inner)
	return aabb_contains_point(outer,min) && aabb_contains_point(outer, max)
}
