#+vet !unused-procedures
package main

import "base:intrinsics"
import "core:math/rand"


RandomSeries :: struct {
    state: rand.Default_Random_State,
}

seed_random_series :: proc(#any_int seed: u64) -> (result: RandomSeries) {
    state := rand.create(seed)
    result = { state }
    return result
}

// @todo(viktor): maybe make type a parameter?
next_random_u32 :: proc(series: ^RandomSeries) -> (result: u32) {
    gen := rand.default_random_generator(&series.state)
    result = rand.uint32( gen )
    return result
}

random_choice :: proc { random_choice_integer_0_max, random_choice_integer_min_max, random_choice_data }
random_choice_integer_0_max :: proc(series: ^RandomSeries, max: u32) -> (result: u32) {
    result = next_random_u32(series) % max
    return result
}
random_choice_integer_min_max :: proc(series: ^RandomSeries, min, max: u32) -> (result: u32) {
    result = next_random_u32(series) % (max - min) + min
    return result
}
random_choice_data :: proc(series: ^RandomSeries, data:[]$T) -> (result: ^T) {
    result = &data[random_choice(series, auto_cast len(data))]
    return result
}

random_unilateral :: proc(series: ^RandomSeries, $T: typeid) -> (result: T) {
    when intrinsics.type_is_array(T) {
        E :: intrinsics.type_elem_type(T)
        #unroll for i in 0..<len(T) do result[i] = cast(E) (cast(f64)(next_random_u32(series) - MinRandomValue) / (MaxRandomValue - MinRandomValue)) 
    } else {
        result = cast(T) (cast(f64)(next_random_u32(series) - MinRandomValue) / (MaxRandomValue - MinRandomValue)) 
    }
    return result
}

random_bilateral :: proc(series: ^RandomSeries, $T: typeid) -> (result: T) {
    result = random_unilateral(series, T) * 2 - 1
    
    return result
}

random_between_i32 :: proc(series: ^RandomSeries, min, max: i32) -> (result: i32) {
    assert(min < max)
    result = min + cast(i32)(next_random_u32(series) % cast(u32)((max+1)-min))
    
    return result
}
random_between_f32 :: proc(series: ^RandomSeries, min, max: f32) -> (result: f32) {
    assert(min < max)
    value := random_unilateral(series, f32)
    range := max - min
    result = min + value * range
    assert(result >= min)
    assert(result <= max)
    return result
}

random_between_u32 :: proc(series: ^RandomSeries, min, max: u32) -> (result: u32) {
    assert(min < max)
    result = min + (next_random_u32(series) % ((max+1)-min))
    assert(result >= min)
    assert(result <= max)
    return result
}

@(private="file") MaxRandomValue :: 0xFFFFFFFF
@(private="file") MinRandomValue :: 0