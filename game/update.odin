package game

import "core:fmt"
import "core:math"
import "core:math/linalg"
import rl "vendor:raylib"

SKATER_RADIUS: f32 : 0.5

//#region update

update :: proc(state: ^State, inputs: Input_State, dt: f32) {
	when ODIN_DEBUG {
		if .Pressed in inputs.actions[.Toggle_Drawing_Mode] {
			state.drawing_mode = Drawing_Mode((int(state.drawing_mode) + 1) % len(Drawing_Mode))
		}
		if .Pressed in inputs.actions[.Toggle_Normals] {
			state.show_normals = !state.show_normals
		}
		if .Pressed in inputs.actions[.Cycle_Target] {
			state.target_skater_idx = (state.target_skater_idx + 1) % len(state.skaters)
		}
	}

	any_skater_moved := false
	defer if any_skater_moved do init_entities(state)

	for &skater in state.skaters {
		moved := update_skater(state, inputs, dt, &skater)
		if moved do any_skater_moved = true
	}
}

update_skater :: proc(
	state: ^State,
	inputs: Input_State,
	dt: f32,
	skater: ^Skater,
) -> (
	moved: bool,
) {
	prev_pos := skater.pos

	if check(state, inputs, skater.idx, .Reset, .Pressed) {
		reset_skater(skater)
		return true
	}
	for action, idx in Input_Action.Spawn_1 ..= Input_Action.Spawn_9 {
		if idx > len(state.spawn_points) - 1 do break
		if check(state, inputs, skater.idx, action, .Pressed) {
			skater.last_respawn_point = state.spawn_points[idx]
			reset_skater(skater)
			skater.state = Skater_State_Ghost{}
			return true
		}
	}

	defer animation_tick(state, skater)

	next_state: Maybe(Skater_State)

	switch _ in skater.state {
	case Skater_State_Idle:
		next_state = update_skater_idle(state, inputs, dt, skater)
	case Skater_State_Grinding:
		next_state = update_skater_grinding(state, inputs, dt, skater)
	case Skater_State_Crouched:
		next_state = update_skater_crouched(state, inputs, dt, skater)
	case Skater_State_Airborne:
		next_state = update_skater_airborne(state, inputs, dt, skater)
	case Skater_State_Landing:
		next_state = update_skater_landing(state, inputs, dt, skater)
	case Skater_State_Dropping:
		next_state = update_skater_dropping(state, inputs, dt, skater)
	case Skater_State_Ghost:
		next_state = update_skater_ghost(state, inputs, dt, skater)
	}

	if next_state, ok := next_state.?; ok {
		skater.state = next_state
		skater.timer = 0
	}

	if skater.pos.z < state.config.data.landing.death_plane_z {
		reset_skater(skater)
	}

	return skater.pos != prev_pos
}


update_skater_idle :: proc(
	state: ^State,
	inputs: Input_State,
	dt: f32,
	skater: ^Skater,
) -> Maybe(Skater_State) {
	skater_state := &skater.state.(Skater_State_Idle)

	{ 	// user inputs
		if check(state, inputs, skater.idx, .Cycle_Play_Mode, .Pressed) {
			return Skater_State_Ghost{}
		}

		steer(state, inputs, skater, dt)

		if check(state, inputs, skater.idx, .Push, .Pressed) {
			skater.vel += get_mov_dir(skater) * state.config.data.movement.push_impulse
		}

		for action in Input_Action.Trick_WN ..= Input_Action.Trick_SW {
			if check(state, inputs, skater.idx, action, .Pressed) {
				return Skater_State_Crouched{trick_buf = {buf = {action, .None, .None}, len = 1}}
			}
		}
	}

	{ 	// simulation
		apply_physics(state, inputs, skater, dt)
		snap(skater)
		apply_velocity(state, inputs, skater, dt)
		is_touching_a_floor := apply_collisions(state, skater)
		if !is_touching_a_floor do return Skater_State_Dropping{}
	}

	return nil
}

