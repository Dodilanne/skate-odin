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

	Axis :: struct {
		dir:   rl.Vector3,
		color: rl.Color,
	}

	axes: [3]Axis = {
		{dir = {1, 0, 0}, color = rl.RED},
		{dir = {0, 1, 0}, color = rl.GREEN},
		{dir = {0, 0, 1}, color = rl.BLUE},
	}


	for !rl.WindowShouldClose() {
		screen := rl.Vector2{f32(rl.GetScreenWidth()), f32(rl.GetScreenHeight())}
		grid_size := f32(math.min(screen.x, screen.y) / 12)
		origin := screen / 2

		rl.BeginDrawing()

		rl.ClearBackground(rl.WHITE)

		// Grid
		num_cols := math.floor(screen.x / grid_size)
		for i: f32 = 0; i <= num_cols; i += 1 {
			rl.DrawLineEx(
				rl.Vector2{i * grid_size - grid_size / 2, 0},
				rl.Vector2{i * grid_size - grid_size / 2, screen.y},
				1,
				rl.LIGHTGRAY,
			)
			if i > 0 && i < num_cols {
				rl.DrawLineEx(
					rl.Vector2{i * grid_size, 0},
					rl.Vector2{i * grid_size, screen.y},
					1.1,
					rl.DARKGRAY,
				)
			}
		}
		num_rows := math.floor(screen.y / grid_size)
		for i: f32 = 0; i <= num_rows; i += 1 {
			rl.DrawLineEx(
				rl.Vector2{0, i * grid_size - grid_size / 2},
				rl.Vector2{screen.x, i * grid_size - grid_size / 2},
				1,
				rl.LIGHTGRAY,
			)
			if i > 0 && i < num_rows {
				rl.DrawLineEx(
					rl.Vector2{0, i * grid_size},
					rl.Vector2{screen.x, i * grid_size},
					1.1,
					rl.DARKGRAY,
				)
			}
		}


		// Origin
		rl.DrawCircleV(origin, 4, rl.ORANGE)


		// Axes
		for axis in axes {
			start := rl.Vector2(0)
			end := axis.dir.xy

			faded_color := axis.color
			faded_color.a = 80
			rl.DrawLineEx(start + origin, end * grid_size + origin, 4, faded_color)

			m := matrix[2, 3]f32{
				1, -1, 0,
				0.5, 0.5, -1,
			}
			end = m * axis.dir

			rl.DrawLineEx(start + origin, end * grid_size + origin, 4, axis.color)
		}

		rl.EndDrawing()
	}
}
