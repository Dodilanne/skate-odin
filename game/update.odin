package game

import "core:math"
import "core:math/linalg"
import "input"
import rl "vendor:raylib"

SKATER_RADIUS: f32 : 0.5

update :: proc(state: ^State, inputs: input.State, dt: f32) {
	when ODIN_DEBUG {read_debug_inputs(state, inputs)}
	for &skater, skater_idx in state.skaters {
		steer(state, inputs, &skater, skater_idx, dt)
		move(state, inputs, &skater, skater_idx, dt)
		physics(state, inputs, &skater, skater_idx, dt)
		touching_a_surface := collisions(state, &skater, skater_idx)
		should_reset := transition(state, inputs, &skater, skater_idx, dt, touching_a_surface)
		if should_reset {reset_skater(&skater)}
	}
}

steer :: proc(state: ^State, inputs: input.State, skater: ^Skater, skater_idx: int, dt: f32) {
	steer_dir: f32
	if check(state, inputs, skater_idx, .Left, .Down) {steer_dir = -1}
	if check(state, inputs, skater_idx, .Right, .Down) {steer_dir = +1}

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
		if speed == 0 {speed = 2}

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

}

move :: proc(state: ^State, inputs: input.State, skater: ^Skater, skater_idx: int, dt: f32) {
	#partial switch skater.state {
	case .idle:
		if check(state, inputs, skater_idx, .Push, .Pressed) {
			skater.vel += skater.move_dir
			break
		}
		for action in input.Action.Trick_WN ..= input.Action.Trick_SW {
			if check(state, inputs, skater_idx, action, .Pressed) {
				transition_state(skater, .crouched)
				skater.trick_buffer[0] = action
				skater.trick_buffer_len = 1
			}
		}
	case .crouched:
		for action in input.Action.Trick_W ..= input.Action.Trick_SW {
			if skater.trick_buffer_len >= 3 {break}
			if check(state, inputs, skater_idx, action, .Pressed) {
				skater.trick_buffer[skater.trick_buffer_len] = action
				skater.trick_buffer_len += 1
			}
		}

		if skater.trick_buffer_len >= 3 ||
		   check(state, inputs, skater_idx, skater.trick_buffer[0], .Released) {
			height := 6 * skater.state_timer
			height = math.max(height, 3)
			skater.vel.z += height
		} else {
			skater.state_timer = math.min(skater.state_timer + dt * 1.5, 1)
		}
	case .airborne:
		skater.state_timer += dt

		if skater.trick_committed != "" {
			if check(state, inputs, skater_idx, .Trick_O, .Pressed) {
				skater.trick_caught = true
			}
			break
		}

		for action in input.Action.Trick_W ..= input.Action.Trick_SW {
			if skater.trick_buffer_len >= 3 {break}
			if check(state, inputs, skater_idx, action, .Pressed) {
				skater.trick_buffer[skater.trick_buffer_len] = action
				skater.trick_buffer_len += 1
			}
		}

		if skater.trick_buffer_len < 1 {
			break
		}

		if skater.trick_buffer_len == 2 {
			switch skater.trick_buffer {
			case {.Trick_S, .Trick_W, .None}:
				skater.trick_committed = "Kickflip"
			case {.Trick_S, .Trick_E, .None}:
				skater.trick_committed = "Heelflip"
			case {.Trick_N, .Trick_W, .None}:
				skater.trick_committed = "Nollie Flip"
			case {.Trick_N, .Trick_E, .None}:
				skater.trick_committed = "Nollie Heel"
			}
		} else if skater.trick_buffer_len >= 3 {
			skater.trick_committed = "BIG MOVE"
		} else if skater.state_timer > 0.3 {
			#partial switch skater.trick_buffer[0] {
			case .Trick_WN, .Trick_N, .Trick_NE:
				skater.trick_committed = "Nollie"
			case .Trick_ES, .Trick_S, .Trick_SW:
				skater.trick_committed = "Ollie"
			}
		}
	}
}