update_skater_grinding :: proc(
	state: ^State,
	inputs: Input_State,
	dt: f32,
	skater: ^Skater,
) -> Maybe(Skater_State) {
	return nil
}

update_skater_crouched :: proc(
	state: ^State,
	inputs: Input_State,
	dt: f32,
	skater: ^Skater,
) -> Maybe(Skater_State) {
	skater_state := &skater.state.(Skater_State_Crouched)

	{ 	// user inputs
		if check(state, inputs, skater.idx, .Cycle_Play_Mode, .Pressed) {
			return Skater_State_Ghost{}
		}

		steer(state, inputs, skater, dt)

		for action in Input_Action.Trick_W ..= Input_Action.Trick_SW {
			if skater_state.trick_buf.len >= 3 do break
			if check(state, inputs, skater.idx, action, .Pressed) {
				skater_state.trick_buf.buf[skater_state.trick_buf.len] = action
				skater_state.trick_buf.len += 1
			}
		}

		if skater_state.trick_buf.len >= 3 ||
		   check(state, inputs, skater.idx, skater_state.trick_buf.buf[0], .Released) {
			height := skater.timer * state.config.data.tricks.jump_height_scale
			height = math.max(height, state.config.data.tricks.min_jump_height)

			// if grind_state, ok := skater_state.prev_state.(Skater_State_Grinding); ok {
			// 	height *= 0.6
			// 	i := skater.vel.x != 0 ? 1 : 0
			// 	mul: f32 = 0
			// 	if check(state, inputs, skater.idx, .Left, .Down) {
			// 		mul = 1
			// 	} else if check(state, inputs, skater.idx, .Right, .Down) {
			// 		mul = -1
			// 	}
			// 	mul *= math.sign(skater.move_dir[1 - i])
			// 	if skater.vel.x != 0 do mul *= -1
			// 	skater.vel[i] += 2 * mul
			// }

			skater.vel.z += height
			return Skater_State_Airborne {
				jump = Jump_State{height = skater.vel.z, start_pos = skater.pos},
				trick_buf = skater_state.trick_buf,
			}
		}

		skater.timer = math.min(skater.timer + dt * state.config.data.tricks.crouch_charge_rate, 1)
	}

	{ 	// simulation
		apply_physics(state, inputs, skater, dt)
		snap(skater)
		apply_velocity(state, inputs, skater, dt)
		is_touching_a_floor := apply_collisions(state, skater)
		if !is_touching_a_floor do return Skater_State_Dropping{}
	}

	return nil
}

