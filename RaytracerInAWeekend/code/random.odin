package main


import "core:math/linalg"
import "core:math/rand"

random_unilateral :: proc () -> f32 {
    return rand.float32()
}

random_bilateral :: proc () -> f32 {
    return random_unilateral() * 2 - 1
}

random_range :: proc (min, max: f32) -> f32 {
    return min + random_unilateral() * (max - min)
}

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
		if length_squared(p) < 1 do return p
	}
}

random_unit_vector :: proc() -> Vec3 {
    result := random_in_unit_sphere()
    result = linalg.normalize(result)
    return result
}

random_in_hemisphere :: proc (normal: Vec3) -> Vec3 {
	in_unit_sphere := random_in_unit_sphere()
    if linalg.dot(in_unit_sphere, normal) < 0 {
        in_unit_sphere = -in_unit_sphere
    }
    return in_unit_sphere
}

random_in_unit_disk :: proc() -> (p: Vec3) {
	for {
		p = Vec3{random_bilateral(), random_bilateral(), 0}
		if length_squared(p) < 1 do return p
	}
}
