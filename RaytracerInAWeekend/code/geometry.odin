package main

import "core:math"

// @naming
Hitable :: struct {
    first_subnode: Hitable_Index,
    next_subnode:  Hitable_Index,
    
    first_value: Hitable_Index,
    next_value:  Hitable_Index,
    value_count: i16,
    
    using bounds: Rectangle3,
    
    is_sphere: bool,
    sphere:    Sphere,
}

Hitable_Index :: distinct i16

Sphere :: struct {
	center:   v3,
	radius:   f32,
	material: Material,
}

HitRecord :: struct {
	p:          v3,
	normal:     v3,
	t:          f32,
	front_face: bool,
	material:   Material,
}

////////////////////////////////////////////////

append_sphere :: proc (hh: ^[dynamic] Hitable, sphere: Sphere) {
    assert(len(hh) > 0)
    it: Hitable
    it.sphere = sphere
    it.is_sphere = true
    it.bounds = {it.sphere.center, it.sphere.radius}
    append(hh, it)
}

////////////////////////////////////////////////

hit_any :: proc(stack1, stack2: ^[dynamic] Hitable_Index, hh: [] Hitable, any_hit: Hitable_Index, r: Ray, t_min, t_max: f32) -> (HitRecord, bool) {
    spall_proc()
    
    clear(stack1)
    clear(stack2)
    append(stack1, any_hit)
    
    spall_begin("octtree traversal")
    for len(stack1) != 0 {
        it_index := pop(stack1)
        
        it := hh[it_index]
        
        if it.next_subnode != 0 do append(stack1, it.next_subnode)
        if it.next_value   != 0 do append(stack1, it.next_value)
        
        if aabb_intersects_ray_min_max(it.bounds, r, t_min, t_max) {
            if it.is_sphere {
                append(stack2, it_index)
            } else {
                if it.first_subnode != 0 do append(stack1, it.first_subnode)
                if it.first_value   != 0 do append(stack1, it.first_value)
            }
        }
    }
    spall_end()
    
    spall_begin("sphere checks")
    closest_so_far := t_max
    hit: bool
    record: HitRecord
    for len(stack2) != 0 {
        it_index := pop(stack2)
        it := hh[it_index]
        assert(it.is_sphere)
        if temp_rec, hit_ok := hit_sphere(it.sphere, r, t_min, closest_so_far); hit_ok {
            hit = true
            closest_so_far = temp_rec.t
            record = temp_rec
        }
    }
    spall_end()
    
    return record, hit
}

hit_sphere :: proc(sphere: Sphere, ray: Ray, t_min, t_max: f32) -> (HitRecord, bool) {
    spall_proc()
    
    record: HitRecord
    hit:    bool
    
    oc     := ray.origin - sphere.center
    a      := length_squared(ray.direction)
    half_b := dot(oc, ray.direction)
    c      := length_squared(oc) - square(sphere.radius)
    
    discriminant := square(half_b) - a * c
    if discriminant < 0 {
        return record, hit
    }
    discriminant_root := math.sqrt(discriminant)
    
    root := (-half_b - discriminant_root) / a
    if t_min > root || root > t_max {
        root = (-half_b + discriminant_root) / a
        if t_min > root || root > t_max {
            return record, hit
        }
    }
    
    hit = true
    
    record.t = root
    record.p = ray_at(ray, root)
    
    record.normal = (record.p - sphere.center) / sphere.radius
    record.material = sphere.material
    
    // set_face_normal
    record.front_face = dot(ray.direction, record.normal) < 0
	record.normal = record.front_face ? record.normal : -record.normal
    
    return record, hit
}