update_skater_airborne :: proc(
	state: ^State,
	inputs: Input_State,
	dt: f32,
	skater: ^Skater,
) -> Maybe(Skater_State) {
	skater_state := &skater.state.(Skater_State_Airborne)

	user_inputs_block: { 	// user inputs
		if check(state, inputs, skater.idx, .Cycle_Play_Mode, .Pressed) {
			return Skater_State_Ghost{}
		}

		steer(state, inputs, skater, dt)

		skater.timer += dt

		if skater_state.jump.height == 0 {
			break user_inputs_block
		}

		if skater_state.committed != .None {
			for action in Input_Action.Trick_W ..= Input_Action.Trick_SW {
				if check(state, inputs, skater.idx, action, .Pressed) {
					skater_state.caught = true
					skater_state.jump.skate_angles.xy = {}
					break user_inputs_block
				}
			}
		}

		for action in Input_Action.Trick_W ..= Input_Action.Trick_SW {
			if skater_state.trick_buf.len >= 3 do break
			if check(state, inputs, skater.idx, action, .Pressed) {
				skater_state.trick_buf.buf[skater_state.trick_buf.len] = action
				skater_state.trick_buf.len += 1
			}
		}

		if skater_state.trick_buf.len < 1 || skater_state.committed != .None {
			break user_inputs_block
		}

		board_speed := state.config.data.tricks.board_spin_speed
		half_spin_divisor := state.config.data.tricks.half_spin_divisor

		if skater_state.trick_buf.len >= 2 {
			switch skater_state.trick_buf.buf {
			case {.Trick_S, .Trick_W, .None}:
				skater_state.committed = .Kickflip
				skater_state.jump.skate_angles.xy = {0, +board_speed}
			case {.Trick_N, .Trick_W, .None}:
				skater_state.committed = .Nollie_Flip
				skater_state.jump.skate_angles.xy = {0, +board_speed}
			case {.Trick_S, .Trick_E, .None}:
				skater_state.committed = .Heelflip
				skater_state.jump.skate_angles.xy = {0, -board_speed}
			case {.Trick_N, .Trick_E, .None}:
				skater_state.committed = .Nollie_Heel
				skater_state.jump.skate_angles.xy = {0, -board_speed}
			case {.Trick_ES, .Trick_W, .None}:
				skater_state.committed = .Varial_Flip
				skater_state.jump.skate_angles.xy = {board_speed / half_spin_divisor, board_speed}
			case {.Trick_NE, .Trick_W, .None}:
				skater_state.committed = .Nollie_Varial_Flip
				skater_state.jump.skate_angles.xy = {board_speed / -half_spin_divisor, board_speed}
			case {.Trick_SW, .Trick_E, .None}:
				skater_state.committed = .Varial_Heel
				skater_state.jump.skate_angles.xy = {
					board_speed / -half_spin_divisor,
					-board_speed,
				}
			case {.Trick_WN, .Trick_E, .None}:
				skater_state.committed = .Nollie_Varial_Heel
				skater_state.jump.skate_angles.xy = {board_speed / half_spin_divisor, -board_speed}
			case {.Trick_SW, .Trick_W, .None}:
				skater_state.committed = .Hard_Flip
				skater_state.jump.skate_angles.xy = {board_speed / -half_spin_divisor, board_speed}
			case {.Trick_WN, .Trick_W, .None}:
				skater_state.committed = .Nollie_Hard_Flip
				skater_state.jump.skate_angles.xy = {board_speed / half_spin_divisor, board_speed}
			case {.Trick_ES, .Trick_E, .None}:
				skater_state.committed = .Inward_Heel
				skater_state.jump.skate_angles.xy = {board_speed / half_spin_divisor, -board_speed}
			case {.Trick_NE, .Trick_E, .None}:
				skater_state.committed = .Nollie_Inward_Heel
				skater_state.jump.skate_angles.xy = {
					board_speed / -half_spin_divisor,
					-board_speed,
				}
			case {.Trick_ES, .Trick_SW, .None}:
				skater_state.committed = .Shuv_It
				skater_state.jump.skate_angles.xy = {board_speed / half_spin_divisor, 0}
			case {.Trick_NE, .Trick_WN, .None}:
				skater_state.committed = .Nollie_Shuv_It
				skater_state.jump.skate_angles.xy = {board_speed / -half_spin_divisor, 0}
			case {.Trick_SW, .Trick_ES, .None}:
				skater_state.committed = .Front_Shuv
				skater_state.jump.skate_angles.xy = {board_speed / -half_spin_divisor, 0}
			case {.Trick_WN, .Trick_NE, .None}:
				skater_state.committed = .Nollie_Front_Shuv
				skater_state.jump.skate_angles.xy = {board_speed / half_spin_divisor, 0}
			case {.Trick_ES, .Trick_S, .Trick_W}:
				skater_state.committed = .Tre_Flip
				skater_state.jump.skate_angles.xy = {board_speed, board_speed}
			case {.Trick_NE, .Trick_N, .Trick_W}:
				skater_state.committed = .Nollie_Tre_Flip
				skater_state.jump.skate_angles.xy = {-board_speed, board_speed}
			case {.Trick_ES, .Trick_S, .Trick_SW}:
				skater_state.committed = .Tre_Shuv
				skater_state.jump.skate_angles.xy = {board_speed, 0}
			case {.Trick_NE, .Trick_N, .Trick_WN}:
				skater_state.committed = .Nollie_Tre_Shuv
				skater_state.jump.skate_angles.xy = {-board_speed, 0}
			case {.Trick_SW, .Trick_S, .Trick_E}:
				skater_state.committed = .Lazer_Flip
				skater_state.jump.skate_angles.xy = {-board_speed, -board_speed}
			case {.Trick_WN, .Trick_N, .Trick_E}:
				skater_state.committed = .Nollie_Lazer_Flip
				skater_state.jump.skate_angles.xy = {board_speed, -board_speed}
			case {.Trick_ES, .Trick_S, .Trick_E}:
				skater_state.committed = .Tre_Inward_Heel
				skater_state.jump.skate_angles.xy = {board_speed, -board_speed}
			case {.Trick_NE, .Trick_N, .Trick_E}:
				skater_state.committed = .Nollie_Tre_Inward_Heel
				skater_state.jump.skate_angles.xy = {-board_speed, -board_speed}
			case {.Trick_SW, .Trick_S, .Trick_W}:
				skater_state.committed = .Tre_Hard_Flip
				skater_state.jump.skate_angles.xy = {-board_speed, board_speed}
			case {.Trick_WN, .Trick_N, .Trick_W}:
				skater_state.committed = .Nollie_Tre_Hard_Flip
				skater_state.jump.skate_angles.xy = {board_speed, board_speed}
			}
		}

		if skater.timer > state.config.data.tricks.trick_commit_delay {
			#partial switch skater_state.trick_buf.buf[0] {
			case .Trick_WN, .Trick_N, .Trick_NE:
				skater_state.committed = .Nollie
			case .Trick_ES, .Trick_S, .Trick_SW:
				skater_state.committed = .Ollie
			}
		}
	}

	{ 	// simulation
		skater_state.jump.skate_angles.zw += dt * skater_state.jump.skate_angles.xy

		apply_physics(state, inputs, skater, dt)
		apply_velocity(state, inputs, skater, dt)
		is_touching_a_floor := apply_collisions(state, skater)
		if is_touching_a_floor {
			{ 	// check board position
				deg := linalg.floor(linalg.abs(rl.RAD2DEG * skater_state.jump.skate_angles.zw))
				delta := state.config.data.landing.board_angle_snap_deg
				switch int(deg.x) % 360 {
				case 360 - delta ..= 360, 0 ..= delta, 180 - delta ..= 180 + delta:
					skater_state.jump.skate_angles.z = 0
				case:
					reset_skater(skater)
					return nil
				}
				switch int(deg.y) % 360 {
				case 360 - delta ..= 360, 0 ..= delta:
					skater_state.jump.skate_angles.w = 0
				case:
					reset_skater(skater)
					return nil
				}
			}

			skater.vel = linalg.dot(skater.vel, skater.look_dir) * skater.look_dir

			landing_state := Skater_State_Landing {
				jump           = skater_state.jump,
				landing_factor = skater.timer * state.config.data.landing.landing_duration_scale,
			}
			return landing_state
		}
	}

	return nil
}

