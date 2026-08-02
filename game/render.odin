package game

import "core:fmt"
import "core:math"
import "core:math/linalg"
import rl "vendor:raylib"

render :: proc(state: ^State) {
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
		draw_surface_wireframe(state, &surface, offset)
	}

	for &skater in state.skaters {
		offset := skater.pos - target.pos

		draw_skater_sprite(state, &skater, offset)

		if skater.skate_angles.z != 0 {
			ax := skater.skate_angles.z + linalg.atan2(skater.look_dir.y, skater.look_dir.x)
			rx := rl.Vector3RotateByAxisAngle({1, 0, 0}, {0, 0, 1}, ax)
			rl.DrawLineEx(project(offset, state), project(rx + offset, state), 4, rl.BLUE)
		}

		if skater.skate_angles.w != 0 {
			ay := skater.skate_angles.w
			ry := rl.Vector3RotateByAxisAngle({0, 0, 1}, skater.look_dir, ay)
			rl.DrawLineEx(project(offset, state), project(ry + offset, state), 4, rl.YELLOW)
		}
	}

	font_size := state.config.ui.font_size
	rl.DrawText(
		fmt.ctprintf("%v", target.timer),
		rl.GetScreenWidth() / 2 + 30,
		(rl.GetScreenHeight() - font_size) / 2,
		font_size,
		rl.WHITE,
	)
	str := fmt.ctprintf("%v", target.state)
	measure := rl.MeasureText(str, font_size)
	rl.DrawText(
		str,
		(rl.GetScreenWidth() - measure) / 2,
		(rl.GetScreenHeight() + font_size) / 2 + i32(state.config.sprite.frame_size),
		font_size,
		rl.WHITE,
	)
	if target.trick_committed != .None {
		str := fmt.ctprintf("%s", target.trick_committed)
		measure := rl.MeasureText(str, font_size)
		rl.DrawText(
			str,
			(rl.GetScreenWidth() - measure) / 2,
			(rl.GetScreenHeight() - font_size) / 2 - i32(state.config.sprite.frame_size),
			font_size,
			rl.YELLOW,
		)
	}
}

project :: proc(point: rl.Vector3, state: ^State) -> rl.Vector2 {
	cell_size := state.config.camera.cell_size
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

skater_rot_to_sprite_idx :: proc(skater: ^Skater) -> f32 {
	look_angle := rl.Vector2Angle({1, 0}, skater.look_dir.xy)
	if skater.look_dir.y < 0 {look_angle = 2 * math.PI - look_angle}
	return math.round((look_angle * 32) / (2 * math.PI))
}


draw_skater_sprite :: proc(state: ^State, skater: ^Skater, offset: rl.Vector3) {
	sprite_idx: rl.Vector2
	sprite_idx.x = skater_rot_to_sprite_idx(skater)
	sprite_sheet: Sprite_Sheet
	switch skater.state {
	case .Crouched:
		frame_count := f32(state.config.sprite.crouch_frame_count)
		sprite_sheet = .Duck
		sprite_idx.y = math.round(skater.timer[.Crouched] * frame_count)
		sprite_idx.y = min(sprite_idx.y, frame_count - 1)
		if skater.trick_buffer_len >= 0 && skater.trick_buffer[0] < .Trick_ES {
			sprite_idx.y += frame_count
		}
	case .Airborne:
		frame_count := f32(state.config.sprite.airborne_frame_count)
		sprite_sheet = .Air
		height := skater.jump_height
		if skater.jump_height > 0 {
			mid := (frame_count - 1) / 2
			sprite_idx.y = math.round(mid * -skater.vel.z / skater.jump_height + mid)
			sprite_idx.y = min(sprite_idx.y, frame_count - 1)
		} else {
			sprite_idx.y = frame_count - 2
		}
		if skater.trick_buffer_len >= 0 && skater.trick_buffer[0] < .Trick_ES {
			sprite_idx.y += frame_count
		}
	case .Idle:
		sprite_sheet = .Ride
	case .Landing:
		frame_count := f32(state.config.sprite.landing_frame_count)
		sprite_sheet = .Land
		x := skater.timer[.Airborne] * state.config.landing.landing_duration_scale
		sprite_idx.y = math.round(-frame_count * skater.timer[.Landing] / x + frame_count)
		sprite_idx.y = min(sprite_idx.y, frame_count - 1)
	}

	frame_size := state.config.sprite.frame_size
	sprite_pos := sprite_idx * frame_size

	target_pos := project(offset, state) - frame_size / 2
	rl.DrawTexturePro(
		state.sprite_sheets[sprite_sheet],
		{sprite_pos.x, sprite_pos.y, frame_size, frame_size},
		{target_pos.x, target_pos.y, frame_size, frame_size},
		{0, 0},
		0,
		rl.WHITE,
	)
}

draw_surface_wireframe :: proc(state: ^State, surface: ^Surface, offset: rl.Vector3) {
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
