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
	rl.InitWindow(500, 500, "skate")
	rl.SetWindowState({.WINDOW_RESIZABLE})

	state: State

	for !rl.WindowShouldClose() {
		screen := rl.Vector2{f32(rl.GetScreenWidth()), f32(rl.GetScreenHeight())}
		grid_size := f32(math.min(screen.x, screen.y) / 12)
		origin := screen / 2

		state.dir = rl.Vector3(0)
		if rl.IsKeyDown(.T) do state.dir += rl.Vector3{1, 0, 0}
		if rl.IsKeyDown(.R) do state.dir += rl.Vector3{-1, 0, 0}
		if rl.IsKeyDown(.S) do state.dir += rl.Vector3{0, 1, 0}
		if rl.IsKeyDown(.F) do state.dir += rl.Vector3{0, -1, 0}
		state.dir = rl.Vector3Normalize(state.dir)

		rl.BeginDrawing()

		rl.ClearBackground(rl.WHITE)

		// Grid
		for i: f32 = 0; i <= math.floor(screen.x / grid_size); i += 1 {
			if i > 0 {
				rl.DrawLineEx(
					PRO_MATRIX * rl.Vector3{i * grid_size - grid_size / 2, 0, 0} + origin,
					PRO_MATRIX * rl.Vector3{i * grid_size - grid_size / 2, screen.y, 0} + origin,
					1,
					rl.Fade(rl.LIGHTGRAY, 0.5),
				)
			}
			rl.DrawLineEx(
				PRO_MATRIX * rl.Vector3{i * grid_size, 0, 0} + origin,
				PRO_MATRIX * rl.Vector3{i * grid_size, screen.y, 0} + origin,
				1.1,
				rl.Fade(rl.DARKGRAY, 0.5),
			)
		}
		for i: f32 = 0; i <= math.floor(screen.y / grid_size); i += 1 {
			if i > 0 {
				rl.DrawLineEx(
					PRO_MATRIX * rl.Vector3{0, i * grid_size - grid_size / 2, 0} + origin,
					PRO_MATRIX * rl.Vector3{screen.x, i * grid_size - grid_size / 2, 0} + origin,
					1,
					rl.Fade(rl.LIGHTGRAY, 0.5),
				)
			}
			rl.DrawLineEx(
				PRO_MATRIX * rl.Vector3{0, i * grid_size, 0} + origin,
				PRO_MATRIX * rl.Vector3{screen.x, i * grid_size, 0} + origin,
				1.1,
				rl.Fade(rl.DARKGRAY, 0.5),
			)
		}

		cube := Shape {
			vertices = {
				{-0.5, 0.5, 0.5},
				{0.5, 0.5, 0.5},
				{0.5, -0.5, 0.5},
				{-0.5, -0.5, 0.5},
				{-0.5, 0.5, -0.5},
				{0.5, 0.5, -0.5},
				{0.5, -0.5, -0.5},
				{-0.5, -0.5, -0.5},
			},
			faces    = {{0, 1, 2, 3}, {4, 5, 6, 7}, {0, 4, 7, 3}, {1, 5, 6, 2}},
		}


		for face in cube.faces {
			for i := 0; i < len(face); i += 1 {
				start_idx := face[i]
				end_idx := face[(i + 1) % len(face)]
				color := rl.ORANGE
				rl.DrawLineEx(
					project(cube.vertices[start_idx], grid_size, origin),
					project(cube.vertices[end_idx], grid_size, origin),
					2,
					color,
				)
			}
		}


		rl.DrawLineEx(
			project(rl.Vector3(0), grid_size, origin),
			project(state.dir, grid_size, origin),
			4,
			rl.PINK,
		)


		rl.EndDrawing()
	}
}

project :: proc(point: rl.Vector3, grid_size: f32, origin: rl.Vector2) -> rl.Vector2 {
	return PRO_MATRIX * point * grid_size + origin
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

State :: struct {
	dir: rl.Vector3,
}