update_skater_landing :: proc(
	state: ^State,
	inputs: Input_State,
	dt: f32,
	skater: ^Skater,
) -> Maybe(Skater_State) {
	skater_state := &skater.state.(Skater_State_Landing)

	skater.timer += dt
	if skater.timer > skater_state.landing_factor {
		return Skater_State_Idle{}
	}

	{ 	// simulation
		if check(state, inputs, skater.idx, .Cycle_Play_Mode, .Pressed) {
			return Skater_State_Ghost{}
		}

		apply_physics(state, inputs, skater, dt)
		snap(skater)
		apply_velocity(state, inputs, skater, dt)
		is_touching_a_floor := apply_collisions(state, skater)
		if !is_touching_a_floor do return Skater_State_Dropping{}
	}

	return nil
}

update_skater_dropping :: proc(
	state: ^State,
	inputs: Input_State,
	dt: f32,
	skater: ^Skater,
) -> Maybe(Skater_State) {
	skater.timer += dt

	if check(state, inputs, skater.idx, .Cycle_Play_Mode, .Pressed) {
		return Skater_State_Ghost{}
	}


	{ 	// simulation
		apply_physics(state, inputs, skater, dt)
		apply_velocity(state, inputs, skater, dt)
		is_touching_a_floor := apply_collisions(state, skater)
		if is_touching_a_floor {
			return Skater_State_Idle{}
		} else if skater.timer > state.config.data.movement.drop_time_before_airborne {
			return Skater_State_Airborne{}
		}
	}

	return nil
}

