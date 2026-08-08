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

	for &skater in state.skaters {
		prev_pos := skater.pos
		defer if skater.pos != prev_pos {
			any_skater_moved = true
		}

		should_reset := check(state, inputs, skater.idx, .Reset, .Pressed)

		if !should_reset {
			if skater.idx == state.target_skater_idx && state.play_mode == .Ghost {
				ghost_move(state, inputs, &skater, dt)
			} else if skater.state == .Grinding {
				move(state, inputs, &skater, dt)
				apply_velocity(state, inputs, &skater, dt)
				stop_grinding(state, &skater)
			} else {
				steer(state, inputs, &skater, dt)
				move(state, inputs, &skater, dt)
				apply_gravity(state, inputs, &skater, dt)
				physics(state, inputs, &skater, dt)
				apply_velocity(state, inputs, &skater, dt)
				stuck := start_grinding(state, &skater)
				if !stuck {
					touching_a_surface := collisions(state, &skater)
					should_reset = transition(state, inputs, &skater, dt, touching_a_surface)
				}
			}
			animation_tick(state, &skater, animation_get_value(&skater, state))
		}

		if should_reset {reset_skater(&skater)}
	}
}

ghost_move :: proc(state: ^State, inputs: Input_State, skater: ^Skater, dt: f32) {
	z_dir: f32
	if check(state, inputs, skater.idx, .Up, .Down) {z_dir = +1}
	if check(state, inputs, skater.idx, .Down, .Down) {z_dir = -1}
	if z_dir != 0 {
		skater.pos.z += z_dir * 5 * dt
	}
	steer_dir: f32
	if check(state, inputs, skater.idx, .Left, .Down) {steer_dir = -1}
	if check(state, inputs, skater.idx, .Right, .Down) {steer_dir = +1}
	angle_change := steer_dir * dt * state.config.data.movement.airborne_steer_speed
	skater.angle = angle_change + linalg.atan2(skater.look_dir.y, skater.look_dir.x)
	if skater.angle < 0 {skater.angle += 2 * math.PI}
	skater.look_dir = rl.Vector3RotateByAxisAngle(
		rl.Vector3{1, 0, 0},
		rl.Vector3{0, 0, 1},
		skater.angle,
	)
	skater.look_dir = linalg.normalize(skater.look_dir)
	if check(state, inputs, skater.idx, .Push, .Down) {
		skater.pos += skater.look_dir * 5 * dt
	}
}

