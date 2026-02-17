package main

Camera :: struct {
	origin:               v3,
	horizontal, vertical: v3,
	lower_left_corner:    v3,
	u, v, w:              v3,
	lens_radius:          f32,
}

camera_init :: proc(c: ^Camera, look_from, look_at: v3, vup: v3, vertical_fov, aspect_ratio, aperture, focus_distance: f32) {
	θ := vertical_fov * RadiansPerDegree
	h := tan(θ / 2)
	viewport_height: f32 = 2 * h
	viewport_width := aspect_ratio * viewport_height

	c.w = normalize(look_from - look_at)
	c.u = normalize(cross(vup, c.w))
	c.v = cross(c.w, c.u)
    
	c.origin = look_from
	c.horizontal = focus_distance * viewport_width * c.u
	c.vertical = focus_distance * viewport_height * c.v
	c.lower_left_corner = c.origin - c.horizontal / 2 - c.vertical / 2 - focus_distance * c.w

	c.lens_radius = aperture / 2
}

camera_get_ray :: proc(c: Camera, s, t: f32) -> Ray {
    spall_proc()
	rd := c.lens_radius * random_in_unit_disk()
	offset := c.u * rd.x + c.v * rd.y
	result := Ray {
        c.origin + offset, 
        c.lower_left_corner + s * c.horizontal + t * c.vertical - (c.origin + offset),
    }
    
    return result
}
