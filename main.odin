package main

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

	state: State

	for !rl.WindowShouldClose() {
		screen := rl.Vector2{f32(rl.GetScreenWidth()), f32(rl.GetScreenHeight())}

		state.cell_size = f32(32)

		num_cols := math.floor(screen.x / state.cell_size)
		num_rows := math.floor(screen.y / state.cell_size)

		new_dir: rl.Vector3
		if rl.IsKeyDown(.T) do new_dir = rl.Vector3{1, 0, 0}
		if rl.IsKeyDown(.R) do new_dir = rl.Vector3{-1, 0, 0}
		if rl.IsKeyDown(.S) do new_dir = rl.Vector3{0, 1, 0}
		if rl.IsKeyDown(.F) do new_dir = rl.Vector3{0, -1, 0}
		new_dir = rl.Vector3Normalize(new_dir)

		if new_dir != state.dir {
			state.dir = new_dir
			state.pos += state.dir
			state.pos = rl.Vector3Clamp(
				state.pos,
				rl.Vector3(0),
				rl.Vector3{num_cols - 1, num_rows - 1, 0},
			)
		}

		if rl.IsKeyPressed(.SPACE) {
			state.drawing_mode = state.drawing_mode == .dimetric ? .top_down : .dimetric
		}

		center := rl.Vector2{math.floor(num_cols / 2), math.floor(num_rows / 2)}
		state.origin = center - state.pos.xy


		rl.BeginDrawing()

		rl.ClearBackground(rl.WHITE)

		for i: f32 = 0; i <= num_cols; i += 1 {
			rl.DrawLineEx(
				project(rl.Vector3{i, 0, 0}, &state),
				project(rl.Vector3{i, num_rows, 0}, &state),
				1.1,
				rl.Fade(rl.DARKGRAY, 0.5),
			)
		}
		for i: f32 = 0; i <= num_rows; i += 1 {
			rl.DrawLineEx(
				project(rl.Vector3{0, i, 0}, &state),
				project(rl.Vector3{num_cols, i, 0}, &state),
				1.1,
				rl.Fade(rl.DARKGRAY, 0.5),
			)
		}

		cube := Shape {
			vertices = {
				{0, 0, 0},
				{0, 1, 0},
				{1, 1, 0},
				{1, 0, 0},
				{0, 0, 1},
				{0, 1, 1},
				{1, 1, 1},
				{1, 0, 1},
			},
			faces    = {{0, 1, 2, 3}, {4, 5, 6, 7}, {0, 4, 7, 3}, {1, 5, 6, 2}},
		}


		for face in cube.faces {
			for i := 0; i < len(face); i += 1 {
				start_idx := face[i]
				end_idx := face[(i + 1) % len(face)]
				color := rl.ORANGE
				rl.DrawLineEx(
					project(cube.vertices[start_idx] + state.pos, &state),
					project(cube.vertices[end_idx] + state.pos, &state),
					2,
					color,
				)
			}
		}

		rl.DrawLineEx(
			project(state.pos + rl.Vector3(0.5), &state),
			project(state.pos + rl.Vector3(0.5) + state.dir, &state),
			4,
			rl.PINK,
		)

		rl.EndDrawing()
	}
}

project :: proc(point: rl.Vector3, state: ^State) -> rl.Vector2 {
	if state.drawing_mode == .top_down {
		return (point.xy + state.origin) * state.cell_size
	}
	return PRO_MATRIX * (point + rl.Vector3{state.origin.x, state.origin.y, 0}) * state.cell_size
}

Axis :: struct {
	dir:   rl.Vector3,
	color: rl.Color,
}

AXES :: [3]Axis {
	{dir = {1, 0, 0}, color = rl.RED},
	{dir = {0, 1, 0}, color = rl.GREEN},
	{dir = {0, 0, 1}, color = rl.BLUE},
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
	drawing_mode: Drawing_Mode,
	cell_size:    f32,
	origin:       rl.Vector2,
}
