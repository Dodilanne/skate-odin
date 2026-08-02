package game

import "core:math"
import rl "vendor:raylib"

Animation_State :: enum u8 {
	Idle,
	Crouched,
	Falling,
	Jumping,
	Landing,
}

animation_configs := [Animation_State]Animation_Config {
	.Idle = {asset = .Ride, frame_count = 1},
	.Crouched = {asset = .Duck, frame_count = 3},
	.Falling = {asset = .Air, frame_count = 1, initial_idx = {0, 14}},
	.Jumping = {asset = .Air, frame_count = 7, initial_idx = {0, 14}},
	.Landing = {asset = .Land, frame_count = 6},
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

animation_update_state :: proc(skater: ^Skater, animation: ^Animation) {
	state: Animation_State
	switch skater.state {
	case .Idle:
		state = .Idle
	case .Crouched:
		state = .Crouched
	case .Airborne:
		if skater.jump_height > 0 {
			state = .Jumping
		} else {
			state = .Falling
		}
	case .Landing:
		state = .Landing
	}
	if state != animation.state {
		animation.state = state
		animation.progress = {}
	}
}

// value needs to be normalized between 0 and 1
animation_tick :: proc(skater: ^Skater, value: f32) {
	animation := &skater.animation
	animation_update_state(skater, animation)
	config := animation_configs[animation.state]

	animation.progress.idx.x = skater_rot_to_sprite_idx(skater)

	animation.progress.idx.y = math.round(value * config.frame_count)
	animation.progress.idx.y = math.clamp(animation.progress.idx.y, 0, config.frame_count - 1)

	// nollie tricks
	if skater.trick_buffer_len >= 0 && skater.trick_buffer[0] < .Trick_ES {
		animation.progress.idx.y += config.frame_count
	}

	animation.progress.idx += config.initial_idx
}

animation_get_value :: proc(skater: ^Skater, state: ^State) -> f32 {
	switch skater.animation.state {
	case .Idle:
		return 0
	case .Crouched:
		return skater.timer[.Crouched]
	case .Falling:
		return 5
	case .Jumping:
		return 1 - ((skater.vel.z + skater.jump_height) / (2 * skater.jump_height))
	case .Landing:
		x := skater.timer[.Airborne] * state.config.landing.landing_duration_scale
		return -skater.timer[.Landing] / x + 1
	}
	return 0
}
