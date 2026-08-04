package game
import "core:c"
import "core:fmt"
import "core:math"
import "core:math/linalg"
import rl "vendor:raylib"

render :: proc(state: ^State) {
	rl.BeginShaderMode(state.shaders[.Customize])
	defer rl.EndShaderMode()

	rl.SetShaderValueV(
		state.shaders[.Customize],
		rl.GetShaderLocation(state.shaders[.Customize], "palette"),
		&state.config.data.customization.skater_colors,
		.IVEC3,
		c.int(6),
	)

	screen := rl.Vector2{f32(rl.GetScreenWidth()), f32(rl.GetScreenHeight())}
	state.offset = screen / 2

	bg := rl.DARKGRAY
	if state.color_mode == .Light {
		bg = rl.WHITE
	}

	rl.ClearBackground(bg)

	rl.DrawFPS(0, 0)

	target := &state.skaters[state.target_skater_idx]

	for &surface in state.surfaces {
		offset := surface.o - target.pos
		draw_surface(state, &surface, offset)
	}

	font_size := state.config.data.ui.font_size
	if target.trick_committed != .None {
		str := fmt.ctprintf("%s", target.trick_committed)
		measure := rl.MeasureText(str, font_size)
		rl.DrawText(
			str,
			(rl.GetScreenWidth() - measure) / 2,
			(rl.GetScreenHeight() - font_size) / 2 - i32(state.config.data.sprite.frame_size),
			font_size,
			rl.ORANGE,
		)
	}

	for &skater in state.skaters {
		offset := skater.pos - target.pos
		draw_board(state, &skater, offset)
		draw_skater(state, &skater, offset)
	}
}

project :: proc(point: rl.Vector3, state: ^State) -> rl.Vector2 {
	cell_size := state.config.data.camera.cell_size
	if state.drawing_mode == .Top_Down {
		return point.xy * cell_size + state.offset
	}
	if state.drawing_mode == .Side {
		return rl.Vector2{-point.y, -point.z} * cell_size + state.offset
	}
	return PRO_MATRIX * point * cell_size + state.offset
}

PRO_MATRIX :: matrix[2, 3]f32{
	1, -1, 0,
	0.5, 0.5, -1,
}

draw_skater :: proc(state: ^State, skater: ^Skater, offset: rl.Vector3) {
	frame_size := state.config.data.sprite.frame_size
	sprite_pos := skater.animation.progress.idx * frame_size
	config := animation_configs[skater.animation.state]
	target_pos := project(offset, state) - frame_size / 2

	rl.DrawTexturePro(
		state.skater_assets[config.asset],
		{sprite_pos.x, sprite_pos.y, frame_size, frame_size},
		{target_pos.x, target_pos.y, frame_size, frame_size},
		{0, 0},
		0,
		rl.WHITE,
	)
}

draw_board :: proc(state: ^State, skater: ^Skater, offset: rl.Vector3) {
	if skater.state != .Airborne {return}
	if skater.skate_angles.zw == {} {return}

	rad := skater.skate_angles.zw
	rad.x += linalg.atan2(skater.look_dir.y, skater.look_dir.x)
	deg := rad * rl.RAD2DEG
	sign := linalg.sign(deg)
	orientation := linalg.mod(deg * sign, 360)
	if sign.x < 0 {orientation.x = 360 - orientation.x}
	if sign.y < 0 {orientation.y = 360 - orientation.y}
	asset_idx := math.round(orientation.x * BOARD_ASSET_COUNT / 360)
	asset_idx = math.clamp(asset_idx, 0, BOARD_ASSET_COUNT - 1)

	frame_size: f32 = 50
	target_pos := project(offset, state) - frame_size / 2
	target_pos.y += state.config.data.sprite.board_y_offset

	sprite_idx: rl.Vector2
	sprite_idx.x = math.round(orientation.y * 21 / 360)
	sprite_idx.x = math.clamp(sprite_idx.x, 0, 20)
	sprite_idx.y = math.ceil(orientation.x * 5 / 360)
	sprite_idx.y = math.clamp(sprite_idx.y, 0, 4)
	sprite_pos := sprite_idx * 50

	rl.DrawTexturePro(
		state.board_assets[int(asset_idx)],
		{sprite_pos.x, sprite_pos.y, frame_size, frame_size},
		{target_pos.x, target_pos.y, frame_size, frame_size},
		{0, 0},
		0,
		rl.WHITE,
	)
}

draw_surface :: proc(state: ^State, surface: ^Surface, offset: rl.Vector3) {
	if state.show_normals {
		rl.DrawCircleV(project(offset, state), 4, rl.BLUE)
		rl.DrawLineEx(project(offset, state), project(surface.n + offset, state), 2, rl.RED)
		rl.DrawLineEx(project(offset, state), project(surface.u + offset, state), 2, rl.GREEN)
		rl.DrawLineEx(project(offset, state), project(surface.v + offset, state), 2, rl.YELLOW)
	}

	for col in 0 ..= surface.w {
		start := surface.u * col + offset
		end := start + surface.v * surface.h
		rl.DrawLineEx(project(start, state), project(end, state), 1.1, rl.Fade(rl.LIGHTGRAY, 0.5))
	}
	for row in 0 ..= surface.h {
		start := surface.v * row + offset
		end := start + surface.u * surface.w
		rl.DrawLineEx(project(start, state), project(end, state), 1.1, rl.Fade(rl.LIGHTGRAY, 0.5))
	}
}
