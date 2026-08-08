package game

import "core:fmt"
import "core:math"
import "core:math/linalg"
import rl "vendor:raylib"

SKATER_RADIUS: f32 : 0.5

update :: proc(state: ^State, inputs: Input_State, dt: f32) {
	when ODIN_DEBUG {read_debug_inputs(state, inputs)}

	any_skater_moved := false
	defer if any_skater_moved {
		init_entities(state)
	}

	for &skater, skater_idx in state.skaters {
		prev_pos := skater.pos
		defer if skater.pos != prev_pos {
			any_skater_moved = true
		}

		should_reset := check(state, inputs, skater_idx, .Reset, .Pressed)

		if !should_reset {
			if skater_idx == state.target_skater_idx && state.play_mode == .Ghost {
				ghost_move(state, inputs, &skater, skater_idx, dt)
				animation_tick(state, &skater, skater_idx, animation_get_value(&skater, state))
			} else {
				steer(state, inputs, &skater, skater_idx, dt)
				move(state, inputs, &skater, skater_idx, dt)
				physics(state, inputs, &skater, skater_idx, dt)
				anim := animation_get_value(&skater, state)
				animation_tick(state, &skater, skater_idx, anim)
				touching_a_surface := collisions(state, &skater, skater_idx)
				should_reset = transition(
					state,
					inputs,
					&skater,
					skater_idx,
					dt,
					touching_a_surface,
				)
			}
		}

		if should_reset {reset_skater(&skater)}
	}
}

ghost_move :: proc(state: ^State, inputs: Input_State, skater: ^Skater, skater_idx: int, dt: f32) {
	z_dir: f32
	if check(state, inputs, skater_idx, .Up, .Down) {z_dir = +1}
	if check(state, inputs, skater_idx, .Down, .Down) {z_dir = -1}
	if z_dir != 0 {
		skater.pos.z += z_dir * 5 * dt
	}
	steer_dir: f32
	if check(state, inputs, skater_idx, .Left, .Down) {steer_dir = -1}
	if check(state, inputs, skater_idx, .Right, .Down) {steer_dir = +1}
	angle_change := steer_dir * dt * state.config.data.movement.airborne_steer_speed
	skater.angle = angle_change + linalg.atan2(skater.look_dir.y, skater.look_dir.x)
	if skater.angle < 0 {skater.angle += 2 * math.PI}
	skater.look_dir = rl.Vector3RotateByAxisAngle(
		rl.Vector3{1, 0, 0},
		rl.Vector3{0, 0, 1},
		skater.angle,
	)
	skater.look_dir = linalg.normalize(skater.look_dir)
	if check(state, inputs, skater_idx, .Push, .Down) {
		skater.pos += skater.look_dir * 5 * dt
	}
}

steer :: proc(state: ^State, inputs: Input_State, skater: ^Skater, skater_idx: int, dt: f32) {
	steer_dir: f32
	if check(state, inputs, skater_idx, .Left, .Down) {steer_dir = -1}
	if check(state, inputs, skater_idx, .Right, .Down) {steer_dir = +1}

	if skater.state == .Airborne {
		angle_change := steer_dir * dt * state.config.data.movement.airborne_steer_speed
		skater.angle = angle_change + linalg.atan2(skater.look_dir.y, skater.look_dir.x)
		if skater.angle < 0 {skater.angle += 2 * math.PI}
		skater.look_dir = rl.Vector3RotateByAxisAngle(
			rl.Vector3{1, 0, 0},
			rl.Vector3{0, 0, 1},
			skater.angle,
		)
		skater.look_dir = linalg.normalize(skater.look_dir)
	} else if steer_dir != 0 {
		speed := linalg.length(skater.vel) * state.config.data.movement.riding_steer_rate
		if speed == 0 {speed = state.config.data.movement.stopped_steer_speed}

		angle_change := steer_dir * dt * speed

		skater.angle = angle_change + linalg.atan2(skater.move_dir.y, skater.move_dir.x)
		if skater.angle < 0 {skater.angle += 2 * math.PI}
		skater.move_dir = rl.Vector3RotateByAxisAngle(
			rl.Vector3{1, 0, 0},
			rl.Vector3{0, 0, 1},
			skater.angle,
		)
		skater.move_dir = linalg.normalize(skater.move_dir)
		skater.vel = rl.Vector3RotateByAxisAngle(skater.vel, rl.Vector3{0, 0, 1}, angle_change)
	}

}

