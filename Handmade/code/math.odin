#+vet !unused-procedures
#+no-instrumentation
package main

import "base:intrinsics"
import "base:builtin"
import "core:math"
import "core:simd"

////////////////////////////////////////////////
// Types

v2  :: [2] f32
v3  :: [3] f32
v4  :: [4] f32

v2i :: [2] i32
v3i :: [3] i32
v4i :: [4] i32

uv2 :: [2] u32
uv3 :: [3] u32
uv4 :: [4] u32

LaneWidth :: 8

lane_f32 :: #simd [LaneWidth] f32
lane_u32 :: #simd [LaneWidth] u32
lane_i32 :: #simd [LaneWidth] i32

lane_v2 :: [2] lane_f32
lane_v3 :: [3] lane_f32
lane_v4 :: [4] lane_f32

lane_uv3 :: [3] lane_u32

lane_pmm :: #simd [LaneWidth] pmm
lane_umm :: #simd [LaneWidth] umm
lane_f64 :: #simd [LaneWidth] f64
lane_u64 :: #simd [LaneWidth] u64

lane_false :: cast(lane_u32) 0
lane_true  :: cast(lane_u32) 0xffff_ffff

lane_offset :: lane_u32{0, 1, 2, 3, 4, 5, 6, 7} when LaneWidth == 8 else ( lane_u32{0, 1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11, 12, 13, 14, 15} when LaneWidth == 16 else lane_u32{0, 1, 2, 3})

m4 :: matrix[4,4] f32

Rectangle   :: struct($T: typeid) { min, max: T }
Rectangle2  :: Rectangle(v2)
Rectangle3  :: Rectangle(v3)
Rectangle2i :: Rectangle(v2i)

////////////////////////////////////////////////
// Constants

Tau :: 6.28318530717958647692528676655900576
Pi  :: 3.14159265358979323846264338327950288
E   :: 2.71828182845904523536

SqrtTwo   :: 1.41421356237309504880168872420969808
SqrtThree :: 1.73205080756887729352744634150587236
SqrtFive  :: 2.23606797749978969640917366873127623

Ln2  :: 0.693147180559945309417232121458176568
Ln10 :: 2.30258509299404568401799145468436421

MaxF64Precision :: 16 // Maximum number of meaningful digits after the decimal point for 'f64'
MaxF32Precision ::  8 // Maximum number of meaningful digits after the decimal point for 'f32'
MaxF16Precision ::  4 // Maximum number of meaningful digits after the decimal point for 'f16'

Infinity :: math.INF_F32
QNaN     :: math.QNAN_F32

RadPerDeg :: Tau/360.0
DegPerRad :: 360.0/Tau

////////////////////////////////////////////////
// Scalar operations

square :: proc(x: $T) -> T { return x * x }

square_root :: proc(x: $T) -> (result: T) { 
    when intrinsics.type_is_array(T) {
        #no_bounds_check #unroll for i in 0..<len(T) {
            result[i] = simd.sqrt(x[i])
        }
    } else {
        result = simd.sqrt(x)
    }
    return result
}

power :: math.pow

linear_blend  :: proc{ linear_blend_v_e, linear_blend_e }
linear_blend_v_e :: proc(from: $V/[$N]$Element, to: V, t: Element) -> V {
    result := (1-t) * from + t * to
    
    return result
}
linear_blend_e :: proc(from: $T, to: T, t: T) -> T  {
    result := (1-t) * from + t * to
    
    return result
}

linear_remap :: proc (v: $T, old_from, old_to: T, new_from, new_to: T) -> T {
    result: T
    old_range := old_to - old_from
    if old_range != 0 {
        old_t := (v - old_from) / old_range
        result = linear_blend(new_from, new_to, old_t)
    }
    return result
}

