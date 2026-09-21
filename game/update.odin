package game

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

		if check(state, inputs, skater.idx, .Reset, .Pressed) {
			reset_skater(&skater)
			continue
		}

		defer animation_tick(state, &skater)

		switch skater_state in skater.state {
		case Skater_State_Ghost:
			ghost_move(state, inputs, &skater, dt)
		case Skater_State_Grinding:
			move(state, inputs, &skater, dt)
			apply_velocity(state, inputs, &skater, dt)
			stop_grinding(state, &skater)
		case Skater_State_Idle,
		     Skater_State_Crouched,
		     Skater_State_Airborne,
		     Skater_State_Landing,
		     Skater_State_Dropping:
			steer(state, inputs, &skater, dt)
			move(state, inputs, &skater, dt)
			apply_physics(state, inputs, &skater, dt)
			apply_velocity(state, inputs, &skater, dt)
			start_grinding(state, &skater)
			if new_state, is_grinding := skater.state.(Skater_State_Grinding); is_grinding {
				gather_grind_trick(&skater, &new_state, inputs)
			} else {
				touching_a_surface := collisions(state, &skater)
				transition(state, inputs, &skater, dt, touching_a_surface)
			}
		}
	}
}

ghost_move :: proc(state: ^State, inputs: Input_State, skater: ^Skater, dt: f32) {
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
	skater.angle = angle_change + linalg.atan2(skater.look_dir.y, skater.look_dir.x)
	if skater.angle < 0 do skater.angle += 2 * math.PI
	skater.look_dir = rl.Vector3RotateByAxisAngle(
		rl.Vector3{1, 0, 0},
		rl.Vector3{0, 0, 1},
		skater.angle,
	)
	skater.look_dir = linalg.normalize(skater.look_dir)
	skater.move_dir = skater.look_dir
	if check(state, inputs, skater.idx, .Push, .Down) {
		skater.pos += skater.look_dir * 5 * dt
	}
}

steer :: proc(state: ^State, inputs: Input_State, skater: ^Skater, dt: f32) {
	steer_dir: f32
	if check(state, inputs, skater.idx, .Left, .Down) do steer_dir = -1
	if check(state, inputs, skater.idx, .Right, .Down) do steer_dir = +1

	if _, ok := skater.state.(Skater_State_Airborne); ok {
		angle_change := steer_dir * dt * state.config.data.movement.airborne_steer_speed
		skater.angle = angle_change + linalg.atan2(skater.look_dir.y, skater.look_dir.x)
		if skater.angle < 0 do skater.angle += 2 * math.PI
		skater.look_dir = rl.Vector3RotateByAxisAngle(
			rl.Vector3{1, 0, 0},
			rl.Vector3{0, 0, 1},
			skater.angle,
		)
		skater.look_dir = linalg.normalize(skater.look_dir)
	} else if steer_dir != 0 {
		speed := linalg.length(skater.vel) * state.config.data.movement.riding_steer_rate
		if speed == 0 do speed = state.config.data.movement.stopped_steer_speed

		angle_change := steer_dir * dt * speed

		skater.angle = angle_change + linalg.atan2(skater.move_dir.y, skater.move_dir.x)
		if skater.angle < 0 do skater.angle += 2 * math.PI
		skater.move_dir = rl.Vector3RotateByAxisAngle(
			rl.Vector3{1, 0, 0},
			rl.Vector3{0, 0, 1},
			skater.angle,
		)
		skater.move_dir = linalg.normalize(skater.move_dir)
		skater.vel = rl.Vector3RotateByAxisAngle(skater.vel, rl.Vector3{0, 0, 1}, angle_change)
	}

}

check_init_crouch :: proc(state: ^State, inputs: Input_State, skater: ^Skater) {
	for action in Input_Action.Trick_WN ..= Input_Action.Trick_SW {
		if check(state, inputs, skater.idx, action, .Pressed) {
			new_state := Skater_State_Crouched{}
			new_state.trick_buf.buf[0] = action
			new_state.trick_buf.len = 1
			transition_state(state, skater, new_state)
		}
	}
}