move :: proc(state: ^State, inputs: Input_State, skater: ^Skater, skater_idx: int, dt: f32) {
	switch skater.state {
	case .Idle:
		if check(state, inputs, skater_idx, .Push, .Pressed) {
			skater.vel += skater.move_dir * state.config.data.movement.push_impulse
			break
		}
		for action in Input_Action.Trick_WN ..= Input_Action.Trick_SW {
			if check(state, inputs, skater_idx, action, .Pressed) {
				transition_state(state, skater, .Crouched)
				skater.trick_buffer[0] = action
				skater.trick_buffer_len = 1
			}
		}
	case .Crouched:
		for action in Input_Action.Trick_W ..= Input_Action.Trick_SW {
			if skater.trick_buffer_len >= 3 {break}
			if check(state, inputs, skater_idx, action, .Pressed) {
				skater.trick_buffer[skater.trick_buffer_len] = action
				skater.trick_buffer_len += 1
			}
		}

		if skater.trick_buffer_len >= 3 ||
		   check(state, inputs, skater_idx, skater.trick_buffer[0], .Released) {
			height := skater.timer[.Crouched] * state.config.data.tricks.jump_height_scale
			height = math.max(height, state.config.data.tricks.min_jump_height)
			skater.vel.z += height
			skater.jump_height = skater.vel.z
		} else {
			skater.timer[.Crouched] = math.min(
				skater.timer[.Crouched] + dt * state.config.data.tricks.crouch_charge_rate,
				1,
			)
		}
	case .Airborne:
		skater.timer[.Airborne] += dt

		if skater.jump_height == 0 {
			break
		}

		if skater.trick_committed != .None {
			if check(state, inputs, skater_idx, .Trick_O, .Pressed) {
				skater.trick_caught = true
			}
			break
		}

		for action in Input_Action.Trick_W ..= Input_Action.Trick_SW {
			if skater.trick_buffer_len >= 3 {break}
			if check(state, inputs, skater_idx, action, .Pressed) {
				skater.trick_buffer[skater.trick_buffer_len] = action
				skater.trick_buffer_len += 1
			}
		}

		if skater.trick_buffer_len < 1 {
			break
		}

		board_speed := state.config.data.tricks.board_spin_speed
		half_spin_divisor := state.config.data.tricks.half_spin_divisor
		if skater.trick_buffer_len >= 2 {
			switch skater.trick_buffer {
			case {.Trick_S, .Trick_W, .None}:
				skater.trick_committed = .Kickflip
				skater.skate_angles.xy = {0, +board_speed}
			case {.Trick_N, .Trick_W, .None}:
				skater.trick_committed = .Nollie_Flip
				skater.skate_angles.xy = {0, +board_speed}
			case {.Trick_S, .Trick_E, .None}:
				skater.trick_committed = .Heelflip
				skater.skate_angles.xy = {0, -board_speed}
			case {.Trick_N, .Trick_E, .None}:
				skater.trick_committed = .Nollie_Heel
				skater.skate_angles.xy = {0, -board_speed}
			case {.Trick_ES, .Trick_W, .None}:
				skater.trick_committed = .Varial_Flip
				skater.skate_angles.xy = {board_speed / half_spin_divisor, board_speed}
			case {.Trick_NE, .Trick_W, .None}:
				skater.trick_committed = .Nollie_Varial_Flip
				skater.skate_angles.xy = {board_speed / -half_spin_divisor, board_speed}
			case {.Trick_SW, .Trick_E, .None}:
				skater.trick_committed = .Varial_Heel
				skater.skate_angles.xy = {board_speed / -half_spin_divisor, -board_speed}
			case {.Trick_WN, .Trick_E, .None}:
				skater.trick_committed = .Nollie_Varial_Heel
				skater.skate_angles.xy = {board_speed / half_spin_divisor, -board_speed}
			case {.Trick_SW, .Trick_W, .None}:
				skater.trick_committed = .Hard_Flip
				skater.skate_angles.xy = {board_speed / -half_spin_divisor, board_speed}
			case {.Trick_WN, .Trick_W, .None}:
				skater.trick_committed = .Nollie_Hard_Flip
				skater.skate_angles.xy = {board_speed / half_spin_divisor, board_speed}
			case {.Trick_ES, .Trick_E, .None}:
				skater.trick_committed = .Inward_Heel
				skater.skate_angles.xy = {board_speed / half_spin_divisor, -board_speed}
			case {.Trick_NE, .Trick_E, .None}:
				skater.trick_committed = .Nollie_Inward_Heel
				skater.skate_angles.xy = {board_speed / -half_spin_divisor, -board_speed}
			case {.Trick_ES, .Trick_SW, .None}:
				skater.trick_committed = .Shuv_It
				skater.skate_angles.xy = {board_speed / half_spin_divisor, 0}
			case {.Trick_NE, .Trick_WN, .None}:
				skater.trick_committed = .Nollie_Shuv_It
				skater.skate_angles.xy = {board_speed / -half_spin_divisor, 0}
			case {.Trick_SW, .Trick_ES, .None}:
				skater.trick_committed = .Front_Shuv
				skater.skate_angles.xy = {board_speed / -half_spin_divisor, 0}
			case {.Trick_WN, .Trick_NE, .None}:
				skater.trick_committed = .Nollie_Front_Shuv
				skater.skate_angles.xy = {board_speed / half_spin_divisor, 0}
			case {.Trick_ES, .Trick_S, .Trick_W}:
				skater.trick_committed = .Tre_Flip
				skater.skate_angles.xy = {board_speed, board_speed}
			case {.Trick_NE, .Trick_N, .Trick_W}:
				skater.trick_committed = .Nollie_Tre_Flip
				skater.skate_angles.xy = {-board_speed, board_speed}
			case {.Trick_ES, .Trick_S, .Trick_SW}:
				skater.trick_committed = .Tre_Shuv
				skater.skate_angles.xy = {board_speed, 0}
			case {.Trick_NE, .Trick_N, .Trick_WN}:
				skater.trick_committed = .Nollie_Tre_Shuv
				skater.skate_angles.xy = {-board_speed, 0}
			case {.Trick_SW, .Trick_S, .Trick_E}:
				skater.trick_committed = .Lazer_Flip
				skater.skate_angles.xy = {-board_speed, -board_speed}
			case {.Trick_WN, .Trick_N, .Trick_E}:
				skater.trick_committed = .Nollie_Lazer_Flip
				skater.skate_angles.xy = {board_speed, -board_speed}
			case {.Trick_ES, .Trick_S, .Trick_E}:
				skater.trick_committed = .Tre_Inward_Heel
				skater.skate_angles.xy = {board_speed, -board_speed}
			case {.Trick_NE, .Trick_N, .Trick_E}:
				skater.trick_committed = .Nollie_Tre_Inward_Heel
				skater.skate_angles.xy = {-board_speed, -board_speed}
			case {.Trick_SW, .Trick_S, .Trick_W}:
				skater.trick_committed = .Tre_Hard_Flip
				skater.skate_angles.xy = {-board_speed, board_speed}
			case {.Trick_WN, .Trick_N, .Trick_W}:
				skater.trick_committed = .Nollie_Tre_Hard_Flip
				skater.skate_angles.xy = {board_speed, board_speed}
			}
		}

		if skater.trick_committed == .None &&
		   skater.timer[.Airborne] > state.config.data.tricks.trick_commit_delay {
			#partial switch skater.trick_buffer[0] {
			case .Trick_WN, .Trick_N, .Trick_NE:
				skater.trick_committed = .Nollie
			case .Trick_ES, .Trick_S, .Trick_SW:
				skater.trick_committed = .Ollie
			}
		}
	case .Landing:
		skater.timer[.Landing] -= dt
		if skater.timer[.Landing] <= 0 {
			transition_state(state, skater, .Idle)
		}
	}
}

