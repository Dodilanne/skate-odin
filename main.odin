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

	rl.SetTargetFPS(60)
	rl.SetTraceLogLevel(.WARNING)
	rl.InitWindow(32 * 40, 32 * 23, "skate")
	rl.SetWindowState({.WINDOW_RESIZABLE})

	player_radius: f32 = 0.5
	initial_player := Player {
		pos        = rl.Vector3{1, 1, 4} + rl.Vector3(player_radius),
		move_dir   = linalg.normalize(rl.Vector3({1, 1, 0})),
		look_dir   = linalg.normalize(rl.Vector3({1, 1, 0})),
		norm       = {0, 0, 1},
		steer_rate = 0.2,
		mass       = 1,
		max_speed  = 8,
		radius     = player_radius,
	}

	state := State {
		show_normals = false,
		color_mode   = .dark,
		drawing_mode = .dimetric,
		player       = initial_player,
		surfaces     = {
			{name = "floor_1", o = {1, 1, 4}, w = 11, h = 9, n = {0, 0, 1}},
			{name = "ledge_1_top", o = {0, 0, 5}, w = 1, h = 13, n = {0, 0, 1}},
			{name = "ledge_1_side_long", o = {1, 1, 4}, w = 9, h = 1, n = {1, 0, 0}},
			{name = "ledge_1_side_tall", o = {1, 10, 3}, w = 3, h = 2, n = {1, 0, 0}},
			{name = "ledge_1_front_tall", o = {0, 13, 3}, w = 1, h = 2, n = {0, 1, 0}},
			{name = "ledge_2_top", o = {1, 0, 5}, w = 12, h = 1, n = {0, 0, 1}},
			{name = "ledge_2_side", o = {1, 1, 4}, w = 11, h = 1, n = {0, 1, 0}},
			{name = "ledge_3_side", o = {12, 1, 5}, w = 1, h = 12, n = {0, 0, 1}},
			{name = "ledge_3_side_tall", o = {13, 0, 3}, w = 13, h = 2, n = {1, 0, 0}},
			{name = "ledge_3_back_tall", o = {12, 0, 3}, w = 13, h = 2, n = {-1, 0, 0}},
			{name = "ledge_3_front_tall", o = {12, 13, 3}, w = 1, h = 2, n = {0, 1, 0}},
			{name = "floor_2", o = {0, 0, 3}, w = 16, h = 26, n = {0, 0, 1}},
			{name = "floor_3", o = {0, 0, 2}, w = 50, h = 50, n = {0, 0, 1}},
			{
				name = "jump_1",
				o = {1, 10, 4},
				w = 11,
				h = math.sqrt(f32(2 * 2 + 1 * 1)),
				n = rl.Vector3RotateByAxisAngle({0, 0, 1}, {1, 0, 0}, -math.atan2_f32(1, 2)),
			},
			{
				name = "jump_2",
				o = {16, 0, 3},
				w = 26,
				h = math.sqrt(f32(2 * 2 + 1 * 1)),
				n = rl.Vector3RotateByAxisAngle({0, 0, 1}, {0, 1, 0}, math.atan2_f32(1, 2)),
			},
		},
	}


	for &surface in state.surfaces {
		surface.n = linalg.normalize(surface.n)

		a := rl.Vector3{0, 0, 1} // arbitrary
		if surface.n == a do a = rl.Vector3{0, 1, 0} // cross product will give 0, need to use another ref vector

		u := linalg.normalize(linalg.cross(surface.n, a))
		if linalg.dot(u, largest_abs_component(u)) < 0.01 do u *= -1
		surface.u = u

		v := linalg.normalize(linalg.cross(surface.n, u))
		if linalg.dot(v, largest_abs_component(v)) < 0.01 do v *= -1
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

		player_angle: f32

		steer_dir: f32 = 0
		if rl.IsKeyDown(.R) do steer_dir = -1
		if rl.IsKeyDown(.T) do steer_dir = +1

		if state.player.airborne {
			speed: f32 = 6
			angle_change := steer_dir * dt * speed
			player_angle =
				angle_change + linalg.atan2(state.player.look_dir.y, state.player.look_dir.x)
			state.player.look_dir = rl.Vector3RotateByAxisAngle(
				rl.Vector3{1, 0, 0},
				rl.Vector3{0, 0, 1},
				player_angle,
			)
			state.player.look_dir = linalg.normalize(state.player.look_dir)
		} else if steer_dir != 0 {
			speed := linalg.length(state.player.vel) * state.player.steer_rate
			if speed == 0 do speed = 2
			angle_change := steer_dir * dt * speed
			player_angle =
				angle_change + linalg.atan2(state.player.move_dir.y, state.player.move_dir.x)
			state.player.move_dir = rl.Vector3RotateByAxisAngle(
				rl.Vector3{1, 0, 0},
				rl.Vector3{0, 0, 1},
				player_angle,
			)
			state.player.move_dir = linalg.normalize(state.player.move_dir)
			state.player.vel = rl.Vector3RotateByAxisAngle(
				state.player.vel,
				rl.Vector3{0, 0, 1},
				angle_change,
			)
		}

		if rl.IsKeyPressed(.ENTER) {
			state.player.vel += state.player.move_dir
		}

		if rl.IsKeyReleased(.COMMA) {
			state.player.vel.z += 4
		}

		state.player.vel -= rl.Vector3{0, 0, state.player.mass * 10 * dt}

		if math.abs(linalg.length(state.player.vel.xy)) > 0.1 {
			friction_coeff: f32 = 0.5
			if rl.IsKeyDown(.SPACE) do friction_coeff *= 10
			state.player.vel = state.player.vel - state.player.move_dir * friction_coeff * dt
		} else {
			state.player.vel.xy = {0, 0}
		}

		state.player.vel.xy = rl.Vector2ClampValue(state.player.vel.xy, 0, state.player.max_speed)

		state.player.pos += state.player.vel * dt

		state.player.airborne = true
		for &surface in state.surfaces {
			p := state.player.pos - surface.o
			d := linalg.dot(surface.n, p)
			if math.abs(d) > state.player.radius do continue
			pp := p - d * surface.n
			px := linalg.dot(pp, surface.u)
			if px < 0 || px > surface.w do continue
			py := linalg.dot(pp, surface.v)
			if py < 0 || py > surface.h do continue
			state.player.pos += (state.player.radius - d) * surface.n
			state.player.vel -= linalg.dot(state.player.vel, surface.n) * surface.n
			if linalg.length(state.player.vel) != 0 do state.player.move_dir = linalg.normalize(state.player.vel)
			if surface.n.z != 0 {
				state.player.airborne = false
			}
		}

		crashed := false
		if !state.player.airborne {
			diff := linalg.dot(state.player.move_dir, state.player.look_dir)
			abs := math.abs(diff)
			if abs < 0.85 {
				crashed = true
			} else {
				state.player.look_dir = state.player.move_dir * math.sign(diff)
			}
		}

		if crashed || state.player.pos.z < -10 || rl.IsKeyPressed(.ZERO) {
			state.player = initial_player
		}

		if rl.IsKeyPressed(.N) {
			state.show_normals = !state.show_normals
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
			if state.show_normals {
				rl.DrawCircleV(project(surface.o - state.player.pos, &state), 4, rl.BLUE)
				rl.DrawLineEx(
					project(surface.o - state.player.pos, &state),
					project(surface.o + surface.n - state.player.pos, &state),
					2,
					rl.RED,
				)
				rl.DrawLineEx(
					project(surface.o - state.player.pos, &state),
					project(surface.o + surface.u - state.player.pos, &state),
					2,
					rl.GREEN,
				)
				rl.DrawLineEx(
					project(surface.o - state.player.pos, &state),
					project(surface.o + surface.v - state.player.pos, &state),
					2,
					rl.YELLOW,
				)
			}
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
				color := rl.ORANGE
				if state.player.airborne do color = rl.GREEN
				rl.DrawLineEx(project(start, &state), project(end, &state), 2, color)
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
			project(state.player.move_dir, &state),
			4,
			rl.BLUE,
		)

		rl.DrawLineEx(
			project(rl.Vector3(0), &state),
			project(state.player.look_dir, &state),
			4,
			rl.YELLOW,
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
		return rl.Vector2{-point.y, -point.z} * state.cell_size + state.offset
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
	move_dir:   rl.Vector3,
	look_dir:   rl.Vector3,
	norm:       rl.Vector3,
	pos:        rl.Vector3,
	vel:        rl.Vector3,
	forces:     rl.Vector3,
	mass:       f32,
	steer_rate: f32,
	max_speed:  f32,
	radius:     f32,
	airborne:   bool,
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
	surfaces:     [dynamic; 20]Surface,
	drawing_mode: Drawing_Mode,
	color_mode:   Color_Mode,
	cell_size:    f32,
	offset:       rl.Vector2,
	show_normals: bool,
}

largest_abs_component :: proc(v: rl.Vector3) -> rl.Vector3 {
	abs := linalg.abs(v)
	if abs.x >= abs.y && abs.x >= abs.z do return {1, 0, 0}
	if abs.y >= abs.z do return {0, 1, 0}
	return {0, 0, 1}
}