update_skater_ghost :: proc(
	state: ^State,
	inputs: Input_State,
	dt: f32,
	skater: ^Skater,
) -> Maybe(Skater_State) {
	if check(state, inputs, skater.idx, .Cycle_Play_Mode, .Pressed) {
		pos, look_dir := skater.pos, skater.look_dir
		reset_skater(skater)
		skater.pos, skater.look_dir = pos, look_dir
		return Skater_State_Idle{}
	}

	z_dir: f32
	if check(state, inputs, skater.idx, .Up, .Down) do z_dir = +1
	if check(state, inputs, skater.idx, .Down, .Down) do z_dir = -1
	if z_dir != 0 {
		skater.pos.z += z_dir * 5 * dt
	}
	steer_dir: f32
	if check(state, inputs, skater.idx, .Left, .Down) do steer_dir = -1
	if check(state, inputs, skater.idx, .Right, .Down) do steer_dir = +1
	angle_change := steer_dir * dt * state.config.data.movement.airborne_steer_speed
	angle := angle_change + linalg.atan2(skater.look_dir.y, skater.look_dir.x)
	if angle < 0 do angle += 2 * math.PI
	skater.look_dir = rl.Vector3RotateByAxisAngle(rl.Vector3{1, 0, 0}, rl.Vector3{0, 0, 1}, angle)
	skater.look_dir = linalg.normalize(skater.look_dir)
	if check(state, inputs, skater.idx, .Push, .Down) {
		skater.pos += skater.look_dir * 8 * dt
	}

	return nil
}

//#endregion update

//#region simulation

steer :: proc(state: ^State, inputs: Input_State, skater: ^Skater, dt: f32) {
	steer_dir: f32
	if check(state, inputs, skater.idx, .Left, .Down) do steer_dir = -1
	if check(state, inputs, skater.idx, .Right, .Down) do steer_dir = +1

	if _, ok := skater.state.(Skater_State_Airborne); ok {
		angle_change := steer_dir * dt * state.config.data.movement.airborne_steer_speed
		angle := angle_change + linalg.atan2(skater.look_dir.y, skater.look_dir.x)
		if angle < 0 do angle += 2 * math.PI
		skater.look_dir = rl.Vector3RotateByAxisAngle(
			rl.Vector3{1, 0, 0},
			rl.Vector3{0, 0, 1},
			angle,
		)
		skater.look_dir = linalg.normalize(skater.look_dir)
	} else if steer_dir != 0 {
		speed := linalg.length(skater.vel) * state.config.data.movement.riding_steer_rate
		if speed == 0 do speed = state.config.data.movement.stopped_steer_speed

		angle_change := steer_dir * dt * speed

		mov_dir := get_mov_dir(skater)
		angle := angle_change + linalg.atan2(mov_dir.y, mov_dir.x)
		if angle < 0 do angle += 2 * math.PI

		if linalg.length(skater.vel) == 0 {
			skater.look_dir = rl.Vector3RotateByAxisAngle(
				rl.Vector3{1, 0, 0},
				rl.Vector3{0, 0, 1},
				angle,
			)
			skater.look_dir = linalg.normalize(skater.look_dir)
		} else {
			skater.vel = rl.Vector3RotateByAxisAngle(skater.vel, rl.Vector3{0, 0, 1}, angle_change)
		}
	}
}

