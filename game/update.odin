package game

import "core:math"
import "core:math/linalg"
import rl "vendor:raylib"

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

update :: proc(state: ^State) {
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

	steer_dir: f32 = 0
	if rl.IsKeyDown(.R) do steer_dir = -1
	if rl.IsKeyDown(.T) do steer_dir = +1

	if state.player.airborne {
		speed: f32 = 6
		angle_change := steer_dir * dt * speed
		state.player.angle =
			angle_change + linalg.atan2(state.player.look_dir.y, state.player.look_dir.x)
		state.player.look_dir = rl.Vector3RotateByAxisAngle(
			rl.Vector3{1, 0, 0},
			rl.Vector3{0, 0, 1},
			state.player.angle,
		)
		state.player.look_dir = linalg.normalize(state.player.look_dir)
	} else if steer_dir != 0 {
		speed := linalg.length(state.player.vel) * state.player.steer_rate
		if speed == 0 do speed = 2
		angle_change := steer_dir * dt * speed
		state.player.angle =
			angle_change + linalg.atan2(state.player.move_dir.y, state.player.move_dir.x)
		state.player.move_dir = rl.Vector3RotateByAxisAngle(
			rl.Vector3{1, 0, 0},
			rl.Vector3{0, 0, 1},
			state.player.angle,
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
}