bilinear_blend :: proc { bilinear_blend_s, bilinear_blend_v }
bilinear_blend_s :: proc (a: $T, b, c, d: T, t: [2] T) -> (result: T) {
    la := (1-t.y) * (1-t.x)
    lb := (1-t.y) *    t.x
    lc :=    t.y  * (1-t.x)
    ld :=    t.y  *    t.x
    
    result = la * a + lb * b + lc * c + ld * d
    return result
}
bilinear_blend_v :: proc (a: $V/[$N]$E, b, c, d: V, t: [2] E) -> (result: V) {
    // @copypasta
    la := (1-t.y) * (1-t.x)
    lb := (1-t.y) *    t.x
    lc :=    t.y  * (1-t.x)
    ld :=    t.y  *    t.x
    
    result = la * a + lb * b + lc * c + ld * d
    return result
}

safe_ratio_or_else :: proc { safe_ratio_or_else_s, safe_ratio_or_else_v }
safe_ratio_or_else_s :: proc(numerator: $T, divisor: T) -> (T, bool) {
    ratio: T
    ok := divisor != 0
    
    if ok {
        ratio = numerator / divisor
    }
    
    return ratio, ok
}
safe_ratio_or_else_v :: proc(numerator: $V/[$N]$E, divisor: V) -> (V, bool) {
    ratio: V
    
    ok := true
    #no_bounds_check #unroll for i in 0..<N {
        if divisor[i] != 0 {
            ratio[i] = numerator[i] / divisor[i]
        } else {
            ok = false
        }
    }
    
    return ratio, ok
}

safe_ratio_or_n    :: proc(numerator: $T, divisor, n: T) -> T { return safe_ratio_or_else(numerator, divisor) or_else n }
safe_ratio_or_zero :: proc(numerator: $T, divisor: T)    -> T { return safe_ratio_or_else(numerator, divisor) or_else 0 }
safe_ratio_or_one  :: proc(numerator: $T, divisor: T)    -> T { return safe_ratio_or_else(numerator, divisor) or_else 1 }

clamp :: proc(value: $T, min, max: T) -> (result: T) {
    when intrinsics.type_is_simd_vector(T) {
        result = simd.clamp(value, min, max)
    } else when intrinsics.type_is_array(T) {
        #no_bounds_check #unroll for i in 0..<len(T) {
            result[i] = clamp(value[i], min[i], max[i])
        }
    } else {
        result = builtin.clamp(value, min, max)
    }
    
    return result
}
clamp_01 :: proc(value: $T) -> T { return clamp(value, 0, 1) }

clamp_01_to_range :: proc(min: $T, t, max: T ) -> (result: T) {
    range := max - min
    if range != 0 {
        percent := (t-min) / range
        result = clamp_01(percent)
    }
    return result
}

sign :: proc{ sign_i, sign_f }
sign_i  :: proc(i: i32) -> i32 { return i >= 0 ? 1 : -1 }
sign_f  :: proc(x: f32) -> f32 { return x >= 0 ? 1 : -1 }

modulus :: proc { modulus_i, modulus_f, modulus_vf, modulus_v }
modulus_f :: proc(value: f32, divisor: f32) -> f32 {
    return math.mod(value, divisor)
}
modulus_i :: proc(value: $I, divisor: I) -> I where intrinsics.type_is_integer(I) {
    return value % divisor
}
modulus_vf :: proc(value: [$N]f32, divisor: f32) -> (result: [N]f32) where N > 1 {
    #no_bounds_check #unroll for i in 0..<N do result[i] = math.mod(value[i], divisor) 
    return result
}
modulus_v :: proc(value: [$N]f32, divisor: [N]f32) -> (result: [N]f32) {
    #no_bounds_check #unroll for i in 0..<N do result[i] = math.mod(value[i], divisor[i]) 
    return result
}

// @cleanup these array to simd to array
round :: proc { round_f, round_v }
round_f :: proc($T: typeid, f: $F) -> T 
where !intrinsics.type_is_array(F)
{
    return  cast(T) (f < 0 ? -math.round(-f) : math.round(f))
}
round_v :: proc($T: typeid, v: [$N]$F) -> (result: [N]T) {
    #no_bounds_check #unroll for i in 0..<N {
        result[i] = cast(T) math.round(v[i]) 
    }
    return result
}