move :: proc(state: ^State, inputs: Input_State, skater: ^Skater, dt: f32) {
	switch &skater_state in skater.state {
	case Skater_State_Idle:
		if check(state, inputs, skater.idx, .Push, .Pressed) {
			skater.vel += skater.move_dir * state.config.data.movement.push_impulse
		} else {
			check_init_crouch(state, inputs, skater)
		}
	case Skater_State_Grinding:
		check_init_crouch(state, inputs, skater)
	case Skater_State_Crouched:
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
			if grind_state, ok := skater_state.prev_state.(Skater_State_Grinding); ok {
				height *= 0.6
				i := skater.vel.x != 0 ? 1 : 0
				mul: f32 = 0
				if check(state, inputs, skater.idx, .Left, .Down) {
					mul = 1
				} else if check(state, inputs, skater.idx, .Right, .Down) {
					mul = -1
				}
				mul *= math.sign(skater.move_dir[1 - i])
				if skater.vel.x != 0 do mul *= -1
				skater.vel[i] += 2 * mul
			}

			skater.vel.z += height
			transition_state(
				state,
				skater,
				Skater_State_Airborne {
					jump = Jump_State{height = skater.vel.z, start_pos = skater.pos},
				},
			)
		} else {
			skater.timer = math.min(
				skater.timer + dt * state.config.data.tricks.crouch_charge_rate,
				1,
			)
		}
	case Skater_State_Airborne:
		skater.timer += dt

		if skater_state.jump.height == 0 {
			break
		}

		if skater_state.committed != .None {
			for action in Input_Action.Trick_W ..= Input_Action.Trick_SW {
				if check(state, inputs, skater.idx, action, .Pressed) {
					skater_state.caught = true
					return
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

		if skater_state.trick_buf.len < 1 {
			break
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

		if skater_state.committed == .None &&
		   skater.timer > state.config.data.tricks.trick_commit_delay {
			#partial switch skater_state.trick_buf.buf[0] {
			case .Trick_WN, .Trick_N, .Trick_NE:
				skater_state.committed = .Nollie
			case .Trick_ES, .Trick_S, .Trick_SW:
				skater_state.committed = .Ollie
			}
		}
	case Skater_State_Landing:
		skater.timer -= dt
		if skater.timer <= 0 {
			transition_state(state, skater, Skater_State_Idle{})
		}

	case Skater_State_Dropping:
		skater.timer += dt
	case Skater_State_Ghost:
	}
}

apply_velocity :: proc(state: ^State, inputs: Input_State, skater: ^Skater, dt: f32) {
	skater.vel.xy = rl.Vector2ClampValue(skater.vel.xy, 0, state.config.data.movement.max_speed)
	skater.pos += skater.vel * dt
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
		skater.vel = skater.vel - skater.move_dir * friction_coeff * dt
	} else {
		skater.vel.xy = {0, 0}
	}

	if skater_state, is_airborne := &skater.state.(Skater_State_Airborne);
	   is_airborne && skater_state.caught {
		skater_state.jump.skate_angles.xy = {}
	} else if is_airborne && skater_state.jump.skate_angles.xy != {} {
		skater_state.jump.skate_angles.zw += dt * skater_state.jump.skate_angles.xy
	}
}


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

start_grinding :: proc(state: ^State, skater: ^Skater) {
	if skater_state, is_airborne := skater.state.(Skater_State_Airborne);
	   !is_airborne ||
	   skater_state.jump.height == 0 ||
	   skater_state.jump.start_pos.z >= skater.pos.z {
		return
	}

	for object, object_idx in state.objects {
		if object.kind == .Ramp do continue

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
				if skater.pos[i] >= min && skater.pos[i] <= max do at_edge[i] |= {.lo}
			}
			{
				min := object.pos[i] + object.size[i] - offset
				max := object.pos[i] + object.size[i] + offset
				if skater.pos[i] >= min && skater.pos[i] <= max do at_edge[i] |= {.hi}
			}
		}

		if .hi not_in at_edge.z do continue

		if at_edge.x != {} {
			if in_bounds.y {
				new_state := Skater_State_Grinding{}
				new_state.grind.target_idx = object_idx
				transition_state(state, skater, new_state)
				skater.pos.z = object.pos.z + object.size.z + skater.radius
				skater.pos.x = object.pos.x
				if .hi in at_edge.x do skater.pos.x += object.size.x
				skater.vel.xz = 0
				skater.move_dir.xz = 0
				skater.move_dir = linalg.normalize(skater.move_dir)
				return
			}
		} else if at_edge.y != {} {
			if in_bounds.x {
				new_state := Skater_State_Grinding{}
				new_state.grind.target_idx = object_idx
				transition_state(state, skater, new_state)
				skater.pos.z = object.pos.z + object.size.z + skater.radius
				skater.pos.y = object.pos.y
				if .hi in at_edge.y do skater.pos.y += object.size.y
				skater.vel.yz = 0
				skater.move_dir.yz = 0
				skater.move_dir = linalg.normalize(skater.move_dir)
				return
			}
		}
	}
}

