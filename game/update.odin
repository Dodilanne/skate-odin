package game

import "core:math"
import "core:math/linalg"
import "input"
import rl "vendor:raylib"


Player_Intention :: enum u8 {
	steer_left,
	steer_right,
	push,
	stop,
	pop,
	reset,
}

update :: proc(state: ^State, inputs: input.State, dt: f32) {
	screen := rl.Vector2{f32(rl.GetScreenWidth()), f32(rl.GetScreenHeight())}

	state.cell_size = f32(32)
	state.offset = screen / 2

	if .Pressed in inputs.actions[.Toggle_Drawing_Mode] {
		state.drawing_mode = Drawing_Mode((int(state.drawing_mode) + 1) % len(Drawing_Mode))
	}
	if .Pressed in inputs.actions[.Toggle_Color_Mode] {
		state.color_mode = Color_Mode((int(state.color_mode) + 1) % len(Color_Mode))
	}
	if .Pressed in inputs.actions[.Toggle_Normals] {
		state.show_normals = !state.show_normals
	}
	if .Pressed in inputs.actions[.Cycle_Target] {
		state.target_skater_idx = (state.target_skater_idx + 1) % len(state.skaters)
	}

	for &skater, i in state.skaters {
		intentions: bit_set[Player_Intention]
		if state.target_skater_idx == i {
			if .Down in inputs.actions[.Left] do intentions |= {.steer_left}
			if .Down in inputs.actions[.Right] do intentions |= {.steer_right}
			if .Pressed in inputs.actions[.Push] do intentions |= {.push}
			if .Down in inputs.actions[.Break] do intentions |= {.stop}
			if .Released in inputs.actions[.Trick_S] do intentions |= {.pop}
			if .Pressed in inputs.actions[.Reset] do intentions |= {.reset}
		}

		steer_dir: f32 = 0
		if .steer_left in intentions do steer_dir = -1
		if .steer_right in intentions do steer_dir = +1

		if skater.state == .airborne {
			speed: f32 = 6
			angle_change := steer_dir * dt * speed
			skater.angle = angle_change + linalg.atan2(skater.look_dir.y, skater.look_dir.x)
			skater.look_dir = rl.Vector3RotateByAxisAngle(
				rl.Vector3{1, 0, 0},
				rl.Vector3{0, 0, 1},
				skater.angle,
			)
			skater.look_dir = linalg.normalize(skater.look_dir)
		} else if steer_dir != 0 {
			speed := linalg.length(skater.vel) * skater.steer_rate
			if speed == 0 do speed = 2
			angle_change := steer_dir * dt * speed
			skater.angle = angle_change + linalg.atan2(skater.move_dir.y, skater.move_dir.x)
			skater.move_dir = rl.Vector3RotateByAxisAngle(
				rl.Vector3{1, 0, 0},
				rl.Vector3{0, 0, 1},
				skater.angle,
			)
			skater.move_dir = linalg.normalize(skater.move_dir)
			skater.vel = rl.Vector3RotateByAxisAngle(skater.vel, rl.Vector3{0, 0, 1}, angle_change)
		}

		if skater.state != .airborne {
			if .push in intentions do skater.vel += skater.move_dir
			if .pop in intentions do skater.vel.z += 4
		}

		skater.vel -= rl.Vector3{0, 0, 10 * dt}

		if math.abs(linalg.length(skater.vel.xy)) > 0.1 {
			friction_coeff: f32 = 0.5
			if .stop in intentions do friction_coeff *= 10
			skater.vel = skater.vel - skater.move_dir * friction_coeff * dt
		} else {
			skater.vel.xy = {0, 0}
		}

		skater.vel.xy = rl.Vector2ClampValue(skater.vel.xy, 0, skater.max_speed)

		skater.pos += skater.vel * dt


		touching_a_surface := false
		for &surface in state.surfaces {
			p := skater.pos - surface.o
			d := linalg.dot(surface.n, p)
			if math.abs(d) > skater.radius do continue
			pp := p - d * surface.n
			px := linalg.dot(pp, surface.u)
			if px < 0 || px > surface.w do continue
			py := linalg.dot(pp, surface.v)
			if py < 0 || py > surface.h do continue
			skater.pos += (skater.radius - d) * surface.n
			skater.vel -= linalg.dot(skater.vel, surface.n) * surface.n
			if linalg.length(skater.vel) != 0 do skater.move_dir = linalg.normalize(skater.vel)
			if surface.n.z != 0 {
				touching_a_surface = true
			}
		}

		if !touching_a_surface do skater.state = .airborne
		else if skater.state == .airborne do skater.state = .idle

		crashed := false
		if skater.state != .airborne {
			diff := linalg.dot(skater.move_dir, skater.look_dir)
			abs := math.abs(diff)
			if abs < 0.85 {
				crashed = true
			} else {
				skater.look_dir = skater.move_dir * math.sign(diff)
			}
		}

		if crashed || skater.pos.z < -10 || .reset in intentions {
			reset_skater(&skater)
		}
	}
}

SKATER_RADIUS :: 0.5

reset_skater :: proc(skater: ^Skater) {
	skater.vel = rl.Vector3{}
	skater.state = .idle
	skater.angle = 0
	skater.pos = rl.Vector3{1, 1, 4} + rl.Vector3(SKATER_RADIUS)
	skater.move_dir = linalg.normalize(rl.Vector3({1, 1, 0}))
	skater.look_dir = linalg.normalize(rl.Vector3({1, 1, 0}))
	skater.norm = {0, 0, 1}
	skater.steer_rate = 0.2
	skater.max_speed = 8
	skater.radius = SKATER_RADIUS
}