floor :: proc { floor_f, floor_v }
floor_f :: proc($T: typeid, f: $F) -> (i: T) {
    when F == lane_f32 {
        return cast(T) simd.floor(f)
    } else {
        return cast(T) math.floor(f)
    }
}
floor_v :: proc($T: typeid, fs: [$N] f32) -> [N] T {
    return vec_cast(T, simd.to_array(simd.floor(simd.from_array(fs))))
}

ceil :: proc { ceil_f, ceil_v }
ceil_f :: proc($T: typeid, f: f32) -> (i: T) {
    return cast(T) math.ceil(f)
}
ceil_v :: proc($T: typeid, fs: [$N]f32) -> [N]T {
    return vec_cast(T, simd.to_array(simd.ceil(simd.from_array(fs))))
}

truncate :: proc { truncate_f, truncate_v }
truncate_f :: proc($T: typeid, f: f32) -> T {
    return cast(T) f
}
truncate_v :: proc($T: typeid, fs: [$N]f32) -> [N]T where N > 1 {
    return vec_cast(T, fs)
}

sin :: math.sin
cos :: math.cos
tan :: math.tan
acos  :: math.acos
asin  :: math.asin
atan2 :: math.atan2

fractional :: proc { fractional_v, fractional_f }
fractional_v :: proc (v: v2) -> (fractional, integral: v2) {
    fractional.x, integral.x = fractional_f(v.x)
    fractional.y, integral.y = fractional_f(v.y)
    return fractional, integral
}
fractional_f :: proc (x: f32) -> (fractional, integral: f32) {
    integral   = cast(f32) floor(i32, x)
    fractional = x - integral
    return fractional, integral
}


////////////////////////////////////////////////
// Vector operations

V3 :: proc { V3_x_yz, V3_xy_z }
V3_x_yz :: proc(x: f32, yz: v2) -> v3 { return { x, yz.x, yz.y }}
V3_xy_z :: proc(xy: v2, z: f32) -> v3 { return { xy.x, xy.y, z }}

Rect3 :: proc(xy: $R/ Rectangle([2] $Element), z_min, z_max: Element) -> Rectangle([3] Element) { 
    return { V3(xy.min, z_min), V3(xy.max, z_max)}
}

V4 :: proc { V4_x_yzw, V4_xy_zw, V4_xyz_w, V4_x_y_zw, V4_x_yz_w, V4_xy_z_w }
V4_x_yzw  :: proc(x: f32, yzw: v3) -> (result: v4) {
    result.x = x
    result.yzw = yzw
    return result
}
V4_xy_zw  :: proc(xy: v2, zw: v2) -> (result: v4) {
    result.xy = xy
    result.zw = zw
    return result
}
V4_xyz_w  :: proc(xyz: v3, w: f32) -> (result: v4) {
    result.xyz = xyz
    result.w = w
    return result
}
V4_x_y_zw :: proc(x, y: f32, zw: v2) -> (result: v4) {
    result.x = x
    result.y = y
    result.zw = zw
    return result
}
V4_x_yz_w :: proc(x: f32, yz: v2, w:f32) -> (result: v4) {
    result.x = x
    result.yz = yz
    result.w = w
    return result
}
V4_xy_z_w :: proc(xy: v2, z, w: f32) -> (result: v4) {
    result.xy = xy
    result.z = z
    result.w = w
    return result
}

perpendicular :: proc(v: v2) -> (result: v2) {
    result = { -v.y, v.x }
    return result
}

arm :: proc(angle: f32) -> (result: v2) {
    result = v2{cos(angle), sin(angle)}
    return result
}

