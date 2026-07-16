package game

import "core:math"
import "core:math/linalg"
import rl "vendor:raylib"

init :: proc(state: ^State) {
	state.show_normals = false
	state.color_mode = .dark
	state.drawing_mode = .dimetric
	state.player = initial_player
	state.surfaces = {
		{name = "floor_1", o = {1, 1, 4}, w = 11, h = 9, n = {0, 0, 1}},
		{name = "ledge_1_top", o = {0, 0, 5}, w = 1, h = 13, n = {0, 0, 1}},
		{name = "ledge_1_side_long", o = {1, 1, 4}, w = 9, h = 1, n = {1, 0, 0}},
		{name = "ledge_1_side_tall", o = {1, 10, 3}, w = 3, h = 2, n = {1, 0, 0}},
		{name = "ledge_1_front_tall", o = {0, 13, 3}, w = 1, h = 2, n = {0, 1, 0}},
		{name = "ledge_2_top", o = {1, 0, 5}, w = 12, h = 1, n = {0, 0, 1}},
		{name = "ledge_2_side", o = {1, 1, 4}, w = 11, h = 1, n = {0, 1, 0}},
		{name = "ledge_3_side", o = {12, 1, 5}, w = 1, h = 12, n = {0, 0, 1}},
		{name = "ledge_3_side_tall", o = {13, 0, 3}, w = 13, h = 2, n = {1, 0, 0}},
		{name = "ledge_3_back_tall", o = {12, 0, 3}, w = 13, h = 2, n = {-1, 0, 0}},
		{name = "ledge_3_front_tall", o = {12, 13, 3}, w = 1, h = 2, n = {0, 1, 0}},
		{name = "floor_2", o = {0, 0, 3}, w = 16, h = 26, n = {0, 0, 1}},
		{name = "floor_3", o = {0, 0, 2}, w = 50, h = 50, n = {0, 0, 1}},
		{
			name = "jump_1",
			o = {1, 10, 4},
			w = 11,
			h = math.sqrt(f32(2 * 2 + 1 * 1)),
			n = rl.Vector3RotateByAxisAngle({0, 0, 1}, {1, 0, 0}, -math.atan2_f32(1, 2)),
		},
		{
			name = "jump_2",
			o = {16, 0, 3},
			w = 26,
			h = math.sqrt(f32(2 * 2 + 1 * 1)),
			n = rl.Vector3RotateByAxisAngle({0, 0, 1}, {0, 1, 0}, math.atan2_f32(1, 2)),
		},
	}

	for &surface in state.surfaces {
		surface.n = linalg.normalize(surface.n)

		a := rl.Vector3{0, 0, 1} // arbitrary
		if surface.n == a do a = rl.Vector3{0, 1, 0} // cross product will give 0, need to use another ref vector

		u := linalg.normalize(linalg.cross(surface.n, a))
		if linalg.dot(u, largest_abs_component(u)) < 0.01 do u *= -1
		surface.u = u

		v := linalg.normalize(linalg.cross(surface.n, u))
		if linalg.dot(v, largest_abs_component(v)) < 0.01 do v *= -1
		surface.v = v
	}
}

largest_abs_component :: proc(v: rl.Vector3) -> rl.Vector3 {
	abs := linalg.abs(v)
	if abs.x >= abs.y && abs.x >= abs.z do return {1, 0, 0}
	if abs.y >= abs.z do return {0, 1, 0}
	return {0, 0, 1}
}

Shape :: struct {
	vertices: [8]rl.Vector3,
	faces:    [4][4]int,
}

Drawing_Mode :: enum {
	dimetric = 0,
	top_down,
	side,
}


Player :: struct {
	move_dir:   rl.Vector3,
	look_dir:   rl.Vector3,
	norm:       rl.Vector3,
	pos:        rl.Vector3,
	vel:        rl.Vector3,
	forces:     rl.Vector3,
	mass:       f32,
	steer_rate: f32,
	max_speed:  f32,
	radius:     f32,
	airborne:   bool,
	angle:      f32,
}

Surface :: struct {
	name: string,
	o:    rl.Vector3,
	w:    f32,
	h:    f32,
	n:    rl.Vector3,
	u:    rl.Vector3,
	v:    rl.Vector3,
}

Color_Mode :: enum {
	dark,
	light,
}

State :: struct {
	player:       Player,
	surfaces:     [dynamic; 20]Surface,
	drawing_mode: Drawing_Mode,
	color_mode:   Color_Mode,
	cell_size:    f32,
	offset:       rl.Vector2,
	show_normals: bool,
}