physics :: proc(state: ^State, inputs: input.State, skater: ^Skater, skater_idx: int, dt: f32) {
	skater.vel -= rl.Vector3{0, 0, 10 * dt}

	if math.abs(linalg.length(skater.vel.xy)) > 0.1 {
		friction_coeff: f32 = 0.5
		if check(state, inputs, skater_idx, .Break, .Down) {
			friction_coeff *= 10
		}
		skater.vel = skater.vel - skater.move_dir * friction_coeff * dt
	} else {
		skater.vel.xy = {0, 0}
	}

	skater.vel.xy = rl.Vector2ClampValue(skater.vel.xy, 0, skater.max_speed)

	skater.pos += skater.vel * dt

	if skater.state != .airborne || skater.trick_caught {
		skater.skate_angles = {0, 0}
	} else {
		switch skater.trick_committed {
		case "Kickflip", "Nollie Flip":
			skater.skate_angles.y += dt * 10
		case "Heelflip", "Nollie Heel":
			skater.skate_angles.y -= dt * 10
		}
	}
}

collisions :: proc(state: ^State, skater: ^Skater, skater_idx: int) -> bool {
	touching_a_surface := false
	for &surface in state.surfaces {
		p := skater.pos - surface.o
		d := linalg.dot(surface.n, p)
		if math.abs(d) > skater.radius {
			continue
		}
		pp := p - d * surface.n
		px := linalg.dot(pp, surface.u)
		if px < 0 || px > surface.w {
			continue
		}
		py := linalg.dot(pp, surface.v)
		if py < 0 || py > surface.h {
			continue
		}
		skater.pos += (skater.radius - d) * surface.n
		skater.vel -= linalg.dot(skater.vel, surface.n) * surface.n
		if linalg.length(skater.vel) != 0 {
			skater.move_dir = linalg.normalize(skater.vel)
		}
		if surface.n.z != 0 {
			touching_a_surface = true
		}
	}
	return touching_a_surface
}

transition :: proc(
	state: ^State,
	inputs: input.State,
	skater: ^Skater,
	skater_idx: int,
	dt: f32,
	touching_a_surface: bool,
) -> bool {
	if !touching_a_surface {
		if skater.state != .airborne {
			skater.state_timer = 0
		}
		skater.state = .airborne
	} else if skater.state == .airborne {
		transition_state(skater, .idle)
	}

	if skater.state != .airborne {
		diff := linalg.dot(skater.move_dir, skater.look_dir)
		abs := math.abs(diff)
		if abs < 0.85 {
			return true
		}
		skater.look_dir = skater.move_dir * math.sign(diff)
	}

	return skater.pos.z < -10 || check(state, inputs, skater_idx, .Reset, .Pressed)
}

read_debug_inputs :: proc(state: ^State, inputs: input.State) {
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
}

reset_skater :: proc(skater: ^Skater) {
	skater.vel = rl.Vector3{}
	skater.state = .idle
	skater.state_timer = 0
	skater.trick_buffer_len = 0
	skater.trick_committed = ""
	skater.angle = 0
	skater.pos = rl.Vector3{1, 1, 4} + rl.Vector3(SKATER_RADIUS)
	skater.move_dir = linalg.normalize(rl.Vector3({1, 1, 0}))
	skater.look_dir = linalg.normalize(rl.Vector3({1, 1, 0}))
	skater.norm = {0, 0, 1}
	skater.steer_rate = 0.2
	skater.max_speed = 8
	skater.radius = SKATER_RADIUS
}

check :: proc(
	state: ^State,
	inputs: input.State,
	skater_idx: int,
	action: input.Action,
	flag: input.Flag,
) -> bool {
	if state.target_skater_idx != skater_idx {
		return false
	}
	return flag in inputs.actions[action]
}

transition_state :: proc(skater: ^Skater, state: Skater_State) {
	skater.state = state
	skater.state_timer = 0
	skater.trick_buffer_len = 0
	skater.trick_buffer = {.None, .None, .None}
	skater.trick_committed = ""
	skater.trick_caught = false
}
