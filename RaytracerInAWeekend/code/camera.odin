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

camera_init :: proc(
	using c: ^Camera,
	look_from, look_at: Point,
	vup: Vec3,
	vertical_fov, aspect_ratio, aperture, focus_distance: f32,
) {
	θ := math.to_radians(vertical_fov)
	h := math.tan(θ / 2)
	viewport_height: f32 = 2 * h
	viewport_width := aspect_ratio * viewport_height

	w = linalg.normalize(look_from - look_at)
	u = linalg.normalize(linalg.cross(vup, w))
	v = linalg.cross(w, u)

	origin = look_from
	horizontal = focus_distance * viewport_width * u
	vertical = focus_distance * viewport_height * v
	lower_left_corner = origin - horizontal / 2 - vertical / 2 - focus_distance * w

	lens_radius = aperture / 2
}

camera_get_ray :: proc(using c: Camera, s, t: f32) -> Ray {
	rd := lens_radius * random_in_unit_disk()
	offset := u * rd.x + v * rd.y
	return(
		Ray {origin + offset, lower_left_corner + s * horizontal + t * vertical - (origin + offset)} \
	)
}
