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

	player_radius: f32 = 0.5
	initial_player := Player {
		pos        = rl.Vector3(player_radius * 2),
		dir        = linalg.normalize(rl.Vector3({1, 1, 0})),
		norm       = {0, 0, 1},
		steer_rate = 0.2,
		mass       = 1,
		max_speed  = 8,
		radius     = player_radius,
	}

	state := State {
		color_mode   = .dark,
		drawing_mode = .side,
		player       = initial_player,
		surfaces     = {
			{name = "floor", origin = {0, 0, 0}, width = 15, height = 20, norm = {0, 0, 1}},
			{name = "back wall", origin = {0, 0, 0}, width = 20, height = 10, norm = {1, 0, 0}},
			{name = "right wall", origin = {0, 0, 0}, width = 15, height = 10, norm = {0, 1, 0}},
			{
				name = "left wall",
				origin = {0, 20, 0},
				width = 15,
				height = 10,
				norm = linalg.normalize(rl.Vector3{0.5, -1, 0}),
			},
			{name = "ceiling", origin = {0, 0, 10}, width = 15, height = 20, norm = {0, 0, -1}},
			{
				name = "slope",
				origin = {15, 0, 0},
				width = 20,
				height = 10,
				norm = linalg.normalize(rl.Vector3{-0.2, 0, 0.8}),
			},
		},
	}

	for !rl.WindowShouldClose() {
		screen := rl.Vector2{f32(rl.GetScreenWidth()), f32(rl.GetScreenHeight())}

		state.cell_size = f32(32)
		state.offset = screen / 2

		if rl.IsKeyPressed(.D) {
			state.drawing_mode = Drawing_Mode((int(state.drawing_mode) + 1) % len(Drawing_Mode))
		}

		if rl.IsKeyPressed(.C) {
			state.color_mode = Color_Mode((int(state.color_mode) + 1) % len(Color_Mode))
		}

		dt := rl.GetFrameTime()

		player_angle := linalg.atan2(state.player.dir.y, state.player.dir.x)

		steer_dir: f32 = 0
		if rl.IsKeyDown(.R) do steer_dir = -1
		if rl.IsKeyDown(.T) do steer_dir = +1

		if steer_dir != 0 {
			speed := linalg.length(state.player.vel) * state.player.steer_rate
			if speed == 0 do speed = 2
			angle_change := steer_dir * dt * speed
			player_angle += angle_change
			state.player.dir = rl.Vector3RotateByAxisAngle(
				rl.Vector3{1, 0, 0},
				rl.Vector3{0, 0, 1},
				player_angle,
			)
			state.player.dir = linalg.normalize(state.player.dir)
			state.player.vel = rl.Vector3RotateByAxisAngle(
				state.player.vel,
				rl.Vector3{0, 0, 1},
				angle_change,
			)
		}

		if rl.IsKeyPressed(.SPACE) {
			state.player.vel += state.player.dir
		}

		state.player.vel -= rl.Vector3{0, 0, state.player.mass * 10 * dt}

		if math.abs(linalg.length(state.player.vel.xy)) > 0.1 {
			friction_coeff: f32 = 0.5
			if rl.IsKeyDown(.ENTER) do friction_coeff *= 10
			state.player.vel = state.player.vel - state.player.dir * friction_coeff * dt
		} else {
			state.player.vel.xy = {0, 0}
		}

		state.player.vel.xy = rl.Vector2ClampValue(state.player.vel.xy, 0, state.player.max_speed)

		state.player.pos += state.player.vel * dt

		for surface in state.surfaces {
			dist := linalg.dot(surface.norm, state.player.pos - surface.origin)
			if dist > state.player.radius do continue
			vel_proj := linalg.dot(state.player.vel, -surface.norm)
			state.player.pos += (state.player.radius - dist) * surface.norm
			state.player.vel -= vel_proj * -surface.norm
			if linalg.length(state.player.vel) != 0 {
				state.player.dir = linalg.normalize(state.player.vel)
			}
		}


		if state.player.pos.z < -10 || rl.IsKeyPressed(.ZERO) {
			state.player = initial_player
		}

		rl.BeginDrawing()

		bg: rl.Color
		if state.color_mode == .light {
			bg = rl.WHITE
		} else {
			bg = rl.DARKGRAY
		}
		rl.ClearBackground(bg)

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

		base_points: [100]rl.Vector3
		for i in 0 ..< len(base_points) {
			rad := math.PI * 2 / len(base_points) * f32(i)
			rad += player_angle
			rot := matrix[3, 3]f32{
				math.cos(rad), -math.sin(rad), 0,
				math.sin(rad), math.cos(rad), 0,
				0, 0, 1,
			}
			base_points[i] =
				rot * rl.Vector3{1, 0, 0} * state.player.radius -
				rl.Vector3{0, 0, state.player.radius}
		}
		for i := 0; i < len(base_points); i += 1 {
			start := base_points[i]
			end := base_points[(i + 1) % len(base_points)]
			rl.DrawLineEx(project(start, &state), project(end, &state), 2, rl.ORANGE)
			rl.DrawLineEx(
				project(start + rl.Vector3{0, 0, state.player.radius * 2}, &state),
				project(end + rl.Vector3{0, 0, state.player.radius * 2}, &state),
				2,
				rl.ORANGE,
			)
			if i % (len(base_points) / 12) == 0 {
				rl.DrawLineEx(
					project(start, &state),
					project(start + rl.Vector3{0, 0, state.player.radius * 2}, &state),
					2,
					rl.ORANGE,
				)
			}
		}

		rl.DrawCircleV(project(-state.player.pos, &state), 2, rl.Fade(rl.LIGHTGRAY, 0.5))
		rl.DrawCircleV(project(rl.Vector3(0), &state), 4, rl.Fade(rl.LIGHTGRAY, 0.5))

		if linalg.length(state.player.vel) > 0 {
			rl.DrawLineEx(
				project(rl.Vector3(0), &state),
				project(state.player.vel, &state),
				4,
				rl.PINK,
			)
		}

		rl.DrawLineEx(
			project(rl.Vector3(0), &state),
			project(state.player.dir, &state),
			4,
			rl.BLUE,
		)

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
	dir:        rl.Vector3,
	norm:       rl.Vector3,
	pos:        rl.Vector3,
	vel:        rl.Vector3,
	forces:     rl.Vector3,
	mass:       f32,
	steer_rate: f32,
	max_speed:  f32,
	radius:     f32,
	on_surface: Maybe(Surface),
}

Surface :: struct {
	name:   string,
	origin: rl.Vector3,
	width:  f32,
	height: f32,
	norm:   rl.Vector3,
}

Color_Mode :: enum {
	dark,
	light,
}

State :: struct {
	player:       Player,
	surfaces:     [dynamic; 10]Surface,
	drawing_mode: Drawing_Mode,
	color_mode:   Color_Mode,
	cell_size:    f32,
	offset:       rl.Vector2,
}

largest_abs_component :: proc(v: rl.Vector3) -> rl.Vector3 {
	abs := linalg.abs(v)
	if abs.x >= abs.y && abs.x >= abs.z do return {1, 0, 0}
	if abs.y >= abs.z do return {0, 1, 0}
	return {0, 0, 1}
}
