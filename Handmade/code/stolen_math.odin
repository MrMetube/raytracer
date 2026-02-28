package main

import "core:math"
// @note(viktor): This is a direct copypasta from the core:math functions, which were then adapted to SIMD.

@(require_results)
atan2_lane_f32 :: proc (y, x: lane_f32) -> lane_f32 {
	return cast(lane_f32) atan2_lane_f64(cast(lane_f64) y, cast(lane_f64) x)
}

@(require_results)
atan2_lane_f64 :: proc (y, x: lane_f64) -> lane_f64 {
	// The original C code:
	//   Stephen L. Moshier
	//   moshier@na-net.ornl.gov

	NAN :: 0h7fff_ffff_ffff_ffff
	INF :: 0h7FF0_0000_0000_0000
	PI  :: 0h4009_21fb_5444_2d18

	atan :: proc (x: lane_f64) -> lane_f64 {
        result: lane_f64
        result = -s_atan(-x)
        conditional_assign(equal(x, 0), &result, x)
        conditional_assign(greater_than(x, 0), &result, s_atan(x))
        return result
		// if x == 0 {
		// 	return x
		// }
		// if x > 0 {
		// 	return s_atan(x)
		// }
		// return -s_atan(-x)
	}
	// s_atan reduces its argument (known to be positive) to the range [0, 0.66] and calls x_atan.
	s_atan :: proc (x: lane_f64) -> lane_f64 {
		MORE_BITS :: 6.123233995736765886130e-17 // pi/2 = PIO2 + MORE_BITS
		TAN3PI08  :: 2.41421356237309504880      // tan(3*pi/8)
        result: lane_f64
        result = PI/4 + x_atan((x-1)/(x+1)) + 0.5*MORE_BITS
        conditional_assign(less_equal(x, 0.66), &result, x_atan(x))
        conditional_assign(greater_than(x, TAN3PI08), &result, PI/2 - x_atan(1/x) + MORE_BITS)
        return result
		// if x <= 0.66 {
		// 	return x_atan(x)
		// }
		// if x > TAN3PI08 {
		// 	return PI/2 - x_atan(1/x) + MORE_BITS
		// }
		// return PI/4 + x_atan((x-1)/(x+1)) + 0.5*MORE_BITS
	}
	// x_atan evaluates a series valid in the range [0, 0.66].
	x_atan :: proc "contextless" (x: lane_f64) -> lane_f64 {
		P0 :: -8.750608600031904122785e-01
		P1 :: -1.615753718733365076637e+01
		P2 :: -7.500855792314704667340e+01
		P3 :: -1.228866684490136173410e+02
		P4 :: -6.485021904942025371773e+01
		Q0 :: +2.485846490142306297962e+01
		Q1 :: +1.650270098316988542046e+02
		Q2 :: +4.328810604912902668951e+02
		Q3 :: +4.853903996359136964868e+02
		Q4 :: +1.945506571482613964425e+02

		z := x * x
		z = z * ((((P0*z+P1)*z+P2)*z+P3)*z + P4) / (((((z+Q0)*z+Q1)*z+Q2)*z+Q3)*z + Q4)
		z = x*z + x
		return z
	}
    
    q := atan(y / x)
    
    // @note(viktor): Somehow this worked with all samples from the raytracer on the first try!?
    // Double check that this order is actually from most to least specific and that there are no typos.
    result: lane_f64
    open := lane_true_64
    conditional_assign_once(&open, is_nan(y) | is_nan(x),                                   &result, NAN)
    conditional_assign_once(&open, equal(y, 0) &   greater_equal(x, 0) & ~sign_bit_f64(x),  &result, copy_sign_f64(0.0, y))
    conditional_assign_once(&open, equal(y, 0) & ~(greater_equal(x, 0) & ~sign_bit_f64(x)), &result, copy_sign_f64(PI, y))
    conditional_assign_once(&open, equal(x, 0),                                             &result, copy_sign_f64(PI/2, y))
    conditional_assign_once(&open, is_inf(x) &  is_inf(x, 1) & is_inf(y, 0),                &result, copy_sign_f64(PI/4, y))
    conditional_assign_once(&open, is_inf(x) &  is_inf(x, 1) & ~is_inf(y, 0),               &result, copy_sign_f64(PI/4, y))
    conditional_assign_once(&open, is_inf(x) & ~is_inf(x, 1) & equal(y, 0),                 &result, copy_sign_f64(3*PI/4, y))
    conditional_assign_once(&open, is_inf(x),                                               &result, copy_sign_f64(PI, y))
    conditional_assign_once(&open, is_inf(y),                                               &result, copy_sign_f64(PI/2, y))
    conditional_assign_once(&open, less_than(x, 0) & less_equal(q, 0),                      &result, q + PI)
    conditional_assign_once(&open, less_than(x, 0),                                         &result, q - PI)
    conditional_assign_once(&open, lane_true_64,                                            &result, q)
    return result
}