get_mov_dir :: proc(skater: ^Skater) -> rl.Vector3 {
	return linalg.length(skater.vel) == 0 ? skater.look_dir : linalg.normalize(skater.vel)
}

snap :: proc(skater: ^Skater) {
	if linalg.length(skater.vel.xy) == 0 do return
	diff := linalg.dot(linalg.normalize(skater.vel.xy), linalg.normalize(skater.look_dir.xy))
	skater.look_dir = linalg.normalize(skater.vel * math.sign(diff))
}

apply_physics :: proc(state: ^State, inputs: Input_State, skater: ^Skater, dt: f32) {
	gravity := state.config.data.physics.gravity_falling
	if skater.vel.z >= 0 do gravity = state.config.data.physics.gravity_rising
	skater.vel -= rl.Vector3{0, 0, gravity * dt}

	if math.abs(linalg.length(skater.vel.xy)) > state.config.data.physics.friction_stop_threshold {
		friction_coeff := state.config.data.physics.friction
		if check(state, inputs, skater.idx, .Break, .Down) {
			friction_coeff *= state.config.data.physics.braking_multiplier
		}
		skater.vel = skater.vel - linalg.normalize(skater.vel) * friction_coeff * dt
	} else {
		skater.vel.xy = {0, 0}
	}

}

apply_velocity :: proc(state: ^State, inputs: Input_State, skater: ^Skater, dt: f32) {
	skater.vel.xy = rl.Vector2ClampValue(skater.vel.xy, 0, state.config.data.movement.max_speed)
	skater.pos += skater.vel * dt
}

apply_collisions :: proc(state: ^State, skater: ^Skater) -> (is_touching_a_floor: bool) {
	for &surface in state.surfaces {
		p := skater.pos - surface.o
		d := linalg.dot(p, surface.n)
		if math.abs(d) >= SKATER_RADIUS do continue
		pp := p - d * surface.n
		px := linalg.dot(pp, surface.u)
		if px < 0 || px > surface.w do continue
		py := linalg.dot(pp, surface.v)
		if py < 0 || py > surface.h do continue

		skater.pos += (SKATER_RADIUS - d) * surface.n
		skater.vel -= linalg.dot(skater.vel, surface.n) * surface.n
		if surface.n.z != 0 do is_touching_a_floor = true
	}
	return
}

find_grind_target :: proc(state: ^State, skater: ^Skater, surface: ^Surface) {
	for edge in surface.grind_edges {
		s := skater.pos - edge.a
		d := linalg.dot(s, linalg.normalize(edge.p))
		if d < 0 || d > linalg.length(edge.p) do continue
		d = linalg.dot(s, edge.n)
		if d < -SKATER_RADIUS || d > SKATER_RADIUS do continue
		fmt.println("grindin!")
	}
}

//#endregion simulation

//#region utils