steer :: proc(state: ^State, inputs: Input_State, skater: ^Skater, dt: f32) {
	steer_dir: f32
	if check(state, inputs, skater.idx, .Left, .Down) {steer_dir = -1}
	if check(state, inputs, skater.idx, .Right, .Down) {steer_dir = +1}

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

move :: proc(state: ^State, inputs: Input_State, skater: ^Skater, dt: f32) {
	switch skater.state {
	case .Idle:
		if check(state, inputs, skater.idx, .Push, .Pressed) {
			skater.vel += skater.move_dir * state.config.data.movement.push_impulse
			break
		}
		for action in Input_Action.Trick_WN ..= Input_Action.Trick_SW {
			if check(state, inputs, skater.idx, action, .Pressed) {
				transition_state(state, skater, .Crouched)
				skater.trick_buffer[0] = action
				skater.trick_buffer_len = 1
			}
		}
	case .Crouched:
		for action in Input_Action.Trick_W ..= Input_Action.Trick_SW {
			if skater.trick_buffer_len >= 3 {break}
			if check(state, inputs, skater.idx, action, .Pressed) {
				skater.trick_buffer[skater.trick_buffer_len] = action
				skater.trick_buffer_len += 1
			}
		}

		if skater.trick_buffer_len >= 3 ||
		   check(state, inputs, skater.idx, skater.trick_buffer[0], .Released) {
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
			if check(state, inputs, skater.idx, .Trick_O, .Pressed) {
				skater.trick_caught = true
			}
			break
		}

		for action in Input_Action.Trick_W ..= Input_Action.Trick_SW {
			if skater.trick_buffer_len >= 3 {break}
			if check(state, inputs, skater.idx, action, .Pressed) {
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
	case .Grinding:
		skater.timer[.Grinding] += dt
	}
}

apply_gravity :: proc(state: ^State, inputs: Input_State, skater: ^Skater, dt: f32) {
	gravity := state.config.data.physics.gravity_falling
	if skater.vel.z >= 0 {gravity = state.config.data.physics.gravity_rising}
	skater.vel -= rl.Vector3{0, 0, gravity * dt}
}

apply_velocity :: proc(state: ^State, inputs: Input_State, skater: ^Skater, dt: f32) {
	skater.vel.xy = rl.Vector2ClampValue(skater.vel.xy, 0, state.config.data.movement.max_speed)
	skater.pos += skater.vel * dt
}

physics :: proc(state: ^State, inputs: Input_State, skater: ^Skater, dt: f32) {
	if math.abs(linalg.length(skater.vel.xy)) > state.config.data.physics.friction_stop_threshold {
		friction_coeff := state.config.data.physics.friction
		if check(state, inputs, skater.idx, .Break, .Down) {
			friction_coeff *= state.config.data.physics.braking_multiplier
		}
		skater.vel = skater.vel - skater.move_dir * friction_coeff * dt
	} else {
		skater.vel.xy = {0, 0}
	}

	if skater.state != .Airborne || skater.trick_caught {
		skater.skate_angles.xy = {}
	} else if skater.skate_angles.xy != {} {
		skater.skate_angles.zw += dt * skater.skate_angles.xy
	}
}

start_grinding :: proc(state: ^State, skater: ^Skater) -> bool {
	if skater.state != .Airborne {return false}

	for object, object_idx in state.objects {
		if object.kind == .Ramp {continue}

		offset := skater.radius

		in_bounds: [3]bool
		at_edge: [3]bit_set[enum u8 {
			lo,
			hi,
		}]
		for i in 0 ..< len(in_bounds) {
			{
				min := object.pos[i]
				max := object.pos[i] + object.size[i]
				in_bounds[i] = skater.pos[i] >= min && skater.pos[i] <= max
			}
			{
				min := object.pos[i] - offset
				max := object.pos[i] + offset
				if skater.pos[i] >= min && skater.pos[i] <= max {at_edge[i] |= {.lo}}
			}
			{
				min := object.pos[i] + object.size[i] - offset
				max := object.pos[i] + object.size[i] + offset
				if skater.pos[i] >= min && skater.pos[i] <= max {at_edge[i] |= {.hi}}
			}
		}

		if .hi not_in at_edge.z {continue}

		if at_edge.x != {} {
			if in_bounds.y {
				fmt.printfln("Grinding on edge %v along y axis!", at_edge.x)
				transition_state(state, skater, .Grinding)
				skater.pos.z = object.pos.z + object.size.z
				skater.pos.x = object.pos.x
				if .hi in at_edge.x {skater.pos.x += object.size.x}
				skater.vel.xz = 0
				skater.grind_target_idx = object_idx
				return true
			}
		}
	}

	return false
}

stop_grinding :: proc(state: ^State, skater: ^Skater) -> bool {
	if skater.state != .Grinding {return false}
	i := skater.vel.x > 0 ? 0 : 1
	object := state.objects[skater.grind_target_idx]
	offset := skater.radius
	min := object.pos[i] - offset
	max := object.pos[i] + object.size[i] + offset
	in_bounds := skater.pos[i] >= min && skater.pos[i] <= max
	if in_bounds {
		return false
	}
	transition_state(state, skater, .Airborne)
	return true
}

collisions :: proc(state: ^State, skater: ^Skater) -> bool {
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

reset_skater :: proc(skater: ^Skater) {
	skater.radius = SKATER_RADIUS
	skater.vel = rl.Vector3{}
	skater.state = .Idle
	skater.timer = {}
	skater.jump_height = 0
	skater.trick_buffer_len = 0
	skater.trick_committed = .None
	skater.trick_caught = false
	skater.skate_angles = {}

	if skater.idx == 0 {
		skater.angle = math.PI / 2
		skater.pos = {4, 2, 4}
	} else {
		skater.angle = 0
		skater.pos = {1, 1, 4}
	}
	skater.pos += rl.Vector3(skater.radius)

	skater.move_dir = linalg.normalize(rl.Vector3({1, 1, 0}))
	if skater.angle != 0 {
		skater.move_dir = rl.Vector3RotateByAxisAngle(skater.move_dir, {0, 0, 1}, skater.angle)
	}
	skater.look_dir = skater.move_dir
	skater.norm = {0, 0, 1}
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
	skater.grind_target_idx = 0
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
