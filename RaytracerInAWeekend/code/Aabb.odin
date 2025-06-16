package main 

import "core:fmt"

Aabb :: struct($Dimension: u8) {
	origin: [Dimension]f32,
	extent: [Dimension]f32,
}

aabb_of :: proc "contextless" (min, max: [$D]f32) -> Aabb(D) {
	extent := max - min
	return {origin = min + extent / 2, extent = extent / 2}
}

aabb_intersects :: proc{
	aabb_intersects_ray,
	aabb_intersects_aabb,
}


aabb_min_max :: proc "contextless" (a:Aabb($D)) -> (min,max:[D]f32){
	return a.origin - a.extent, a.origin + a.extent
}

// Note: as rays are a 3d construct, only accept 3d aabbs
aabb_intersects_ray :: proc "contextless" (b:Aabb(3), r:Ray) -> b8 {
	// TODO check correctness
	bmin,bmax := b.origin - b.extent, b.origin + b.extent
	inv_dir := 1/r.direction

	tx1 := (bmin.x - r.origin.x)*inv_dir.x;
    tx2 := (bmax.x - r.origin.x)*inv_dir.x;

    tmin := min(tx1, tx2);
    tmax := max(tx1, tx2);

    ty1 := (bmin.y - r.origin.y)*inv_dir.y;
    ty2 := (bmax.y - r.origin.y)*inv_dir.y;

    tmin = max(tmin, min(ty1, ty2));
    tmax = min(tmax, max(ty1, ty2));

    return tmax >= tmin;
}

aabb_intersects_aabb :: proc "contextless" (a, b: Aabb($D)) -> b8 {
	result: b8 = true
	for dim in 0 ..< D {
		amin, amax := aabb_min_max(a)
		bmin, bmax := aabb_min_max(b)
		result &= amin[dim] < bmax[dim] && amax[dim] > bmin[dim]
	}
	return result
}

aabb_contains :: proc{
	aabb_contains_point,
	aabb_contains_aabb,
}

aabb_contains_point :: proc "contextless" (a: Aabb($D), position: [D]f32) -> b8 {
	EPSILON :: 0.000001
	for pos, dim in position {
		min, max := a.origin[dim] - a.extent[dim], a.origin[dim] + a.extent[dim]
		if pos + EPSILON < min || pos - EPSILON >= max {
			return false
		}
	}
	return true
}

aabb_contains_aabb :: proc "contextless" (outer,inner:Aabb($D)) -> b8 {
	smaller := true
	for _, dim in outer.extent {
		smaller &= outer.extent[dim] >= inner.extent[dim]
	}
	if !smaller do return false

	min, max := aabb_min_max(inner)
	return aabb_contains_point(outer,min) && aabb_contains_point(outer, max)
}