reset_skater :: proc(skater: ^Skater) {
	skater.state = Skater_State_Idle{}
	skater.vel = {}
	skater.timer = 0
	skater.pos = skater.last_respawn_point.xyz
	angle := skater.last_respawn_point.a
	skater.look_dir = linalg.normalize(rl.Vector3({1, 1, 0}))
	if angle != 0 {
		skater.look_dir = rl.Vector3RotateByAxisAngle(skater.look_dir, {0, 0, 1}, angle)
	}
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

//#endregion utils

//#region old

gather_grind_trick :: proc(
	skater: ^Skater,
	skater_state: ^Skater_State_Grinding,
	inputs: Input_State,
) {
	buf: bit_set[Input_Action]
	for action in Input_Action.Trick_W ..= Input_Action.Trick_SW {
		if .Down in inputs.actions[action] {
			buf |= {action}
		}
	}

	switch buf {
	case {.Trick_N}:
		if math.abs(skater.look_dir.y) > math.abs(skater.look_dir.x) {
			skater_state.grind.trick = .Nose_Grind
		} else if skater.look_dir.x >= 0 {
			skater_state.grind.trick = .Nose_Blunt
		} else {
			skater_state.grind.trick = .Nose_Slide
		}
	case {.Trick_S}:
		if math.abs(skater.look_dir.y) > math.abs(skater.look_dir.x) {
			skater_state.grind.trick = .Five_O
		} else if skater.look_dir.x >= 0 {
			skater_state.grind.trick = .Tail_Slide
		} else {
			skater_state.grind.trick = .Blunt_Slide
		}
	}
}

// start_grinding :: proc(state: ^State, skater: ^Skater) {
// 	if skater_state, is_airborne := skater.state.(Skater_State_Airborne);
// 	   !is_airborne ||
// 	   skater_state.jump.height == 0 ||
// 	   skater_state.jump.start_pos.z >= skater.pos.z {
// 		return
// 	}
//
// 	for object, object_idx in state.objects {
// 		if object.kind == .Ramp do continue
//
// 		offset := SKATER_RADIUS
//
// 		in_bounds: [3]bool
// 		at_edge: [3]bit_set[enum u8 {
// 			lo,
// 			hi,
// 		}]
// 		for i in 0 ..< len(in_bounds) {
// 			{
// 				min := object.pos[i]
// 				max := object.pos[i] + object.size[i]
// 				in_bounds[i] = skater.pos[i] >= min && skater.pos[i] <= max
// 			}
// 			{
// 				min := object.pos[i] - offset
// 				max := object.pos[i] + offset
// 				if skater.pos[i] >= min && skater.pos[i] <= max do at_edge[i] |= {.lo}
// 			}
// 			{
// 				min := object.pos[i] + object.size[i] - offset
// 				max := object.pos[i] + object.size[i] + offset
// 				if skater.pos[i] >= min && skater.pos[i] <= max do at_edge[i] |= {.hi}
// 			}
// 		}
//
// 		if .hi not_in at_edge.z do continue
//
// 		if at_edge.x != {} {
// 			if in_bounds.y {
// 				new_state := Skater_State_Grinding{}
// 				new_state.grind.target_idx = object_idx
// 				// transition_state(state, skater, new_state)
// 				skater.pos.z = object.pos.z + object.size.z + SKATER_RADIUS
// 				skater.pos.x = object.pos.x
// 				if .hi in at_edge.x do skater.pos.x += object.size.x
// 				skater.vel.xz = 0
// 				skater.move_dir.xz = 0
// 				skater.move_dir = linalg.normalize(skater.move_dir)
// 				return
// 			}
// 		} else if at_edge.y != {} {
// 			if in_bounds.x {
// 				new_state := Skater_State_Grinding{}
// 				new_state.grind.target_idx = object_idx
// 				// transition_state(state, skater, new_state)
// 				skater.pos.z = object.pos.z + object.size.z + SKATER_RADIUS
// 				skater.pos.y = object.pos.y
// 				if .hi in at_edge.y do skater.pos.y += object.size.y
// 				skater.vel.yz = 0
// 				skater.move_dir.yz = 0
// 				skater.move_dir = linalg.normalize(skater.move_dir)
// 				return
// 			}
// 		}
// 	}
// }

// stop_grinding :: proc(state: ^State, skater: ^Skater) {
// 	skater_state, is_grinding := skater.state.(Skater_State_Grinding)
// 	if !is_grinding do return
// 	if skater_state.grind.target_idx < 0 do return
//
// 	i := skater.vel.x != 0 ? 0 : 1
// 	object := state.objects[skater_state.grind.target_idx]
// 	offset := SKATER_RADIUS
// 	min := object.pos[i] - offset
// 	max := object.pos[i] + object.size[i] + offset
// 	in_bounds := skater.pos[i] >= min && skater.pos[i] <= max
// 	if !in_bounds {
// 		// transition_state(state, skater, Skater_State_Airborne{})
// 	}
// }

//#endregion old
