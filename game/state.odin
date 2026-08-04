package game

import "core:c"
import "core:fmt"
import "core:math"
import "core:math/linalg"
import "core:strings"
import rl "vendor:raylib"

MAX_SKATERS :: 20
MAX_SURFACES :: 20
BOARD_ASSET_COUNT :: 32

init :: proc(state: ^State) {
	append(&state.skaters, Skater{})
	reset_skater(&state.skaters[0])
	state.skaters[0].color = rl.ORANGE

	state.show_normals = false
	state.color_mode = .Dark
	state.drawing_mode = .Dimetric
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
		if surface.n == a {
			a = rl.Vector3{0, 1, 0} // cross product will give 0, need to use another ref vector
		}

		u := linalg.normalize(linalg.cross(surface.n, a))
		if linalg.dot(u, largest_abs_component(u)) < 0.01 {
			u *= -1
		}
		surface.u = u

		v := linalg.normalize(linalg.cross(surface.n, u))
		if linalg.dot(v, largest_abs_component(v)) < 0.01 {
			v *= -1
		}
		surface.v = v
	}

	for sprite_sheet in Skater_Asset {
		path := fmt.ctprintf("assets/data/anim/anim_%v.png", sprite_sheet)
		state.skater_assets[sprite_sheet] = rl.LoadTexture(path)
	}

	for i in 0 ..< BOARD_ASSET_COUNT {
		path := fmt.ctprintf("assets/data/board/board_Dir%v.png", i)
		state.board_assets[i] = rl.LoadTexture(path)
	}

	for name in Shader {
		lower := strings.to_lower(string(fmt.tprintf("%v", name)), context.temp_allocator)
		fs_path := fmt.ctprintf("assets/shaders/%v.fs", lower)
		state.shaders[name] = rl.LoadShader(nil, fs_path)
	}

	load_config_from_file(&state.config)
	state.shader_uniforms[.Customize] = rl.GetShaderLocation(state.shaders[.Customize], "palette")
}

largest_abs_component :: proc(v: rl.Vector3) -> rl.Vector3 {
	abs := linalg.abs(v)
	if abs.x >= abs.y && abs.x >= abs.z {
		return {1, 0, 0}
	}
	if abs.y >= abs.z {
		return {0, 1, 0}
	}
	return {0, 0, 1}
}

Shape :: struct {
	vertices: [8]rl.Vector3,
	faces:    [4][4]int,
}

Drawing_Mode :: enum {
	Dimetric = 0,
	Top_Down,
	Side,
}

Trick :: enum u8 {
	None,
	Ollie,
	Nollie,
	Kickflip,
	Nollie_Flip,
	Heelflip,
	Nollie_Heel,
	Varial_Flip,
	Nollie_Varial_Flip,
	Varial_Heel,
	Nollie_Varial_Heel,
	Hard_Flip,
	Nollie_Hard_Flip,
	Inward_Heel,
	Nollie_Inward_Heel,
	Shuv_It,
	Nollie_Shuv_It,
	Front_Shuv,
	Nollie_Front_Shuv,
	Tre_Flip,
	Nollie_Tre_Flip,
	Tre_Shuv,
	Nollie_Tre_Shuv,
	Lazer_Flip,
	Nollie_Lazer_Flip,
	Tre_Inward_Heel,
	Nollie_Tre_Inward_Heel,
	Tre_Hard_Flip,
	Nollie_Tre_Hard_Flip,
}

Skater :: struct {
	move_dir:         rl.Vector3,
	look_dir:         rl.Vector3,
	norm:             rl.Vector3,
	pos:              rl.Vector3,
	vel:              rl.Vector3,
	radius:           f32,
	angle:            f32,
	color:            rl.Color,
	state:            Skater_State,
	timer:            [Skater_State]f32,
	jump_height:      f32,
	trick_buffer:     [3]Input_Action,
	trick_buffer_len: u8,
	trick_committed:  Trick,
	trick_caught:     bool,
	skate_angles:     rl.Vector4,
	animation:        Animation,
}

Skater_State :: enum {
	Idle,
	Crouched,
	Airborne,
	Landing,
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
	Dark,
	Light,
}

Skater_Asset :: enum u8 {
	Ride,
	Duck,
	Air,
	Land,
}

Shader :: enum u8 {
	Customize,
}


State :: struct {
	config:            Config,
	target_skater_idx: int,
	skaters:           [dynamic; MAX_SKATERS]Skater,
	surfaces:          [dynamic; MAX_SURFACES]Surface,
	drawing_mode:      Drawing_Mode,
	color_mode:        Color_Mode,
	offset:            rl.Vector2,
	show_normals:      bool,
	skater_assets:     [Skater_Asset]rl.Texture2D,
	board_assets:      [BOARD_ASSET_COUNT]rl.Texture2D,
	shaders:           [Shader]rl.Shader,
	shader_uniforms:   [Shader]c.int,
}
