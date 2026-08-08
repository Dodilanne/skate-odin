package game

import "core:c"
import "core:fmt"
import "core:math"
import "core:math/linalg"
import "core:slice"
import "core:strings"
import rl "vendor:raylib"

MAX_SKATERS :: 100
MAX_OBJECTS :: 100
BOARD_ASSET_COUNT :: 32
COLORS_PER_PALETTE :: 6

init :: proc(state: ^State) {
	for i in 0 ..< 1 {
		append(&state.skaters, Skater{})
		if i == 0 {
			reset_skater(&state.skaters[i], angle = math.PI / 4, pos = {7, 33, 2})
		} else {
			reset_skater(&state.skaters[i])
		}
	}

	state.show_normals = false
	state.drawing_mode = .Dimetric

	init_objects(state)
	init_surfaces(state)
	init_entities(state)

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

	state.palette.loc = rl.GetShaderLocation(state.shaders[.Customize], "palettes")
	state.palette.img = rl.GenImageColor(MAX_SKATERS * COLORS_PER_PALETTE, 1, rl.BLANK)
	state.palette.tex = rl.LoadTextureFromImage(state.palette.img)

	load_config_from_file(&state.config)
	update_state_after_config_update(state)
}

init_objects :: proc(state: ^State) {
	state.objects = {
		{kind = .Ramp, mat = .Concrete, pos = {16, 0, 2}, size = {2, 36, 1}, orientation = .West},
		{kind = .Ramp, mat = .Wood, pos = {1, 10, 3}, size = {11, 2, 1}},
		{kind = .Box, mat = .Brick, pos = {0, 1, 3}, size = {1, 12, 2}},
		{kind = .Box, mat = .Brick, pos = {0, 0, 3}, size = {13, 1, 2}},
		{kind = .Box, mat = .Brick, pos = {12, 1, 3}, size = {1, 12, 2}},
		{kind = .Ramp, mat = .Brick, pos = {5, 40, 2}, size = {5, 5, 2}, orientation = .East},
		{kind = .Box, mat = .Concrete, pos = {0, 0, 2}, size = {16, 26, 1}},
		{kind = .Box, mat = .Wood, pos = {1, 1, 3}, size = {11, 9, 1}},
		{kind = .Box, mat = .Concrete, pos = {0, 0, -40}, size = {50, 50, 42}},
	}
}

init_surfaces :: proc(state: ^State) {
	for object in state.objects {
		switch object.kind {
		case .Box:
			append(
				&state.surfaces,
				Surface {
					o = object.pos + {0, 0, object.size.z},
					w = object.size.x,
					h = object.size.y,
					n = {0, 0, 1},
					u = {1, 0, 0},
					v = {0, 1, 0},
				},
				Surface {
					o = object.pos,
					w = object.size.x,
					h = object.size.z,
					n = {0, -1, 0},
					u = {1, 0, 0},
					v = {0, 0, 1},
				},
				Surface {
					o = object.pos + {object.size.x, 0, 0},
					w = object.size.y,
					h = object.size.z,
					n = {1, 0, 0},
					u = {0, 1, 0},
					v = {0, 0, 1},
				},
				Surface {
					o = object.pos + {0, object.size.y, 0},
					w = object.size.x,
					h = object.size.z,
					n = {0, 1, 0},
					u = {1, 0, 0},
					v = {0, 0, 1},
				},
				Surface {
					o = object.pos,
					w = object.size.y,
					h = object.size.z,
					n = {-1, 0, 0},
					u = {0, 1, 0},
					v = {0, 0, 1},
				},
			)
		case .Ramp:
			squared_size := object.size * object.size
			switch object.orientation {
			case .North:
				v := linalg.normalize(
					rl.Vector3RotateByAxisAngle(
						{0, -1, 0},
						{1, 0, 0},
						-math.atan2_f32(object.size.z, object.size.y),
					),
				)
				u := rl.Vector3{1, 0, 0}
				n := linalg.normalize(linalg.cross(v, u))
				append(
					&state.surfaces,
					Surface {
						o = object.pos + {0, object.size.y, 0},
						w = object.size.x,
						h = math.sqrt(squared_size.y + squared_size.z),
						n = n,
						u = u,
						v = v,
					},
					Surface {
						o = object.pos,
						w = object.size.x,
						h = object.size.z,
						n = {0, -1, 0},
						u = {1, 0, 0},
						v = {0, 0, 1},
					},
				)
			case .East:
				v := linalg.normalize(
					rl.Vector3RotateByAxisAngle(
						{1, 0, 0},
						{0, 1, 0},
						-math.atan2_f32(object.size.z, object.size.x),
					),
				)
				u := rl.Vector3{0, 1, 0}
				n := linalg.normalize(linalg.cross(v, u))
				append(
					&state.surfaces,
					Surface {
						o = object.pos,
						w = object.size.y,
						h = math.sqrt(squared_size.x + squared_size.z),
						n = n,
						u = u,
						v = v,
					},
					Surface {
						o = object.pos + {object.size.x, 0, 0},
						w = object.size.y,
						h = object.size.z,
						n = {1, 0, 0},
						u = {0, 1, 0},
						v = {0, 0, 1},
					},
				)
			case .South:
				v := linalg.normalize(
					rl.Vector3RotateByAxisAngle(
						{0, 1, 0},
						{1, 0, 0},
						math.atan2_f32(object.size.z, object.size.y),
					),
				)
				u := rl.Vector3{1, 0, 0}
				n := linalg.normalize(linalg.cross(u, v))
				append(
					&state.surfaces,
					Surface {
						o = object.pos,
						w = object.size.x,
						h = math.sqrt(squared_size.y + squared_size.z),
						n = n,
						u = u,
						v = v,
					},
					Surface {
						o = object.pos + {0, object.size.y, 0},
						w = object.size.x,
						h = object.size.z,
						n = {0, 1, 0},
						u = {1, 0, 0},
						v = {0, 0, 1},
					},
				)
			case .West:
				v := linalg.normalize(
					rl.Vector3RotateByAxisAngle(
						{-1, 0, 0},
						{0, 1, 0},
						math.atan2_f32(object.size.z, object.size.x),
					),
				)
				u := rl.Vector3{0, 1, 0}
				n := linalg.normalize(linalg.cross(u, v))
				append(
					&state.surfaces,
					Surface {
						o = object.pos + {object.size.x, 0, 0},
						w = object.size.y,
						h = math.sqrt(squared_size.x + squared_size.z),
						n = n,
						u = u,
						v = v,
					},
					Surface {
						o = object.pos,
						w = object.size.y,
						h = object.size.z,
						n = {-1, 0, 0},
						u = {0, 1, 0},
						v = {0, 0, 1},
					},
				)
			}
		}
	}
}

