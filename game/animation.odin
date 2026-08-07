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
}

animation_configs := [Animation_State]Animation_Config {
	.Idle = {asset = .Ride, frame_count = 1},
	.Crouched = {asset = .Duck, frame_count = 3},
	.Falling = {asset = .Air, frame_count = 1},
	.Jumping = {asset = .Air, frame_count = 7},
	.Tricking = {asset = .Air, frame_count = 7, initial_idx = {0, 14}},
	.Landing = {asset = .Land, frame_count = 6},
	.Ghost = {asset = .Onspot, frame_count = 1, initial_idx = {0, 8}},
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
		case .Idle:
			anim_state = .Idle
		case .Crouched:
			anim_state = .Crouched
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
animation_tick :: proc(state: ^State, skater: ^Skater, skater_idx: int, value: f32) {
	animation := &skater.animation
	animation_update_state(state, skater, skater_idx, animation)
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
	case .Idle, .Ghost:
		return 0
	case .Crouched:
		return skater.timer[.Crouched]
	case .Falling:
		return 5
	case .Jumping, .Tricking:
		return 1 - ((skater.vel.z + skater.jump_height) / (2 * skater.jump_height))
	case .Landing:
		x := skater.timer[.Airborne] * state.config.data.landing.landing_duration_scale
		return -skater.timer[.Landing] / x + 1
	}
	return 0
}

skater_rot_to_sprite_idx :: proc(skater: ^Skater) -> f32 {
	look_angle := rl.Vector2Angle({1, 0}, skater.look_dir.xy)
	if skater.look_dir.y < 0 {look_angle = 2 * math.PI - look_angle}
	return math.round((look_angle * 32) / (2 * math.PI))
}
