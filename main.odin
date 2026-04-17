package main

import "core:log"
import "core:math"
import "core:math/linalg"
import "core:mem"
import rl "vendor:raylib"

main :: proc() {
	context.logger = log.create_console_logger()

	when ODIN_DEBUG {
		track: mem.Tracking_Allocator
		mem.tracking_allocator_init(&track, context.allocator)
		context.allocator = mem.tracking_allocator(&track)
		defer for _, v in track.allocation_map do log.warnf("%v Leaked %v bytes.\n", v.location, v.size)
	}

	rl.SetTraceLogLevel(.WARNING)
	rl.SetTargetFPS(60)
	rl.InitWindow(32 * 40, 32 * 23, "skate")
	rl.SetWindowState({.WINDOW_RESIZABLE})


	initial_player := Player {
		grounded   = true,
		pos        = {0, 0, 0},
		dir        = {1, 0, 0},
		norm       = {0, 0, 1},
		steer_rate = 0.2,
		mass       = 1,
		max_speed  = 8,
	}


	state := State {
		drawing_mode = .dimetric,
		player       = initial_player,
		surfaces     = {
			{origin = {0, 0, 0}, width = 20, height = 20, norm = {0, 0, 1}},
			{origin = {0, 0, 0}, width = 20, height = 10, norm = {1, 0, 0}},
			{origin = {20, 0, 0}, width = 20, height = 5, norm = {-0.2, 0, 0.8}},
		},
	}
	for !rl.WindowShouldClose() {
		screen := rl.Vector2{f32(rl.GetScreenWidth()), f32(rl.GetScreenHeight())}

		state.cell_size = f32(32)
		state.offset = screen / 2

		if rl.IsKeyPressed(.D) {
			state.drawing_mode = Drawing_Mode((int(state.drawing_mode) + 1) % len(Drawing_Mode))
		}

		dt := rl.GetFrameTime()

		friction_coeff: f32 = 0.5

		if state.player.grounded {
			steer_dir: f32 = 0
			if rl.IsKeyDown(.R) do steer_dir = -1
			if rl.IsKeyDown(.T) do steer_dir = +1
			if steer_dir != 0 {
				angle_change :=
					steer_dir * dt * rl.Vector3Length(state.player.vel) * state.player.steer_rate
				state.player.angle = state.player.angle + angle_change
				state.player.dir = rl.Vector3RotateByAxisAngle(
					rl.Vector3{1, 0, 0},
					rl.Vector3{0, 0, 1},
					state.player.angle,
				)
				state.player.dir = rl.Vector3Normalize(state.player.dir)
				state.player.vel = rl.Vector3RotateByAxisAngle(
					state.player.vel,
					rl.Vector3{0, 0, 1},
					angle_change,
				)
			}

			if rl.IsKeyPressed(.SPACE) {
				state.player.vel += state.player.dir
			}

			if rl.IsKeyDown(.ENTER) {
				friction_coeff *= 10
			}

			state.player.vel.z = 0
		} else {
			state.player.vel -= rl.Vector3{0, 0, state.player.mass * 10 * dt}
		}

		if rl.Vector2Length(state.player.vel.xy) != 0 {
			new_vel := state.player.vel - state.player.dir * friction_coeff * dt
			diff := math.abs(
				rl.Vector3Length(
					rl.Vector3Normalize(new_vel) - rl.Vector3Normalize(state.player.vel),
				),
			)
			if diff < 0.1 {
				state.player.vel = new_vel
				state.player.vel.xy = rl.Vector2ClampValue(
					state.player.vel.xy,
					0,
					state.player.max_speed,
				)
			} else {
				state.player.vel = rl.Vector3(0)
			}
		}

		state.player.pos += state.player.vel * dt

		if state.player.pos.z < -10 {
			state.player = initial_player
		}

		// state.player.grounded = false
		// for surface, i in state.surfaces {
		// 	diff := state.player.pos - surface.origin
		// 	if diff.z < -0.5 || diff.z > 0 {
		// 		continue
		// 	}
		// 	if state.player.pos.x < surface.origin.x - 1 ||
		// 	   state.player.pos.x > surface.origin.x + surface.size.x {
		// 		continue
		// 	}
		// 	if state.player.pos.y < surface.origin.y - 1 ||
		// 	   state.player.pos.y > surface.origin.y + surface.size.y {
		// 		continue
		// 	}
		// 	state.player.grounded = true
		// 	state.player.pos.z = surface.origin.z
		// 	break
		// }

		rl.BeginDrawing()

		rl.ClearBackground(rl.DARKGRAY)

		for &surface in state.surfaces {
			surface.norm = linalg.normalize(surface.norm)

			ref := rl.Vector3{0, 0, 1} // arbitrary
			if surface.norm == ref { 	// cross product will give 0, need to use another ref vector
				ref = rl.Vector3{0, 1, 0}
			}

			right := linalg.normalize(linalg.cross(surface.norm, ref))
			up := linalg.normalize(linalg.cross(surface.norm, right))

			if linalg.dot(right, largest_abs_component(right)) < 0 do right *= -1
			if linalg.dot(up, largest_abs_component(up)) < 0 do up *= -1

			for col in 0 ..= surface.width {
				start := surface.origin + right * col - state.player.pos
				end := start + up * surface.height
				rl.DrawLineEx(
					project(start, &state),
					project(end, &state),
					1.1,
					rl.Fade(rl.LIGHTGRAY, 0.5),
				)
			}
			for row in 0 ..= surface.height {
				start := surface.origin + up * row - state.player.pos
				end := start + right * surface.width
				rl.DrawLineEx(
					project(start, &state),
					project(end, &state),
					1.1,
					rl.Fade(rl.LIGHTGRAY, 0.5),
				)
			}
		}

		// for surface in state.surfaces {
		// 	for i: f32 = 0; i <= surface.size.x; i += 1 {
		// 		rl.DrawLineEx(
		// 			project(
		// 				surface.origin + rl.Vector3{i, 0, 0} - state.player.pos - rl.Vector3(0.5),
		// 				&state,
		// 			),
		// 			project(
		// 				surface.origin +
		// 				rl.Vector3{i, surface.size.y, 0} -
		// 				state.player.pos -
		// 				rl.Vector3(0.5),
		// 				&state,
		// 			),
		// 			1.1,
		// 			rl.Fade(rl.LIGHTGRAY, 0.5),
		// 		)
		// 	}
		// 	for i: f32 = 0; i <= surface.size.y; i += 1 {
		// 		rl.DrawLineEx(
		// 			project(
		// 				surface.origin + rl.Vector3{0, i, 0} - state.player.pos - rl.Vector3(0.5),
		// 				&state,
		// 			),
		// 			project(
		// 				surface.origin +
		// 				rl.Vector3{surface.size.x, i, 0} -
		// 				state.player.pos -
		// 				rl.Vector3(0.5),
		// 				&state,
		// 			),
		// 			1.1,
		// 			rl.Fade(rl.LIGHTGRAY, 0.5),
		// 		)
		// 	}
		// }

		cube := Shape {
			vertices = {
				{-0.5, -0.5, -0.5},
				{-0.5, 0.5, -0.5},
				{0.5, 0.5, -0.5},
				{0.5, -0.5, -0.5},
				{-0.5, -0.5, 0.5},
				{-0.5, 0.5, 0.5},
				{0.5, 0.5, 0.5},
				{0.5, -0.5, 0.5},
			},
			faces    = {{0, 1, 2, 3}, {4, 5, 6, 7}, {0, 4, 7, 3}, {1, 5, 6, 2}},
		}

		angle := state.player.angle
		rot_matrix := matrix[3, 3]f32{
			math.cos(angle), -math.sin(angle), 0,
			math.sin(angle), math.cos(angle), 0,
			0, 0, 1,
		}

		for face, face_idx in cube.faces {
			for i := 0; i < len(face); i += 1 {
				start_idx := face[i]
				end_idx := face[(i + 1) % len(face)]
				color := rl.ORANGE

				rl.DrawLineEx(
					project(rot_matrix * cube.vertices[start_idx], &state),
					project(rot_matrix * cube.vertices[end_idx], &state),
					2,
					color,
				)
			}
		}

		if rl.Vector3Length(state.player.vel) > 0 {
			rl.DrawLineEx(
				project(rl.Vector3(0), &state),
				project(state.player.vel, &state),
				4,
				rl.PINK,
			)
		} else {
			rl.DrawLineEx(
				project(rl.Vector3(0), &state),
				project(state.player.dir, &state),
				4,
				rl.BLUE,
			)
		}

		rl.DrawFPS(0, 0)

		rl.EndDrawing()
	}
}

