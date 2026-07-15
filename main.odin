package main

import "core:log"
import "core:mem"
import "game"
import rl "vendor:raylib"

main :: proc() {
	context.logger = log.create_console_logger()

	when ODIN_DEBUG {
		track: mem.Tracking_Allocator
		mem.tracking_allocator_init(&track, context.allocator)
		context.allocator = mem.tracking_allocator(&track)
		defer for _, v in track.allocation_map do log.warnf("%v Leaked %v bytes.\n", v.location, v.size)
	}

	rl.SetTargetFPS(60)
	rl.SetTraceLogLevel(.WARNING)
	rl.InitWindow(32 * 40, 32 * 23, "skate")
	rl.SetWindowState({.WINDOW_RESIZABLE})

	state := game.new_state()

	for !rl.WindowShouldClose() {
		game.update(&state)
		game.render(&state)
	}
}