init_entities :: proc(state: ^State) {
	clear(&state.entities)
	for &object, idx in state.objects {
		max := object.pos + object.size
		if object.kind == .Ramp {max.z = object.pos.z}
		append(&state.entities, Entity{object.pos, max, u16(idx), .Object, object.kind})
	}
	for &skater, idx in state.skaters {
		append(&state.entities, Entity{skater.pos, skater.pos, u16(idx), .Skater, .Box})
	}
	slice.stable_sort_by(state.entities[:], sort_entity)
}

sort_entity :: proc(a, b: Entity) -> bool {
	return a.max.x <= b.min.x || a.max.y <= b.min.y || a.max.z <= b.min.z
}

Object_Material :: enum u8 {
	Concrete,
	Wood,
	Brick,
}

Object_Kind :: enum u8 {
	Box,
	Ramp,
}

Object_Orientation :: enum u8 {
	North,
	East,
	South,
	West,
}

Object :: struct {
	kind:        Object_Kind,
	mat:         Object_Material,
	pos:         rl.Vector3,
	size:        rl.Vector3,
	orientation: Object_Orientation,
}

vec_to_color :: proc(vec: rl.Vector3) -> rl.Color {
	return rl.Color{u8(vec.x), u8(vec.y), u8(vec.z), 255}
}

update_state_after_config_update :: proc(state: ^State) {
	pixels := [(1 + MAX_SKATERS) * COLORS_PER_PALETTE]rl.Color{}
	// Reference palette is storerd in the first slot
	src := src_palette()
	for j in 0 ..< COLORS_PER_PALETTE {
		pixels[j] = vec_to_color(src[j])
	}
	// Following slots are for skaters
	for palette, i in state.config.data.customization.palettes {
		for j in 0 ..< COLORS_PER_PALETTE {
			pixels[(i + 1) * COLORS_PER_PALETTE + j] = vec_to_color(palette[j])
		}
	}
	rl.UpdateTexture(state.palette.tex, &pixels)
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
	Top,
	South,
	East,
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
	o: rl.Vector3,
	w: f32,
	h: f32,
	n: rl.Vector3,
	u: rl.Vector3,
	v: rl.Vector3,
}

Skater_Asset :: enum u8 {
	Ride,
	Duck,
	Air,
	Land,
	Onspot,
}

Shader :: enum u8 {
	Customize,
}

Palette :: struct {
	loc: c.int,
	img: rl.Image,
	tex: rl.Texture2D,
}

Play_Mode :: enum u8 {
	Play,
	Ghost,
}

Entity_Kind :: enum u8 {
	Object,
	Skater,
}

Entity :: struct {
	min:         rl.Vector3,
	max:         rl.Vector3,
	idx:         u16,
	entity_kind: Entity_Kind,
	object_kind: Object_Kind,
}

State :: struct {
	config:            Config,
	target_skater_idx: int,
	skaters:           [dynamic; MAX_SKATERS]Skater,
	surfaces:          [dynamic; MAX_OBJECTS * 5]Surface,
	objects:           [dynamic; MAX_OBJECTS]Object,
	drawing_mode:      Drawing_Mode,
	offset:            rl.Vector2,
	show_normals:      bool,
	skater_assets:     [Skater_Asset]rl.Texture2D,
	board_assets:      [BOARD_ASSET_COUNT]rl.Texture2D,
	shaders:           [Shader]rl.Shader,
	palette:           Palette,
	play_mode:         Play_Mode,
	entities:          [dynamic; MAX_SKATERS + MAX_OBJECTS]Entity,
}
