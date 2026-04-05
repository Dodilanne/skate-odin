package main

import "core:log"
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

	for !rl.WindowShouldClose() {
		rl.ClearBackground(rl.GRAY)
		rl.BeginDrawing()
		rl.DrawCircleV({250, 250}, 50, rl.GREEN)
		rl.EndDrawing()
	}
}
