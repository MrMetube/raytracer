#+no-instrumentation
package main

import "base:intrinsics"
import "core:simd"

////////////////////////////////////////////////
// @note(viktor): A typed wrapper on a lane pointer

Lane :: struct ($T: typeid) {
    p: lane_pmm,
}

lane_index :: proc { lane_index_array, lane_index_dynamic, lane_index_slice, lane_index_slice_lane }
lane_index_wide :: #force_inline proc (slice: [] $Vector/ #simd[$N] $E, index: lane_u32) -> Lane(E) {
    base   := cast(lane_umm) raw_data(slice)
    offset := cast(lane_umm) index * size_of(Vector)
    result := Lane(E) { cast(lane_pmm) (base + offset) }
    return result
}
lane_index_array :: #force_inline proc (lane: Lane($T/ [$N] $E), index: lane_u32) -> Lane(E) {
    base   := cast(lane_umm) lane.p
    offset := cast(lane_umm) index * size_of(E)
    result := Lane(E) { cast(lane_pmm) (base + offset) }
    return result
}
lane_index_slice_lane :: #force_inline proc (lane: Lane($T/ [] $E), index: lane_u32) -> Lane(E) {
    base   := cast(lane_umm) lane.p
    offset := size_of(E) * cast(lane_umm) index
    result := Lane(E) { cast(lane_pmm) (base + offset) }
    return result
}

lane_index_slice :: #force_inline proc (slice: $T/ [] $E, index: lane_u32) -> Lane(E) {
    base   := Lane(T) { raw_data(slice) }
    result := lane_index(base, index)
    return result
}
lane_index_dynamic :: #force_inline proc (array: $T/ [dynamic] $E, index: lane_u32) -> Lane(E) {
    result := lane_index(array[:], index)
    return result
}

lane_member :: #force_inline proc (lane: Lane($T), $member: string, $_member_type: typeid) -> Lane(_member_type) 
where intrinsics.type_field_index_of(T, member) != 999 { // @note(viktor): 999 is a bullshit value, if the member is not valid the where will also fail
    // @todo(viktor): once OLS doesn't crash anymore we can remove the parameter
    type :: intrinsics.type_field_type(T, member)
    #assert(type == _member_type)
    
    base   := cast(lane_umm) lane.p
    offset :: offset_of_by_string(T, member)
    result := Lane(_member_type) { cast(lane_pmm) (base + offset) }
    return result
}

lane_slice :: #force_inline proc (slice: $T / [] $E, start: lane_u32) -> Lane([] E) {
    result := cast(Lane([] E)) lane_index(slice, start)
    return result
}

lane_gather :: proc { lane_gather_mask, lane_gather_no_mask, lane_gather_v }
lane_gather_mask :: #force_inline proc (lane: Lane($T), default: #simd [LaneWidth] T, mask: lane_u32) -> #simd [LaneWidth] T {
    result := simd.gather(lane.p, default, mask)
    return result
}
lane_gather_no_mask :: #force_inline proc (lane: Lane($T)) -> #simd [LaneWidth] T {
    result := lane_gather_mask(lane, T{}, lane_true)
    return result
}
lane_gather_v :: #force_inline proc (lane: Lane($T/ [$N] $E)) -> [N] #simd [LaneWidth] E {
    result: [N] #simd [LaneWidth] E
    #no_bounds_check #unroll for channel_index in cast(u32) 0..<N {
        result[channel_index] = lane_gather(lane_index(lane, cast(lane_u32) channel_index))
    }
    return result
}

lane_scatter :: #force_inline proc (lane: Lane($T), value: #simd [LaneWidth] T, mask: lane_u32 = lane_true) {
    simd.scatter(lane.p, value, mask)
}