physics :: proc(state: ^State, inputs: Input_State, skater: ^Skater, skater_idx: int, dt: f32) {
	gravity := state.config.data.physics.gravity_falling
	if skater.vel.z >= 0 {gravity = state.config.data.physics.gravity_rising}
	skater.vel -= rl.Vector3{0, 0, gravity * dt}

	if math.abs(linalg.length(skater.vel.xy)) > state.config.data.physics.friction_stop_threshold {
		friction_coeff := state.config.data.physics.friction
		if check(state, inputs, skater_idx, .Break, .Down) {
			friction_coeff *= state.config.data.physics.braking_multiplier
		}
		skater.vel = skater.vel - skater.move_dir * friction_coeff * dt
	} else {
		skater.vel.xy = {0, 0}
	}

	skater.vel.xy = rl.Vector2ClampValue(skater.vel.xy, 0, state.config.data.movement.max_speed)

	skater.pos += skater.vel * dt

	if skater.state != .Airborne || skater.trick_caught {
		skater.skate_angles.xy = {}
	} else if skater.skate_angles.xy != {} {
		skater.skate_angles.zw += dt * skater.skate_angles.xy
	}
}

collisions :: proc(state: ^State, skater: ^Skater, skater_idx: int) -> bool {
	touching_a_surface := false
	for &surface in state.surfaces {
		p := skater.pos - surface.o
		d := linalg.dot(p, surface.n)
		if math.abs(d) >= skater.radius {continue}
		pp := p - d * surface.n
		px := linalg.dot(pp, surface.u)
		if px < 0 || px > surface.w {continue}
		py := linalg.dot(pp, surface.v)
		if py < 0 || py > surface.h {continue}
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
	inputs: Input_State,
	skater: ^Skater,
	skater_idx: int,
	dt: f32,
	touching_a_surface: bool,
) -> bool {
	if !touching_a_surface {
		transition_state(state, skater, .Airborne)
	} else if skater.state == .Airborne {
		transition_state(state, skater, .Landing)
	}

	if skater.state != .Airborne {
		{ 	// player position
			diff := linalg.dot(
				linalg.normalize(skater.move_dir.xy),
				linalg.normalize(skater.look_dir.xy),
			)
			abs := math.abs(diff)
			if skater.state == .Landing &&
			   abs < state.config.data.landing.facing_alignment_min_dot {
				return true
			}
			skater.look_dir = skater.move_dir * math.sign(diff)
		}

		{ 	// board position
			deg := linalg.floor(linalg.abs(rl.RAD2DEG * skater.skate_angles.zw))
			delta := state.config.data.landing.board_angle_snap_deg
			switch int(deg.x) % 360 {
			case 360 - delta ..= 360, 0 ..= delta, 180 - delta ..= 180 + delta:
				skater.skate_angles.z = 0
			case:
				return true
			}
			switch int(deg.y) % 360 {
			case 360 - delta ..= 360, 0 ..= delta:
				skater.skate_angles.w = 0
			case:
				return true
			}
		}
	}

	return skater.pos.z < state.config.data.landing.death_plane_z
}

read_debug_inputs :: proc(state: ^State, inputs: Input_State) {
	if .Pressed in inputs.actions[.Toggle_Drawing_Mode] {
		state.drawing_mode = Drawing_Mode((int(state.drawing_mode) + 1) % len(Drawing_Mode))
	}
	if .Pressed in inputs.actions[.Toggle_Normals] {
		state.show_normals = !state.show_normals
	}
	if .Pressed in inputs.actions[.Cycle_Target] {
		state.target_skater_idx = (state.target_skater_idx + 1) % len(state.skaters)
	}
	if .Pressed in inputs.actions[.Cycle_Play_Mode] {
		state.play_mode = Play_Mode((int(state.play_mode) + 1) % len(Play_Mode))
		skater := &state.skaters[state.target_skater_idx]
		pos := skater.pos
		reset_skater(skater)
		skater.pos = pos
	}
}

reset_skater :: proc(skater: ^Skater, angle: f32 = 0, pos: rl.Vector3 = {1, 1, 4}) {
	skater.vel = rl.Vector3{}
	skater.state = .Idle
	skater.timer = {}
	skater.jump_height = 0
	skater.trick_buffer_len = 0
	skater.trick_committed = .None
	skater.trick_caught = false
	skater.skate_angles = {}
	skater.angle = angle
	skater.pos = pos + rl.Vector3(SKATER_RADIUS)
	skater.move_dir = linalg.normalize(rl.Vector3({1, 1, 0}))
	if angle != 0 {
		skater.move_dir = rl.Vector3RotateByAxisAngle(skater.move_dir, {0, 0, 1}, angle)
	}
	skater.look_dir = skater.move_dir
	skater.norm = {0, 0, 1}
	skater.radius = SKATER_RADIUS
}

check :: proc(
	state: ^State,
	inputs: Input_State,
	skater_idx: int,
	action: Input_Action,
	flag: Input_Flag,
) -> bool {
	if state.target_skater_idx != skater_idx {
		return false
	}
	return flag in inputs.actions[action]
}

transition_state :: proc(state: ^State, skater: ^Skater, new_state: Skater_State) {
	if skater.state == new_state {return}
	skater.state = new_state
	skater.timer[new_state] = 0
	#partial switch new_state {
	case .Idle:
		skater.jump_height = 0
		skater.trick_buffer_len = 0
		skater.trick_buffer = {.None, .None, .None}
		skater.trick_committed = .None
		skater.trick_caught = false
	case .Landing:
		skater.timer[.Landing] =
			skater.timer[.Airborne] * state.config.data.landing.landing_duration_scale
	}
}
