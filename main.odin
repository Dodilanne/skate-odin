#+vet !unused-imports

package main

import "core:log"
import "core:mem"
import "game"
import "game/input"
import rl "vendor:raylib"

UPDATE_FREQ :: 60
FIXED_DT :: 1. / UPDATE_FREQ

main :: proc() {
	context.logger = log.create_console_logger()

	when ODIN_DEBUG {
		track: mem.Tracking_Allocator
		mem.tracking_allocator_init(&track, context.allocator)
		context.allocator = mem.tracking_allocator(&track)
		defer for _, v in track.allocation_map {
			log.warnf("%v Leaked %v bytes.\n", v.location, v.size)
		}
	}

	rl.SetTraceLogLevel(.WARNING)
	rl.InitWindow(32 * 40, 32 * 23, "skate")
	rl.SetWindowState({.WINDOW_RESIZABLE})

	input_state: input.State
	game_state: game.State
	game.init(&game_state)

	accumulator: f32 = 0

	for !rl.WindowShouldClose() {
		frame_time := rl.GetFrameTime()
		accumulator += frame_time

		frame_input_state: input.State
		input.gather(&frame_input_state)
		input.add(&input_state, frame_input_state)

		update_did_run := accumulator >= FIXED_DT
		defer if update_did_run {
			input_state = {}
		}

		for ; accumulator >= FIXED_DT; accumulator -= FIXED_DT {
			game.update(&game_state, input_state, FIXED_DT)
			// Pressed and released should only be consumed by one game update
			input.clear_flags(&input_state, {.Pressed, .Released})
		}


		rl.BeginDrawing()
		defer rl.EndDrawing()

		game.render(&game_state)

		free_all(context.temp_allocator)
	}
}
