package main


import "core:math/linalg"
import "core:math/rand"

random_vector :: proc(min: f32 = 0, max: f32 = 1) -> Vec3 {
	return(
		Vec3 {
			rand.float32_range(min, max),
			rand.float32_range(min, max),
			rand.float32_range(min, max),
		} \
	)
}

random_in_unit_sphere :: proc() -> (p: Vec3) {
	for {
		p = random_vector(-1, 1)
		if linalg.length2(p) < 1 do return p
	}
}

random_unit_vector :: proc() -> Vec3 {
	return linalg.normalize(random_in_unit_sphere())
}

random_in_hemisphere :: proc(normal: Vec3) -> Vec3 {
	in_unit_sphere := random_in_unit_sphere()
	return linalg.dot(in_unit_sphere, normal) > 0 ? in_unit_sphere : -in_unit_sphere
}

random_in_unit_disk :: proc() -> (p: Vec3) {
	for {
		p = Vec3{rand.float32_range(-1, 1), rand.float32_range(-1, 1), 0}
		if linalg.length2(p) < 1 do return p
	}
}
