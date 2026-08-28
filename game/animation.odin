package game

import "core:math"
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
}

animation_configs := [Animation_State]Animation_Config {
	.Idle = {asset = .Ride, frame_count = 1},
	.Crouched = {asset = .Duck, frame_count = 3},
	.Falling = {asset = .Air, frame_count = 1},
	.Jumping = {asset = .Air, frame_count = 7},
	.Tricking = {asset = .Air, frame_count = 7, initial_idx = {0, 14}},
	.Landing = {asset = .Land, frame_count = 6},
	.Ghost = {asset = .Onspot, frame_count = 1, initial_idx = {0, 9}},
	.Grinding = {asset = .Allgrind2, frame_count = 1},
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
	if state.target_skater_idx == skater_idx && state.play_mode == .Ghost {
		anim_state = .Ghost
	} else {
		switch skater.state {
		case .Idle, .Crouched:
			if skater.grind_target_idx > -1 {
				anim_state = .Grinding
			} else {
				anim_state = skater.state == .Crouched ? .Crouched : .Idle
			}
		case .Dropping:
			anim_state = .Idle
		case .Airborne:
			if skater.jump_height <= 0 {
				anim_state = .Falling
			} else if skater.skate_angles.zw == {} {
				anim_state = .Jumping
			} else {
				anim_state = .Tricking
			}
		case .Landing:
			anim_state = .Landing
		}
	}
	if anim_state != animation.state {
		animation.state = anim_state
		animation.progress = {}
	}
}

// value needs to be normalized between 0 and 1
animation_tick :: proc(state: ^State, skater: ^Skater) {
	animation := &skater.animation
	animation_update_state(state, skater, skater.idx, animation)
	config := animation_configs[animation.state]

	#partial switch skater.animation.state {
	case .Grinding:
		switch skater.grind_buffer {
		case {.Trick_S}:
			animation.progress.idx.x = 1
		case {.Trick_N}:
			animation.progress.idx.x = 4
		case:
			animation.progress.idx.x = 0
		}
	case:
		animation.progress.idx.x = skater_rot_to_sprite_idx(skater)
	}

	#partial switch skater.animation.state {
	case .Grinding:
		if skater.vel.y != 0 {
			animation.progress.idx.y = skater.look_dir.y > 0 ? 0 : 1
		} else {
			animation.progress.idx.y = skater.look_dir.x > 0 ? 2 : 3
		}
	case .Idle, .Ghost:
		animation.progress.idx.y = 0
	case .Crouched:
		v := skater.timer[skater.state]
		animation.progress.idx.y = value_to_frame(v, config)
		// nollie tricks
		if skater.trick_buffer_len >= 0 && skater.trick_buffer[0] < .Trick_ES {
			animation.progress.idx.y += config.frame_count
		}
	case .Falling:
		animation.progress.idx.y = 5
	case .Jumping, .Tricking:
		v := 1 - ((skater.vel.z + skater.jump_height) / (2 * skater.jump_height))
		animation.progress.idx.y = value_to_frame(v, config)
	case .Landing:
		x := skater.timer[.Airborne] * state.config.data.landing.landing_duration_scale
		v := -skater.timer[.Landing] / x + 1
		animation.progress.idx.y = value_to_frame(v, config)
	}

	animation.progress.idx += config.initial_idx
}

value_to_frame :: proc(value: f32, config: Animation_Config) -> f32 {
	res := math.round(value * config.frame_count)
	return math.clamp(res, 0, config.frame_count - 1)
}

skater_rot_to_sprite_idx :: proc(skater: ^Skater) -> f32 {
	look_angle := rl.Vector2Angle({1, 0}, skater.look_dir.xy)
	if skater.look_dir.y < 0 do look_angle = 2 * math.PI - look_angle
	return math.round((look_angle * 32) / (2 * math.PI))
}