stop_grinding :: proc(state: ^State, skater: ^Skater) {
	skater_state, is_grinding := skater.state.(Skater_State_Grinding)
	if !is_grinding do return
	if skater_state.grind.target_idx < 0 do return

	i := skater.vel.x != 0 ? 0 : 1
	object := state.objects[skater_state.grind.target_idx]
	offset := skater.radius
	min := object.pos[i] - offset
	max := object.pos[i] + object.size[i] + offset
	in_bounds := skater.pos[i] >= min && skater.pos[i] <= max
	if !in_bounds {
		transition_state(state, skater, Skater_State_Airborne{})
	}
}

collisions :: proc(state: ^State, skater: ^Skater) -> bool {
	touching_a_surface := false
	for &surface in state.surfaces {
		p := skater.pos - surface.o
		d := linalg.dot(p, surface.n)
		if math.abs(d) >= skater.radius do continue
		pp := p - d * surface.n
		px := linalg.dot(pp, surface.u)
		if px < 0 || px > surface.w do continue
		py := linalg.dot(pp, surface.v)
		if py < 0 || py > surface.h do continue
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
) {
	skater_fell := false
	defer if skater_fell do reset_skater(skater)

	if _, ok := skater.state.(Skater_State_Dropping); ok {
		if touching_a_surface {
			transition_state(state, skater, Skater_State_Idle{})
		} else if skater.timer > state.config.data.movement.drop_time_before_airborne {
			transition_state(state, skater, Skater_State_Airborne{})
		}
	}

	skater_state, is_airborne := &skater.state.(Skater_State_Airborne)

	if !is_airborne && !touching_a_surface {
		transition_state(state, skater, Skater_State_Dropping{})
	} else if is_airborne && touching_a_surface {
		defer transition_state(state, skater, Skater_State_Landing{})

		skater.vel = linalg.dot(skater.vel, skater.look_dir) * skater.look_dir

		{ 	// player position
			diff := linalg.dot(
				linalg.normalize(skater.move_dir.xy),
				linalg.normalize(skater.look_dir.xy),
			)
			skater.look_dir = skater.move_dir * math.sign(diff)
		}

		{ 	// board position
			deg := linalg.floor(linalg.abs(rl.RAD2DEG * skater_state.jump.skate_angles.zw))
			delta := state.config.data.landing.board_angle_snap_deg
			switch int(deg.x) % 360 {
			case 360 - delta ..= 360, 0 ..= delta, 180 - delta ..= 180 + delta:
				skater_state.jump.skate_angles.z = 0
			case:
				skater_fell = true
				return
			}
			switch int(deg.y) % 360 {
			case 360 - delta ..= 360, 0 ..= delta:
				skater_state.jump.skate_angles.w = 0
			case:
				skater_fell = true
				return
			}
		}

	}

	skater_fell = skater.pos.z < state.config.data.landing.death_plane_z
	return
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
		skater := &state.skaters[state.target_skater_idx]
		if _, is_ghost := skater.state.(Skater_State_Ghost); is_ghost {
			transition_state(state, skater, Skater_State_Idle{})
		} else {
			transition_state(state, skater, Skater_State_Ghost{})
		}
		pos, look_dir, move_dir := skater.pos, skater.look_dir, skater.move_dir
		reset_skater(skater)
		skater.pos, skater.look_dir, skater.move_dir = pos, look_dir, move_dir
	}
}

reset_skater :: proc(skater: ^Skater) {
	skater.state = Skater_State_Idle{}
	skater.radius = SKATER_RADIUS
	skater.vel = rl.Vector3{}
	skater.timer = 0
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
	if skater.state == new_state do return
	skater.state = new_state

	if skater_state, is_landing := &skater.state.(Skater_State_Landing); is_landing {
		skater_state.landing_factor =
			skater.timer * state.config.data.landing.landing_duration_scale
	}

	skater.timer = 0
}
