package main

import "core:math"
import "core:math/linalg"

// TODO better name
Hitable :: union {
	Sphere,
	Hitables,
	HitableOctTree,
}

HitableOctTree :: BinaryTree(^Hitable, 3)
Hitables :: [dynamic] Hitable

Sphere :: struct {
	center:   Point,
	radius:   f32,
	material: Material,
}

HitRecord :: struct {
	p:          Point,
	normal:     Vec3,
	t:          f32,
	front_face: bool,
	material:   Material,
}

////////////////////////////////////////////////

hit_any :: proc(any_hit: Hitable, r: Ray, t_min, t_max: f32, rec: ^HitRecord, loc := #caller_location) -> bool {
    result: bool
    switch &h in any_hit {
    case Sphere:         result = hit_sphere(h, r, t_min, t_max, rec)
    case Hitables:       result = hit_list(h, r, t_min, t_max, rec)
    case HitableOctTree: result = hit_binary_tree(&h, r, t_min, t_max, rec)
    case:
    }
    return result
}


hitrecord_set_face_normal :: proc (rec: ^HitRecord, r: Ray, outward_normal: Vec3) {
	rec.front_face = linalg.dot(r.direction, outward_normal) < 0
	rec.normal = rec.front_face ? outward_normal : -outward_normal
}

hit_list :: proc(list: Hitables, r: Ray, t_min, t_max: f32, rec: ^HitRecord) -> bool {
    temp_rec: HitRecord
    hit_anything: bool
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

hit_binary_tree :: proc(t: ^HitableOctTree, r: Ray, t_min, t_max: f32, rec: ^HitRecord) -> bool {
	if !aabb_intersects(t.bounds, r) do return false

	temp_rec: HitRecord
	closest_so_far := t_max
	hit_anything: bool
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

hit_sphere :: proc(sphere: Sphere, ray: Ray, t_min, t_max: f32, hit_record: ^HitRecord) -> bool {
    oc     := ray.origin - sphere.center
    a      := length_squared(ray.direction)
    half_b := linalg.dot(oc, ray.direction)
    c      := length_squared(oc) - square(sphere.radius)
    
    discriminant := square(half_b) - a * c
    if discriminant < 0 {
        return false
    }
    discriminant_root := math.sqrt(discriminant)
    
    root := (-half_b - discriminant_root) / a
    if root < t_min || t_max < root {
        root = (-half_b + discriminant_root) / a
        if root < t_min || t_max < root {
            return false
        }
    }
    
    hit_record.t = root
    hit_record.p = ray_at(ray, root)
    hit_record.normal = (hit_record.p - sphere.center) / sphere.radius
    hit_record.material = sphere.material
    outward_normal := (hit_record.p - sphere.center) / sphere.radius
    hitrecord_set_face_normal(hit_record, ray, outward_normal)
    
    return true
}
