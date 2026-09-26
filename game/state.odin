package game

import "core:c"
import "core:fmt"
import "core:math"
import "core:math/linalg"
import "core:slice"
import "core:strings"
import rl "vendor:raylib"

MAX_SKATERS :: 1
MAX_OBJECTS :: 100
BOARD_ASSET_COUNT :: 32
COLORS_PER_PALETTE :: 6

init :: proc(state: ^State) {
	state.spawn_points = {{-8, -8, 0, 0}, {8, -8, 0, 0}, {8, 8, 0, 0}, {-8, 8, 0, 0}}

	for i in 0 ..< MAX_SKATERS {
		append(&state.skaters, Skater{})
		state.skaters[i].idx = i
		state.skaters[i].last_respawn_point = state.spawn_points[0]
		reset_skater(&state.skaters[i])
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
		{kind = .Box, mat = .Concrete, pos = {-20, -20, -40}, size = {40, 40, 40}},
		{kind = .Box, mat = .Brick, pos = {-6, -6, 0}, size = {12, 12, 1}, grindable = true},
		{kind = .Box, mat = .Wood, pos = {12, -6, 0}, size = {0.1, 12, 1}, grindable = true},
	}
}

ramp_axis_info :: proc(
	size: rl.Vector3,
	axis_is_y: bool,
) -> (
	axis_vec, u: rl.Vector3,
	width, axis_size: f32,
) {
	axis_vec = axis_is_y ? {0, 1, 0} : {1, 0, 0}
	u = axis_is_y ? {1, 0, 0} : {0, 1, 0}
	width = axis_is_y ? size.x : size.y
	axis_size = axis_is_y ? size.y : size.x
	return
}

build_wall_surface :: proc(pos, size: rl.Vector3, axis_is_y, high: bool) -> Surface {
	axis_vec, u, width, axis_size := ramp_axis_info(size, axis_is_y)
	n := axis_vec * (high ? 1 : -1)
	offset := high ? axis_vec * axis_size : rl.Vector3{0, 0, 0}
	return Surface{o = pos + offset, w = width, h = size.z, n = n, u = u, v = {0, 0, 1}}
}

build_grind_edge :: proc(surface: ^Surface, a, b: rl.Vector3) -> (edge: Grind_Edge) {
	edge.o = surface.o + a
	edge.v = b - a
	edge.n = surface.n
	edge.i = linalg.normalize(linalg.cross(edge.n, edge.v))
	return
}

build_incline_surface :: proc(pos, size: rl.Vector3, axis_is_y, high: bool) -> Surface {
	axis_vec, u, width, axis_size := ramp_axis_info(size, axis_is_y)
	angle_sign: f32 = (axis_is_y == high) ? 1 : -1
	base_dir := axis_vec * (high ? 1 : -1)
	angle := angle_sign * math.atan2_f32(size.z, axis_size)
	v := linalg.normalize(rl.Vector3RotateByAxisAngle(base_dir, u, angle))
	n := linalg.normalize(angle_sign > 0 ? linalg.cross(u, v) : linalg.cross(v, u))
	offset := high ? rl.Vector3{0, 0, 0} : axis_vec * axis_size
	h := math.sqrt(axis_size * axis_size + size.z * size.z)
	return Surface{o = pos + offset, w = width, h = h, n = n, u = u, v = v}
}

init_surfaces :: proc(state: ^State) {
	for object in state.objects {
		switch object.kind {
		case .Box:
			top := Surface {
				o = object.pos + {0, 0, object.size.z},
				w = object.size.x,
				h = object.size.y,
				n = {0, 0, 1},
				u = {1, 0, 0},
				v = {0, 1, 0},
			}

			if object.grindable {
				append(
					&top.grind_edges,
					build_grind_edge(&top, {}, {top.w, 0, 0}),
					build_grind_edge(&top, {top.w, 0, 0}, {top.w, top.h, 0}),
					build_grind_edge(&top, {top.w, top.h, 0}, {0, top.h, 0}),
					build_grind_edge(&top, {0, top.h, 0}, {}),
				)
			}

			append(
				&state.surfaces,
				top,
				build_wall_surface(object.pos, object.size, true, false),
				build_wall_surface(object.pos, object.size, true, true),
				build_wall_surface(object.pos, object.size, false, true),
				build_wall_surface(object.pos, object.size, false, false),
			)
		case .Ramp:
			axis_is_y, high: bool
			switch object.orientation {
			case .North:
				axis_is_y, high = true, false
			case .South:
				axis_is_y, high = true, true
			case .East:
				axis_is_y, high = false, true
			case .West:
				axis_is_y, high = false, false
			}
			append(
				&state.surfaces,
				build_incline_surface(object.pos, object.size, axis_is_y, high),
				build_wall_surface(object.pos, object.size, axis_is_y, high),
			)
		}
	}
}

