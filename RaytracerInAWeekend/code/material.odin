package main

import "core:math"
import "core:math/linalg"

Lambertian :: struct {
	albedo: v3,
}

Metal :: struct {
	albedo: v3,
	fuzz:   f32,
}

Dielectric :: struct {
	index_of_refraction: f32,
}

Material :: union {
	Lambertian,
	Metal,
	Dielectric,
}

scatter :: proc(material: Material, ray: Ray, hit_record: HitRecord) -> (v3, Ray, bool) {
    spall_proc()
    scattered: Ray
    attenuation: v3
    ok: bool // @todo(viktor): what exactly was this bool?
    
	switch m in material {
	case Lambertian:
		scatter_direction := hit_record.normal + random_in_unit_sphere()
		if vector_near_zero(scatter_direction) {
			scatter_direction = hit_record.normal
		}
		scattered = Ray{hit_record.p, scatter_direction}
		attenuation = m.albedo
        ok = true
        
	case Metal:
		reflected := linalg.reflect(linalg.normalize(ray.direction), hit_record.normal)
		scattered = Ray{hit_record.p, reflected + m.fuzz * random_in_unit_sphere()}
		attenuation = m.albedo
		ok = dot(scattered.direction, hit_record.normal) > 0
        
	case Dielectric:
		attenuation = 1
		refraction_ratio := hit_record.front_face ? 1 / m.index_of_refraction : m.index_of_refraction
		unit_direction := linalg.normalize(ray.direction)
		cos_theta := min(dot(-unit_direction, hit_record.normal), 1)
		sin_theta := math.sqrt(1 - cos_theta * cos_theta)

		cannot_refract := refraction_ratio * sin_theta > 1
		direction: v3 = ---
		if cannot_refract || reflectance(cos_theta, refraction_ratio) > random_unilateral() {
			direction = linalg.reflect(unit_direction, hit_record.normal)
		} else {
			direction = linalg.refract(unit_direction, hit_record.normal, refraction_ratio)
		}

		scattered = {hit_record.p, direction}
		ok = true
	}
    
    return attenuation, scattered, ok
}

reflectance :: proc(cosine, reflective_index: f32) -> f32 {
	// Use Schlick's approximation for reflectance
	r0 := (1 - reflective_index) / (1 + reflective_index)
	r0 = r0 * r0
	result := r0 + (1 - r0) * math.pow(1 - cosine, 5)
    return result
}
