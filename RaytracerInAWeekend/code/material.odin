package main

import "core:math"
import "core:math/linalg"
import "core:math/rand"

Lambertian :: struct {
	albedo: Color,
}
Metal :: struct {
	albedo: Color,
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

scatter :: proc(
	mat: Material,
	r: ^Ray,
	rec: HitRecord,
	attenuation: ^Color,
	scattered: ^Ray,
) -> b32 {
	switch m in mat {
	case Lambertian:
		scatter_direction := rec.normal + random_in_unit_sphere()
		if vector_near_zero(scatter_direction) {
			scatter_direction = rec.normal
		}
		scattered^ = Ray{rec.p, scatter_direction}
		attenuation^ = m.albedo
		return true
	case Metal:
		reflected := linalg.reflect(linalg.normalize(r.direction), rec.normal)
		scattered^ = Ray{rec.p, reflected + m.fuzz * random_in_unit_sphere()}
		attenuation^ = m.albedo
		return linalg.dot(scattered.direction, rec.normal) > 0
	case Dielectric:
		attenuation^ = 1
		refraction_ratio := rec.front_face ? 1 / m.index_of_refraction : m.index_of_refraction
		unit_direction := linalg.normalize(r.direction)
		cos_theta := min(linalg.dot(-unit_direction, rec.normal), 1)
		sin_theta := math.sqrt(1 - cos_theta * cos_theta)

		cannot_refract := refraction_ratio * sin_theta > 1
		direction: Vec3 = ---
		if cannot_refract || reflectance(cos_theta, refraction_ratio) > rand.float32() {
			direction = linalg.reflect(unit_direction, rec.normal)
		} else {
			direction = linalg.refract(unit_direction, rec.normal, refraction_ratio)
		}

		scattered^ = {rec.p, direction}
		return true
	}
	return false
}

reflectance :: proc(cosine, reflective_index: f32) -> f32 {
	// Use Schlick's approximation for reflectance
	r0 := (1 - reflective_index) / (1 + reflective_index)
	r0 = r0 * r0
	return r0 + (1 - r0) * math.pow(1 - cosine, 5)
}