project :: proc(point: rl.Vector3, state: ^State) -> rl.Vector2 {
	if state.drawing_mode == .top_down {
		return point.xy * state.cell_size + state.offset
	}
	if state.drawing_mode == .side {
		return rl.Vector2{point.x, -point.z} * state.cell_size + state.offset
	}
	return PRO_MATRIX * point * state.cell_size + state.offset
}

PRO_MATRIX :: matrix[2, 3]f32{
	1, -1, 0,
	0.5, 0.5, -1,
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
	angle:      f32,
	dir:        rl.Vector3,
	norm:       rl.Vector3,
	pos:        rl.Vector3,
	vel:        rl.Vector3,
	forces:     rl.Vector3,
	mass:       f32,
	steer_rate: f32,
	grounded:   bool,
	max_speed:  f32,
}

Surface :: struct {
	origin: rl.Vector3,
	width:  f32,
	height: f32,
	norm:   rl.Vector3,
}

State :: struct {
	player:       Player,
	surfaces:     [dynamic; 10]Surface,
	drawing_mode: Drawing_Mode,
	cell_size:    f32,
	offset:       rl.Vector2,
}

largest_abs_component :: proc(v: rl.Vector3) -> rl.Vector3 {
	abs := linalg.abs(v)
	if abs.x >= abs.y && abs.x >= abs.z do return {1, 0, 0}
	if abs.y >= abs.z do return {0, 1, 0}
	return {0, 0, 1}
}