dot :: proc(a: $V/[$N] $E, b: V) -> E {
    result := fused_mul_add(a.x, b.x, 0)
    result  = fused_mul_add(a.y, b.y, result)
    when N >= 3 do result = fused_mul_add(a.z, b.z, result)
    when N >= 4 do result = fused_mul_add(a.w, b.w, result)
    return result
}

cross :: proc(a: $V/[3]$Element, b: V) -> V {
    result: V
    result.x = fused_mul_add(a.y, b.z, -a.z*b.y)
    result.y = fused_mul_add(a.z, b.x, -a.x*b.z)
    result.z = fused_mul_add(a.x, b.y, -a.y*b.x)
    
    return result
}

reflect :: proc(v, axis: $V) -> V {
    result := v - 2 * dot(v, axis) * axis
    return result
}
project :: proc(v, axis: $V) -> V {
    result := v - 1 * dot(v, axis) * axis
    return result
}

length :: proc(vec: $V/ [$N] $T) -> (result: T) {
    squared_length := length_squared(vec)
    result = square_root(squared_length)
    return result
}

length_squared :: proc(vec: $V/ [$N] $T) -> T {
    result := dot(vec, vec)
    return result
}

normalize :: proc(vec: $V) -> (result: V) {
    result = vec / length(vec)
    return result
}

normalize_or_zero :: proc(vec: $V/[$N]$T) -> (result: V) {
    len_sq := length_squared(vec)
    when intrinsics.type_is_simd_vector(T) {
        conditional_assign(greater_than(len_sq, 0.0000001), &result, vec / square_root(len_sq))
    } else {
        if len_sq > 0.0000001 {
            result = vec / square_root(len_sq)
        }
    }
    return result
}

linear_to_srgb :: proc(l: v3) -> (s: v3) {
    l := l
    l = clamp_01(l)
    #no_bounds_check #unroll for i in 0..<len(l) {
        s[i] = 12.92 * l[i]
        if l[i] > 0.0031308 {
            s[i] = 1.055 * power(l[i], 1.0/2.4) - 0.055
        }
    }
    
    return s
}

color_to_u8 :: proc { color_to_u8_3, color_to_u8_4 }
color_to_u8_3 :: proc (color: v3) -> Color {
    v: v4 = 255
    v.rgb *= color
    result := round(u8, v)
    return result
}
color_to_u8_4 :: proc (color: v4) -> Color {
    v: v4 = 255
    v.rgba *= color
    result := round(u8, v)
    return result
}

////////////////////////////////////////////////
// Simd operations

ternary :: proc (mask: $M, then_value: $T, else_value: T) -> T {
    result: T
    
    when intrinsics.type_is_array(T) {
        #no_bounds_check #unroll for i in 0..<len(T) {
            result[i] = ternary(mask, then_value[i], else_value[i])
        }
    } else {
        result = simd.select(mask, then_value, else_value)
    }
    
    return result
}

conditional_assign :: proc (mask: $M, dest: ^$D, value: D) {
    when intrinsics.type_is_array(D) {
        #no_bounds_check #unroll for i in 0..<len(D) {
            conditional_assign(mask, &dest[i], value[i])
        }
    } else {
        simd.masked_store(dest, value, mask)
    }
}

absolute      :: simd.abs
greater_equal :: simd.lanes_ge
less_equal    :: simd.lanes_le
greater_than  :: simd.lanes_gt
less_than     :: simd.lanes_lt
equal         :: simd.lanes_eq
not_equal     :: simd.lanes_ne

fused_mul_add :: simd.fma

is_nan :: proc { is_nan_s, is_nan_v }

is_nan_v :: proc (x: $V/ #simd[$N] $F) -> #simd[N] (u32 when F == f32 else u64) {
    result := not_equal(x, x)
    return result
}
is_nan_s :: proc (x: $F) -> bool where !intrinsics.type_is_simd_vector(F) {
    result := !(x == x)
    return result
}

approximate_equal :: proc (a, b: lane_f32, epsilon : lane_f32 = 0.000001) -> lane_u32 {
    result := less_than(absolute(a - b), epsilon)
    return result
}

