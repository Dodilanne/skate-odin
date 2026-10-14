package game

import "core:math"
import "core:math/linalg"
import rl "vendor:raylib"

Animation_State :: enum u8 {
	Idle,
	Crouched,
	Falling,
	Jumping,
	Tricking,
	Landing,
	Ghost,
	Grinding,
	Manualing,
}

animation_configs := [Animation_State]Animation_Config {
	.Idle = {asset = .Ride, frame_count = 3},
	.Crouched = {asset = .Duck, frame_count = 3},
	.Falling = {asset = .Air, frame_count = 1},
	.Jumping = {asset = .Air, frame_count = 7},
	.Tricking = {asset = .Air, frame_count = 7, initial_idx = {0, 14}},
	.Landing = {asset = .Land, frame_count = 6},
	.Ghost = {asset = .Onspot, frame_count = 1, initial_idx = {0, 9}},
	.Grinding = {asset = .Allgrind2, frame_count = 1},
	.Manualing = {asset = .Manual, frame_count = 1},
}

Animation_Config :: struct {
	asset:       Skater_Asset,
	frame_count: f32,
	initial_idx: rl.Vector2,
}

Animation_Progress :: struct {
	idx: rl.Vector2,
}

Animation :: struct {
	state:    Animation_State,
	progress: Animation_Progress,
}

animation_update_state :: proc(
	state: ^State,
	skater: ^Skater,
	skater_idx: int,
	animation: ^Animation,
) {
	anim_state: Animation_State
	switch skater_state in skater.state {
	case Skater_State_Ghost:
		anim_state = .Ghost
	case Skater_State_Idle, Skater_State_Dropping:
		anim_state = .Idle
	case Skater_State_Crouched:
		anim_state = .Crouched
	case Skater_State_Grinding:
		anim_state = .Grinding
	case Skater_State_Manualing:
		anim_state = .Manualing
	case Skater_State_Airborne:
		if skater_state.jump.height <= 0 {
			anim_state = .Falling
		} else if skater_state.jump.skate_angles.zw == {} {
			anim_state = .Jumping
		} else {
			anim_state = .Tricking
		}
	case Skater_State_Landing:
		anim_state = .Landing
	}

	if anim_state != animation.state {
		animation.state = anim_state
		animation.progress = {}
	}
}

// value needs to be normalized between 0 and 1
animation_tick :: proc(state: ^State, skater: ^Skater) {
	animation := &skater.anim
	animation_update_state(state, skater, skater.idx, animation)
	config := animation_configs[animation.state]

	#partial switch skater_state in skater.state {
	case Skater_State_Grinding:
		animation.progress.idx.x = f32(skater_state.grind.trick)
	case:
		animation.progress.idx.x = skater_rot_to_sprite_idx(skater)
	}

	switch skater_state in skater.state {
	case Skater_State_Grinding:
		i := skater_state.grind.target.i
		v := linalg.normalize(skater.vel)
		if linalg.dot(skater.look_dir, v) < 0 {
			v = -v
		}
		switch {
		case i.x < 0:
			animation.progress.idx.y = 0 if v.y > 0 else 1
		case i.y > 0:
			animation.progress.idx.y = 2 if v.x > 0 else 3
		case i.x > 0:
			animation.progress.idx.y = 4 if v.y < 0 else 5
		case i.y < 0:
			animation.progress.idx.y = 6 if v.x < 0 else 7
		}
	case Skater_State_Idle:
		if skater.steer_timer == 0 {
			animation.progress.idx.y = 3
			break
		}
		animation.progress.idx.y, _ = value_to_frame(math.abs(skater.steer_timer), config)
		sign := math.sign(skater.steer_timer)
		if linalg.dot(skater.look_dir, linalg.normalize(skater.vel)) < 0 {
			sign = -sign
		}
		if sign > 0 {
			animation.progress.idx.y += 4
		}
	case Skater_State_Ghost, Skater_State_Dropping:
		animation.progress.idx.y = 0
	case Skater_State_Manualing:
		animation.progress.idx.y = skater_state.nose ? 5 : 0
	case Skater_State_Crouched:
		v := skater.timer
		anim_done: bool
		animation.progress.idx.y, anim_done = value_to_frame(v, config)
		if skater_state.trick_buf.len <= 0 do break

		first_trick_input := skater_state.trick_buf.buf[0]
		if first_trick_input < .Trick_ES {
			animation.progress.idx.y += config.frame_count
		}

		if anim_done {
			#partial switch first_trick_input {
			case .Trick_ES:
				animation.progress.idx.y = 6
			case .Trick_SW:
				animation.progress.idx.y = 7
			case .Trick_NE:
				animation.progress.idx.y = 8
			case .Trick_WN:
				animation.progress.idx.y = 9
			}
		}
	case Skater_State_Airborne:
		if skater.anim.state == .Falling {
			animation.progress.idx.y = 5
		} else {
			v := 1 - ((skater.vel.z + skater_state.jump.height) / (2 * skater_state.jump.height))
			animation.progress.idx.y, _ = value_to_frame(v, config)
		}
	case Skater_State_Landing:
		x := skater_state.landing_factor
		v := skater.timer / x
		animation.progress.idx.y, _ = value_to_frame(v, config)
	}

	animation.progress.idx += config.initial_idx
}

value_to_frame :: proc(value: f32, config: Animation_Config) -> (frame: f32, done: bool) {
	res := math.round(value * config.frame_count)
	max := config.frame_count - 1
	frame = math.clamp(res, 0, max)
	return frame, frame == max
}

skater_rot_to_sprite_idx :: proc(skater: ^Skater, step: f32 = 32) -> f32 {
	look_angle := rl.Vector2Angle({1, 0}, skater.look_dir.xy)
	if skater.look_dir.y < 0 do look_angle = 2 * math.PI - look_angle
	return math.round((look_angle * step) / (2 * math.PI))
}
