package main

import "core:fmt"
import "core:math"
import "core:math/linalg"

// TODO better name
Hitable :: union {
	Sphere,
	Hitables,
	HitableOctTree,
}

HitableOctTree :: BinaryTree(^Hitable, 3)
Hitables :: [dynamic]Hitable

Sphere :: struct {
	center:   Point,
	radius:   f32,
	material: Material,
}

HitRecord :: struct {
	p:          Point,
	normal:     Vec3,
	t:          f32,
	front_face: b8,
	material:   Material,
}

hitrecord_set_face_normal :: proc "contextless" (rec: ^HitRecord, r: Ray, outward_normal: Vec3) {
	rec.front_face = linalg.dot(r.direction, outward_normal) < 0
	rec.normal = rec.front_face ? outward_normal : -outward_normal
}

hit_any :: proc(
	any_hit: Hitable,
	r: Ray,
	t_min, t_max: f32,
	rec: ^HitRecord,
	loc := #caller_location,
) -> (
	res: b8,
) {
	switch &h in any_hit {
	case Sphere:
		res = hit_sphere(h, r, t_min, t_max, rec)
	case Hitables:
		res = hit_list(h, r, t_min, t_max, rec)
	case HitableOctTree:
		res = hit_binary_tree(&h, r, t_min, t_max, rec)
	case:
	}
	return res
}

hit_list :: proc(list: Hitables, r: Ray, t_min, t_max: f32, rec: ^HitRecord) -> b8 {
	temp_rec: HitRecord
	hit_anything: b8
	closest_so_far := t_max

	for &hitable in list {
		if hit_any(hitable, r, t_min, closest_so_far, &temp_rec) {
			hit_anything = true
			closest_so_far = temp_rec.t
			rec^ = temp_rec
		}
	}

	return hit_anything
}

hit_binary_tree :: proc(t: ^HitableOctTree, r: Ray, t_min, t_max: f32, rec: ^HitRecord) -> b8 {
	if !aabb_intersects(t.bounds, r) do return false

	temp_rec: HitRecord
	closest_so_far := t_max
	hit_anything: b8
	for item in t.values {
		if hit_any(item.value^, r, t_min, closest_so_far, &temp_rec) {
			hit_anything = true
			closest_so_far = temp_rec.t
			rec^ = temp_rec
		}
	}
	if t.subnodes != nil {
		for subtree in t.subnodes {
			if hit_binary_tree(subtree, r, t_min, closest_so_far, &temp_rec) {
				hit_anything = true
				closest_so_far = temp_rec.t
				rec^ = temp_rec
			}
		}
	}
	return hit_anything
}

hit_sphere :: proc(s: Sphere, r: Ray, t_min, t_max: f32, rec: ^HitRecord) -> b8 {
	oc := r.origin - s.center
	a := linalg.length2(r.direction)
	half_b := linalg.dot(oc, r.direction)
	c := linalg.length2(oc) - s.radius * s.radius

	discriminant := half_b * half_b - a * c
	if discriminant < 0 {
		return false
	}
	sqrt_d := math.sqrt(discriminant)

	root := (-half_b - sqrt_d) / a
	if root < t_min || t_max < root {
		root = (-half_b + sqrt_d) / a
		if root < t_min || t_max < root {
			return false
		}
	}

	rec.t = root
	rec.p = ray_at(r, root)
	rec.normal = (rec.p - s.center) / s.radius
	rec.material = s.material
	outward_normal := (rec.p - s.center) / s.radius
	hitrecord_set_face_normal(rec, r, outward_normal)

	return true
}