shift_left     :: simd.shl
shift_right    :: simd.shr
horizontal_add :: simd.reduce_add_bisect
maximum :: proc (a: $T, b: T) -> T {
    when intrinsics.type_is_simd_vector(T) {
        return simd.max(a, b)
    } else {
        return max(a, b)
    }
}
minimum :: proc (a: $T, b: T) -> T {
    when intrinsics.type_is_simd_vector(T) {
        return simd.min(a, b)
    } else {
        return min(a, b)
    }
}

min_max :: proc (a: $T, b: T) -> (min, max: T) {
    when intrinsics.type_is_simd_vector(T) {
        min, max = b, a
        mask := less_than(a, b)
        conditional_assign(mask, &min, a)
        conditional_assign(mask, &max, b)
        return min, max
    } else {
        min, max = b, a
        if a < b do min, max = a, b
        return min, max
    }
}

extract_v3 :: proc (a: lane_v3, #any_int n: u32) -> (result: v3) {
    result.x = extract(a.x, n)
    result.y = extract(a.y, n)
    result.z = extract(a.z, n)
    return result
}

extract :: proc (a: $T/#simd[$N] $Element, #any_int n: u32) -> (result: Element) {
    when intrinsics.type_is_array(T) {
        #no_bounds_check #unroll for i in 0..<len(T) {
            result[i] = simd.extract(a[i], n)
        }
    } else {
        result = simd.extract(a, n)
    }
    return result
}

// @naming
replace_v3 :: proc (a: ^lane_v3, #any_int n: u32, value: v3) {
    replace(&a.x, n, value.x)
    replace(&a.y, n, value.y)
    replace(&a.z, n, value.z)
}

// @naming
replace :: proc (a: ^$T/ #simd[$N] $Element, #any_int n: u32, value: Element) {
    when intrinsics.type_is_array(T) {
        #no_bounds_check #unroll for i in 0..<len(T) {
            a[i] = simd.replace(a[i], n, value[i])
        }
    } else {
        a^ = simd.replace(a^, n, value)
    }
}

////////////////////////////////////////////////
// Matrix operations

identity :: proc () -> (result: m4) {
    result = 1
    return result
}

transpose :: proc (a: m4) -> (result: m4) {
    #no_bounds_check #unroll for c in 0 ..= 3 {
        #unroll for r in 0 ..= 3 {
            result[c, r] = a[r, c]
        }
    }
    return result
}

////////////////////////////////////////////////

multiply :: proc { multiply3, multiply4 }
multiply4 :: proc (a: m4, p: v4) -> (result: v4) {
    result.x = a[0, 0] * p.x + a[0, 1] * p.y + a[0, 2] * p.z + a[0, 3] * p.w
    result.y = a[1, 0] * p.x + a[1, 1] * p.y + a[1, 2] * p.z + a[1, 3] * p.w
    result.z = a[2, 0] * p.x + a[2, 1] * p.y + a[2, 2] * p.z + a[2, 3] * p.w
    result.w = a[3, 0] * p.x + a[3, 1] * p.y + a[3, 2] * p.z + a[3, 3] * p.w
    
    return result
}
multiply3 :: proc (a: m4, p: v3, w: f32 = 1) -> (result: v3) {
    product := multiply(a, V4(p, w))
    result = product.xyz
    result /= product.w 
    
    return result
}

////////////////////////////////////////////////

x_rotation :: yz_rotation
y_rotation :: xz_rotation
z_rotation :: xy_rotation

xy_rotation :: proc (angle: f32) -> (result: m4) {
    c := cos(angle)
    s := sin(angle)
    
    result = {
        c, -s, 0, 0,
        s,  c, 0, 0,
        0,  0, 1, 0,
        0,  0, 0, 1,
    }
    
    return result
}

