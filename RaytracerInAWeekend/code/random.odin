package main

import "base:runtime"
import "core:math/rand"

GlobalRandomState: rand.Xoshiro256_Random_State

seed_random_generator :: proc (seed: u64) -> runtime.Random_Generator {
    result := rand.xoshiro256_random_generator(&GlobalRandomState)
    rand.reset(seed, result)
    return result
}

random_unilateral :: proc () -> f32 {
    return rand.float32()
}

random_bilateral :: proc () -> f32 {
    return random_unilateral() * 2 - 1
}

random_range :: proc (min, max: f32) -> f32 {
    return min + random_unilateral() * (max - min)
}

random_vector :: proc(min: f32 = 0, max: f32 = 1) -> v3 {
	return v3 {
        rand.float32_range(min, max),
        rand.float32_range(min, max),
        rand.float32_range(min, max),
    }
}

random_in_unit_sphere :: proc() -> (p: v3) {
	for {
		p = random_vector(-1, 1)
		if length_squared(p) < 1 do return p
	}
}

random_in_hemisphere :: proc (normal: v3) -> v3 {
	in_unit_sphere := random_in_unit_sphere()
    if dot(in_unit_sphere, normal) < 0 {
        in_unit_sphere = -in_unit_sphere
    }
    return in_unit_sphere
}

random_in_unit_disk :: proc() -> (p: v3) {
    spall_proc()
	for {
		p = v3{random_bilateral(), random_bilateral(), 0}
		if length_squared(p) < 1 do return p
	}
}
