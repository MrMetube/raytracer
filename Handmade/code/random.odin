#+vet !unused-procedures
package main

import "base:intrinsics"

@(private="file") MaxRandomValue :lane_u32: max(u32)

RandomSeries :: struct {
    state: lane_u32,
}

seed_random_series :: proc(#any_int seed: u32) -> (result: RandomSeries) {
    result = { state = seed }
    for i in u32(0)..<LaneWidth {
        (cast(^[LaneWidth]u32) &result.state)[i] ~= (i + 58564) * seed
    }
    return 
}

next_random_lane_u32 :: xor_shift
next_random_u32 :: proc (series: ^RandomSeries) ->  (result: u32) {
    next_random_lane_u32(series)
    return extract(series.state, 0)
}
xor_shift :: proc (series: ^RandomSeries) ->  (x: lane_u32) {
    // @note(viktor): Reference xor_shift from https://en.wikipedia.org/wiki/Xorshift
    x = series.state 
        
    x ~= shift_left(x, 13)
    x ~= shift_right(x, 17)
    x ~= shift_left(x,  5)
    
    series.state = x
    
    return x
}

random_unilateral :: proc(series: ^RandomSeries, $T: typeid) -> (result: T) #no_bounds_check {
    when intrinsics.type_is_array(T) {
        E :: intrinsics.type_elem_type(T)
        #unroll for i in 0..<len(T) {
            result[i] = random_unilateral(series, E)
        }
    } else {
        unilateral := cast(lane_f32) (shift_right(next_random_lane_u32(series), 1)) / cast(lane_f32) (max(u32) >> 1)
        when intrinsics.type_is_simd_vector(T) {
            result = cast(T) unilateral
        } else {
            result = cast(T) extract(unilateral, 0)
        }
    }
    
    // @todo(viktor): why are all results less than 0.001 ?
    return result
}

random_bilateral :: proc(series: ^RandomSeries, $T: typeid) -> (result: T) {
    result = random_unilateral(series, T) * 2 - 1
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

random_between_i32 :: proc(series: ^RandomSeries, min, max: i32) -> (result: i32) {
    assert(min < max)
    result = min + cast(i32)(next_random_u32(series) % cast(u32)((max+1)-min))
    
    return result
}

random_between_u32 :: proc(series: ^RandomSeries, min, max: u32) -> (result: u32) {
    assert(min < max)
    result = min + (next_random_u32(series) % ((max+1)-min))
    assert(result >= min)
    assert(result <= max)
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