yz_rotation :: proc (angle: f32) -> (result: m4) {
    c := cos(angle)
    s := sin(angle)
    
    result = {
        1, 0,  0, 0,
        0, c, -s, 0,
        0, s,  c, 0,
        0, 0,  0, 1,
    }
    
    return result
}

xz_rotation :: proc (angle: f32) -> (result: m4) {
    c := cos(angle)
    s := sin(angle)

    result = {
         c, 0, s, 0,
         0, 1, 0, 0,
        -s, 0, c, 0,
         0, 0, 0, 1,
    }

    return result
}

translate :: proc (a: m4, t: v3) -> (result: m4) {
    result = a
    
    result[0, 3] += t.x
    result[1, 3] += t.y
    result[2, 3] += t.z
    
    return result
}

////////////////////////////////////////////////

get_column :: proc (a: m4, column: u32) -> (result: v3) {
    result.x = a[0, column]
    result.y = a[1, column]
    result.z = a[2, column]
    
    return result
}

get_row :: proc (a: m4, row: u32) -> (result: v3) {
    result.x = a[row, 0]
    result.y = a[row, 1]
    result.z = a[row, 2]
    
    return result
}

rows_3x3 :: proc (x, y, z: v3) -> (result: m4) {
    result = m4 {
        x.x, x.y, x.z, 0,
        y.x, y.y, y.z, 0,
        z.x, z.y, z.z, 0,
          0,   0,   0, 1,
    }
    return result
}

columns_3x3 :: proc (x, y, z: v3) -> (result: m4) {
    result = m4 {
        x.x, y.x, z.x, 0,
        x.y, y.y, z.y, 0,
        x.z, y.z, z.z, 0,
          0,   0,   0, 1,
    }
    return result
}

////////////////////////////////////////////////
// Rectangle operations

rectangle_min_dimension         :: proc { rectangle_min_dimension_2, rectangle_min_dimension_v }
rectangle_min_dimension_2       :: proc(x: $Element, y, w, h: Element) -> Rectangle([2] Element) { return rectangle_min_dimension_v([2]Element{x, y}, [2]Element{w, h}) }
rectangle_min_dimension_v       :: proc(min: $T, dimension: T)         -> Rectangle(T)           { return { min,                      min + dimension          } }
rectangle_min_max               :: proc(min: $T, max: T)               -> Rectangle(T)           { return { min,                      max                      } }
rectangle_center_dimension      :: proc(center: $T, dimension: T)      -> Rectangle(T)           { return { center - (dimension / 2), center + (dimension / 2) } }
rectangle_center_half_dimension :: proc(center: $T, half_dimension: T) -> Rectangle(T)           { return { center - half_dimension,  center + half_dimension  } }

rectangle_inverted_infinity :: proc($R: typeid) -> (result: R) {
    T :: intrinsics.type_field_type(R, "min")
    #assert(intrinsics.type_is_subtype_of(R, Rectangle(T)))
    E :: intrinsics.type_elem_type(T)
    
    result.min = max(E)
    result.max = min(E)
    
    return result
}

rectangle_get_max       :: proc(rect: Rectangle($T)) -> (result: T) { return rect.max }
rectangle_get_min       :: proc(rect: Rectangle($T)) -> (result: T) { return rect.min }
rectangle_get_dimension :: proc(rect: Rectangle($T)) -> (result: T) { return rect.max - rect.min }
rectangle_get_center    :: proc(rect: Rectangle($T)) -> (result: T) { return rect.min + 0.5 * rectangle_get_dimension(rect) }

rectangle_add_radius :: proc(rect: $R/Rectangle($T), radius: T) -> (result: R) {
    result = rect
    result.min -= radius
    result.max += radius
    return result
}

rectangle_scale_radius :: proc(rect: $R/Rectangle($T), factor: T) -> (result: R) {
    result = rect
    center := get_center(rect)
    result.min = linear_blend(center, result.min, factor)
    result.max = linear_blend(center, result.max, factor)
    return result
}