init_entities :: proc(state: ^State) {
	clear(&state.entities)
	for &object, idx in state.objects {
		max := object.pos + object.size
		if object.kind == .Ramp do max.z = object.pos.z
		append(&state.entities, Entity{object.pos, max, u16(idx), .Object, object.kind})
	}
	for &skater, idx in state.skaters {
		// TODO: Remove this cheat
		if skater_state, ok := skater.state.(Skater_State_Grinding); ok {
			append(&state.entities, Entity{10000, 10000, u16(idx), .Skater, .Box})
		} else {
			append(&state.entities, Entity{skater.pos, skater.pos, u16(idx), .Skater, .Box})
		}
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
	grindable:   bool,
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


Grind_Trick :: enum u8 {
	Fifty_Fifty,
	Five_O,
	Over_Salad,
	Salad_Grind,
	Nose_Grind,
	Over_Crook,
	Crooked_Grind,
	Smith_Grind,
	Feeble_Grind,
	Willy_Grind,
	Suski_Grind,
	Board_Slide,
	Lip_Slide,
	Tail_Slide,
	Blunt_Slide,
	Nose_Slide,
	Nose_Blunt,
}

Skater :: struct {
	idx:                int,
	pos:                rl.Vector3,
	vel:                rl.Vector3,
	look_dir:           rl.Vector3,
	anim:               Animation,
	color:              rl.Color,
	state:              Skater_State,
	timer:              f32,
	last_respawn_point: rl.Vector4,
}

Grind_State :: struct {
	trick:  Grind_Trick,
	target: Grind_Edge,
}

Trick_Buffer :: struct {
	buf: [3]Input_Action,
	len: u8,
}

Jump_State :: struct {
	height:       f32,
	start_pos:    rl.Vector3,
	skate_angles: rl.Vector4,
}

Skater_State_Idle :: struct {}

Skater_State_Grinding :: struct {
	grind: Grind_State,
}

Skater_State_Crouched :: struct {
	prev_state: union {
		Skater_State_Idle,
		Skater_State_Grinding,
	},
	trick_buf:  Trick_Buffer,
}

Skater_State_Airborne :: struct {
	trick_buf: Trick_Buffer,
	committed: Trick,
	caught:    bool,
	jump:      Jump_State,
}

Skater_State_Landing :: struct {
	jump:           Jump_State,
	landing_factor: f32,
}

Skater_State_Dropping :: struct {}

Skater_State_Ghost :: struct {}

Skater_State :: union {
	Skater_State_Idle,
	Skater_State_Grinding,
	Skater_State_Crouched,
	Skater_State_Airborne,
	Skater_State_Landing,
	Skater_State_Dropping,
	Skater_State_Ghost,
}

Surface :: struct {
	o:           rl.Vector3,
	w:           f32,
	h:           f32,
	n:           rl.Vector3,
	u:           rl.Vector3,
	v:           rl.Vector3,
	grind_edges: [dynamic; 4]Grind_Edge,
}

Grind_Edge :: struct {
	o: rl.Vector3, // origin
	v: rl.Vector3, // the edge's vector
	n: rl.Vector3, // normal
	i: rl.Vector3, // inner normal
}

Skater_Asset :: enum u8 {
	Ride,
	Duck,
	Air,
	Land,
	Onspot,
	Allgrind2,
}

Shader :: enum u8 {
	Customize,
}

Palette :: struct {
	loc: c.int,
	img: rl.Image,
	tex: rl.Texture2D,
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
	entities:          [dynamic; MAX_SKATERS + MAX_OBJECTS]Entity,
	spawn_points:      [dynamic; 9]rl.Vector4,
}