conditional_assign_once :: proc (open: ^$M, mask: M, dest: ^$D, value: D) {
    conditional_assign(mask & open^, dest, value)
    open^ = open^ &~ mask
}

@(require_results)
acos_lane_f32 :: proc (x: lane_f32) -> lane_f32 {
	return lane_f32(acos_lane_f64(lane_f64(x)))
}


@(require_results)
acos_lane_f64 :: proc (x: lane_f64) -> lane_f64 {
	/* origin: FreeBSD /usr/src/lib/msun/src/e_acos.c */
	/*
	 * ====================================================
	 * Copyright (C) 1993 by Sun Microsystems, Inc. All rights reserved.
	 *
	 * Developed at SunSoft, a Sun Microsystems, Inc. business.
	 * Permission to use, copy, modify, and distribute this
	 * software is freely granted, provided that this notice
	 * is preserved.
	 * ====================================================
	 */

	pio2_hi :: 0h3FF921FB54442D18
	pio2_lo :: 0h3C91A62633145C07
	pS0     :: 0h3FC5555555555555
	pS1     :: 0hBFD4D61203EB6F7D
	pS2     :: 0h3FC9C1550E884455
	pS3     :: 0hBFA48228B5688F3B
	pS4     :: 0h3F49EFE07501B288
	pS5     :: 0h3F023DE10DFDF709
	qS1     :: 0hC0033A271C8A2D4B
	qS2     :: 0h40002AE59C598AC8
	qS3     :: 0hBFE6066C1B8D0159
	qS4     :: 0h3FB3B8C5B12E9282

	R :: #force_inline proc "contextless" (z: lane_f64) -> lane_f64 {
		p, q: lane_f64
		p = z*(pS0+z*(pS1+z*(pS2+z*(pS3+z*(pS4+z*pS5)))))
		q = 1.0+z*(qS1+z*(qS2+z*(qS3+z*qS4)))
		return p/q
	}

	z, w, s, c, df: lane_f64
	dwords := transmute([LaneWidth][2]u32)x
	hx := transmute(lane_u32) [LaneWidth] u32 { dwords[0][1], dwords[1][1], dwords[2][1], dwords[3][1], dwords[4][1], dwords[5][1], dwords[6][1], dwords[7][1] }
	ix := hx & 0x7fffffff
    
	lx := transmute(lane_u32) [LaneWidth] u32 { dwords[0][0], dwords[1][0], dwords[2][0], dwords[3][0], dwords[4][0], dwords[5][0], dwords[6][0], dwords[7][0] }
    
    open := lane_true
    result: lane_f64
    c1 := greater_equal(ix, 0x3ff00000)
    c2 := equal((ix-0x3ff00000 | lx), 0)
    c3 := less_than(ix, 0x3fe00000)
    conditional_assign_once(&open, c1  & c2 & not_equal(shift_right(hx, 31), 0), &result, 2*pio2_hi + 1e-120)
    conditional_assign_once(&open, c1  & c2,                                     &result, 0)
    conditional_assign_once(&open, c1,                                           &result, 0/(x-x))
    conditional_assign_once(&open, c3  & less_equal(ix, 0x3c600000),             &result, pio2_hi + 1e-120)
    conditional_assign_once(&open, c3,                                           &result, pio2_hi - (x - (pio2_lo-x*R(x*x))))
    
    z = (1.0+x)*0.5
    s = square_root(z)
    w = R(z)*s-pio2_lo
    r1 := 2*(pio2_hi - (s+w))
    
    z = (1.0-x)*0.5
	s = square_root(z)
	df = s
	(^lane_u64)(&df)^ &= 0xffffffff_00000000
	c = (z-df*df)/(s+df)
	w = R(z)*s+c
	r2 :=  2*(df+w)
    conditional_assign_once(&open, not_equal(shift_right(hx, 31), 0), &result, r1)
    conditional_assign_once(&open, lane_true, &result, r2)
    
    return result
}

@(require_results) sign_bit_f64   :: proc (x: lane_f64)   -> lane_u64 {
    ix := transmute(lane_u64) x
    return not_equal(ix & (1<<63), 0)
}

@(require_results)
copy_sign_f64 :: proc (x, y: lane_f64) -> lane_f64 {
    ix := transmute(lane_u64) x
    iy := transmute(lane_u64) y
    ix &= 0x7fff_ffff_ffff_ffff
    ix |= iy & 0x8000_0000_0000_0000
    return transmute(lane_f64) ix
}

@(require_results)
is_inf :: proc (x: lane_f64, sign := 0) -> lane_u64 {
    result: lane_u64
    conditional_assign(equal(x*0.5, x) &  less_than(x, 0), &result, sign <= 0 ? lane_true_64 : lane_false_64)
    conditional_assign(equal(x*0.5, x) & ~less_than(x, 0), &result, sign >= 0 ? lane_true_64 : lane_false_64)
    return result
}