package main

import "core:fmt"
import "core:log"
import "core:math"
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

	state := State {
		dir  = rl.Vector3{1, 0, 0},
		norm = rl.Vector3{0, 0, 1},
	}

	full_rot: f32 = 0

	for !rl.WindowShouldClose() {
		screen := rl.Vector2{f32(rl.GetScreenWidth()), f32(rl.GetScreenHeight())}

		state.cell_size = f32(32)
		state.offset = screen / 2

		num_cols := math.floor(screen.x / state.cell_size)
		num_rows := math.floor(screen.y / state.cell_size)

		theta := rl.GetFrameTime()
		full_rot += theta
		rot_matrix := matrix[3, 3]f32{
			math.cos_f32(theta), -math.sin_f32(theta), 0,
			math.sin_f32(theta), math.cos_f32(theta), 0,
			0, 0, 1,
		}

		state.dir = rot_matrix * state.dir
		state.dir = rl.Vector3Normalize(state.dir)

		steer: rl.Vector3
		if rl.IsKeyDown(.R) do steer = +rl.Vector3CrossProduct(state.dir, state.norm)
		if rl.IsKeyDown(.T) do steer = -rl.Vector3CrossProduct(state.dir, state.norm)

		if rl.IsKeyPressed(.D) {
			state.drawing_mode = state.drawing_mode == .dimetric ? .top_down : .dimetric
		}

		rl.BeginDrawing()

		rl.ClearBackground(rl.WHITE)

		for i: f32 = 0; i <= num_cols; i += 1 {
			rl.DrawLineEx(
				project(rl.Vector3{i, 0, 0} - state.pos - rl.Vector3(0.5), &state),
				project(rl.Vector3{i, num_rows, 0} - state.pos - rl.Vector3(0.5), &state),
				1.1,
				rl.Fade(rl.DARKGRAY, 0.5),
			)
		}
		for i: f32 = 0; i <= num_rows; i += 1 {
			rl.DrawLineEx(
				project(rl.Vector3{0, i, 0} - state.pos - rl.Vector3(0.5), &state),
				project(rl.Vector3{num_cols, i, 0} - state.pos - rl.Vector3(0.5), &state),
				1.1,
				rl.Fade(rl.DARKGRAY, 0.5),
			)
		}

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

		full_rot_matrix := matrix[3, 3]f32{
			math.cos_f32(full_rot), -math.sin_f32(full_rot), 0,
			math.sin_f32(full_rot), math.cos_f32(full_rot), 0,
			0, 0, 1,
		}

		for face, face_idx in cube.faces {
			for i := 0; i < len(face); i += 1 {
				start_idx := face[i]
				end_idx := face[(i + 1) % len(face)]
				color := rl.ORANGE

				rl.DrawLineEx(
					project(full_rot_matrix * cube.vertices[start_idx], &state),
					project(full_rot_matrix * cube.vertices[end_idx], &state),
					2,
					color,
				)
			}
		}

		rl.DrawLineEx(project(rl.Vector3(0), &state), project(steer, &state), 4, rl.PINK)
		rl.DrawLineEx(project(rl.Vector3(0), &state), project(state.norm, &state), 4, rl.GREEN)
		rl.DrawLineEx(project(rl.Vector3(0), &state), project(state.dir, &state), 4, rl.BLUE)

		rl.EndDrawing()
	}
}

project :: proc(point: rl.Vector3, state: ^State) -> rl.Vector2 {
	if state.drawing_mode == .top_down {
		return point.xy * state.cell_size + state.offset
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
	dimetric,
	top_down,
}

State :: struct {
	pos:          rl.Vector3,
	dir:          rl.Vector3,
	vel:          rl.Vector3,
	norm:         rl.Vector3,
	drawing_mode: Drawing_Mode,
	cell_size:    f32,
	offset:       rl.Vector2,
}