rectangle_add_offset :: proc(rect: $R/Rectangle($T), offset: T) -> (result: R) {
    result.min = rect.min + offset
    result.max = rect.max + offset
    
    return result
}

rectangle_contains :: proc(rect: Rectangle($T), point: T) -> (result: bool) {
    result = true
    #no_bounds_check #unroll for i in 0..<len(T) {
        result &&= rect.min[i] <= point[i] && point[i] < rect.max[i] 
    }
    return result
}

rectangle_contains_inclusive :: proc(rect: Rectangle($T), point: T) -> (result: bool) {
    result = true
    #no_bounds_check #unroll for i in 0..<len(T) {
        result &&= rect.min[i] <= point[i] && point[i] <= rect.max[i] 
    }
    return result
}

dimension_contains :: proc(dimension: $V/[$N]$T, point: V) -> (result: bool) {
    result = true
    #no_bounds_check #unroll for i in 0..<N {
        result &&= 0 <= point[i] && point[i] < dimension[i] 
    }
    return result
}

rectangle_contains_rect :: proc(a: $R/Rectangle($T), b: R) -> (result: bool) {
    u := rectangle_union(a, b)
    result = a == u
    return result
}

rectangle_intersects :: proc(a, b: Rectangle($T)) -> (result: bool) {
    result  = !(b.max.x <= a.min.x || b.min.x >= a.max.x)
    result &= !(b.max.y <= a.min.y || b.min.y >= a.max.y)
    when len(T) >= 3 do result &= !(b.max.z <= a.min.z || b.min.z >= a.max.z)
    
    return result
}


rectangle_intersection :: proc(a, b: $R/Rectangle($T)) -> (result: R) {
    result.min.x = max(a.min.x, b.min.x)
    result.min.y = max(a.min.y, b.min.y)
    
    result.max.x = min(a.max.x, b.max.x)
    result.max.y = min(a.max.y, b.max.y)
    
    when len(T) >= 3 {
        result.min.z = max(a.min.z, b.min.z)
        result.max.z = min(a.max.z, b.max.z)
    }
    return result
    
}

rectangle_union_point :: proc(a: $R/Rectangle($T), b: T) -> (result: R) {
    result.min.x = min(a.min.x, b.x)
    result.min.y = min(a.min.y, b.y)
    
    result.max.x = max(a.max.x, b.x)
    result.max.y = max(a.max.y, b.y)
    
    when len(T) >= 3 {
        result.min.z = min(a.min.z, b.z)
        result.max.z = max(a.max.z, b.z)
    }
    
    return result
}

rectangle_union :: proc(a: $R/Rectangle($T), b: R) -> (result: R) {
    result.min.x = min(a.min.x, b.min.x)
    result.min.y = min(a.min.y, b.min.y)
    
    result.max.x = max(a.max.x, b.max.x)
    result.max.y = max(a.max.y, b.max.y)
    
    when len(T) >= 3 {
        result.min.z = min(a.min.z, b.min.z)
        result.max.z = max(a.max.z, b.max.z)
    }
    
    return result
}

rectangle_get_barycentric :: proc(rect: Rectangle($T), p: T) -> (result: T) {
    result = safe_ratio_or_zero(p - rect.min, rect.max - rect.min)
    
    return result
}

rectangle_xy :: proc(rect: Rectangle3) -> (result: Rectangle2) {
    result.min = rect.min.xy
    result.max = rect.max.xy
    
    return result
}

rectangle_clamped_area :: proc(rect: Rectangle([$N] $E)) -> (result: E) {
    dimension := rect.max - rect.min
    ok := true
    #no_bounds_check #unroll for axis in 0..<N do if dimension[axis] <= 0 { ok = false }
    if ok {
        result = dimension.x * dimension.y
    }
    
    return result
}

rectangle_has_area :: proc(rect: Rectangle2i) -> (result: bool) {
    return rect.min.x < rect.max.x && rect.min.y < rect.max.y
}