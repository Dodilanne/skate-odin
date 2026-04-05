package main

import "core:fmt"
import rl "vendor:raylib"

main :: proc() {
	fmt.println("Hello world")

	rl.InitWindow(500, 500, "skate")
	rl.SetTargetFPS(60)

	for !rl.WindowShouldClose() {
		rl.ClearBackground(rl.GRAY)
		rl.BeginDrawing()
		rl.DrawCircleV({250, 250}, 50, rl.GREEN)
		rl.EndDrawing()
	}
}
