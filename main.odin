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
		drawing_mode = .dimetric,
		player       = initial_player,
		surfaces     = {
			{name = "floor", o = {0, 0, 0}, w = 15, h = 20, n = {0, 0, 1}},
			// {name = "back wall", origin = {0, 0, 0}, width = 20, height = 10, n = {1, 0, 0}},
			{name = "right wall", o = {0, 0, 0}, w = 15, h = 10, n = {0, 1, 0}},
			{name = "left wall", o = {0, 20, 0}, w = 15, h = 10, n = {0.5, -1, 0}},
			{name = "ceiling", o = {0, 0, 10}, w = 15, h = 20, n = {0, 0, -1}},
			{name = "slope", o = {15, 0, 0}, w = 20, h = 10, n = {-0.2, 0, 0.8}},
		},
	}


	for &surface in state.surfaces {
		surface.n = linalg.normalize(surface.n)

		a := rl.Vector3{0, 0, 1} // arbitrary
		if surface.n == a do a = rl.Vector3{0, 1, 0} // cross product will give 0, need to use another ref vector

		u := linalg.normalize(linalg.cross(surface.n, a))
		if linalg.dot(u, largest_abs_component(u)) < 0 do u *= -1
		surface.u = u

		v := linalg.normalize(linalg.cross(surface.n, u))
		if linalg.dot(v, largest_abs_component(v)) < 0 do v *= -1
		surface.v = v
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

		clear(&state.player.collisions)

		for &surface in state.surfaces {
			dist := linalg.dot(surface.n, state.player.pos - surface.o)
			if dist > state.player.radius do continue
			append(&state.player.collisions, &surface)
			vel_proj := linalg.dot(state.player.vel, -surface.n)
			state.player.pos += (state.player.radius - dist) * surface.n
			state.player.vel -= vel_proj * -surface.n
			if linalg.length(state.player.vel) != 0 do state.player.dir = linalg.normalize(state.player.vel)
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
			for col in 0 ..= surface.w {
				start := surface.o + surface.u * col - state.player.pos
				end := start + surface.v * surface.h
				rl.DrawLineEx(
					project(start, &state),
					project(end, &state),
					1.1,
					rl.Fade(rl.LIGHTGRAY, 0.5),
				)
			}
			for row in 0 ..= surface.h {
				start := surface.o + surface.v * row - state.player.pos
				end := start + surface.u * surface.w
				rl.DrawLineEx(
					project(start, &state),
					project(end, &state),
					1.1,
					rl.Fade(rl.LIGHTGRAY, 0.5),
				)
			}
		}

		for &surface in state.player.collisions {
			if surface.n.z == 1 do continue

			rl.DrawLineEx(
				project(surface.o - state.player.pos, &state),
				project(surface.o - state.player.pos + surface.n, &state),
				2,
				rl.GREEN,
			)
			rl.DrawLineEx(
				project(surface.o - state.player.pos, &state),
				project(surface.o - state.player.pos + surface.u, &state),
				2,
				rl.MAGENTA,
			)
			rl.DrawLineEx(
				project(surface.o - state.player.pos, &state),
				project(surface.o - state.player.pos + surface.v, &state),
				2,
				rl.YELLOW,
			)

		}

		num_circles := 6
		base_points: [100]rl.Vector3
		points_per_circle := len(base_points) / num_circles
		for c in 0 ..< num_circles {
			for p in 0 ..< points_per_circle {
				y_angle := math.PI * 2 / f32(points_per_circle) * f32(p)
				y_rot := matrix[3, 3]f32{
					math.cos(y_angle), 0, math.sin(y_angle),
					0, 1, 0,
					-math.sin(y_angle), 0, math.cos(y_angle),
				}

				z_angle := math.PI / f32(num_circles) * f32(c)
				z_angle += player_angle
				z_rot := matrix[3, 3]f32{
					math.cos(z_angle), -math.sin(z_angle), 0,
					math.sin(z_angle), math.cos(z_angle), 0,
					0, 0, 1,
				}

				base_points[c * points_per_circle + p] =
					z_rot * y_rot * rl.Vector3{1, 0, 0} * state.player.radius
			}
		}

		for c in 0 ..< num_circles {
			for p in 0 ..< points_per_circle {
				start := base_points[c * points_per_circle + p]
				end := base_points[c * points_per_circle + (p + 1) % points_per_circle]
				rl.DrawLineEx(project(start, &state), project(end, &state), 2, rl.ORANGE)
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
	collisions: [dynamic; 10]^Surface,
}

Surface :: struct {
	name: string,
	o:    rl.Vector3,
	w:    f32,
	h:    f32,
	n:    rl.Vector3,
	u:    rl.Vector3,
	v:    rl.Vector3,
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
