package main

import "core:math"
import "core:math/linalg"

Camera :: struct {
	origin:               Point,
	horizontal, vertical: Vec3,
	lower_left_corner:    Vec3,
	u, v, w:              Vec3,
	lens_radius:          f32,
}

camera_init :: proc(c: ^Camera, look_from, look_at: Point, vup: Vec3, vertical_fov, aspect_ratio, aperture, focus_distance: f32) {
	θ := math.to_radians(vertical_fov)
	h := math.tan(θ / 2)
	viewport_height: f32 = 2 * h
	viewport_width := aspect_ratio * viewport_height

	c.w = linalg.normalize(look_from - look_at)
	c.u = linalg.normalize(linalg.cross(vup, c.w))
	c.v = linalg.cross(c.w, c.u)
    
	c.origin = look_from
	c.horizontal = focus_distance * viewport_width * c.u
	c.vertical = focus_distance * viewport_height * c.v
	c.lower_left_corner = c.origin - c.horizontal / 2 - c.vertical / 2 - focus_distance * c.w

	c.lens_radius = aperture / 2
}

camera_get_ray :: proc(c: Camera, s, t: f32) -> Ray {
	rd := c.lens_radius * random_in_unit_disk()
	offset := c.u * rd.x + c.v * rd.y
	result := Ray {
        c.origin + offset, 
        c.lower_left_corner + s * c.horizontal + t * c.vertical - (c.origin + offset)
    }
    
    return result
}
