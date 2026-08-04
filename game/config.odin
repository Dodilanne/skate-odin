package game

import "core:encoding/json"
import "core:fmt"
import "core:os"
import "core:time"
import rl "vendor:raylib"

Movement_Config :: struct {
	push_impulse:         f32,
	riding_steer_rate:    f32,
	stopped_steer_speed:  f32,
	airborne_steer_speed: f32,
	max_speed:            f32,
}

Physics_Config :: struct {
	gravity_rising:          f32,
	gravity_falling:         f32,
	friction:                f32,
	braking_multiplier:      f32,
	friction_stop_threshold: f32,
}

Trick_Config :: struct {
	crouch_charge_rate: f32,
	min_jump_height:    f32,
	jump_height_scale:  f32,
	board_spin_speed:   f32,
	half_spin_divisor:  f32,
	trick_commit_delay: f32,
}

Landing_Config :: struct {
	facing_alignment_min_dot: f32,
	board_angle_snap_deg:     int,
	landing_duration_scale:   f32,
	death_plane_z:            f32,
}

Camera_Config :: struct {
	cell_size: f32,
}

Sprite_Config :: struct {
	frame_size:     f32,
	board_y_offset: f32,
}

UI_Config :: struct {
	font_size: i32,
}

Customization_Config :: struct {
	skater_colors: [6][3]i32,
}

Config_Data :: struct {
	movement:      Movement_Config,
	physics:       Physics_Config,
	tricks:        Trick_Config,
	landing:       Landing_Config,
	camera:        Camera_Config,
	sprite:        Sprite_Config,
	ui:            UI_Config,
	customization: Customization_Config,
}

Config :: struct {
	last_updated_at: time.Time,
	data:            Config_Data,
}

init_config_with_defaults :: proc(config: ^Config) {
	config.data = {
		movement = {
			push_impulse = 1,
			riding_steer_rate = 0.2,
			stopped_steer_speed = 2,
			airborne_steer_speed = 6,
			max_speed = 8,
		},
		physics = {
			gravity_rising = 10,
			gravity_falling = 20,
			friction = 0.5,
			braking_multiplier = 10,
			friction_stop_threshold = 0.1,
		},
		tricks = {
			crouch_charge_rate = 1.8,
			min_jump_height = 3,
			jump_height_scale = 6,
			board_spin_speed = 12,
			half_spin_divisor = 2,
			trick_commit_delay = 0.3,
		},
		landing = {
			facing_alignment_min_dot = 0.85,
			board_angle_snap_deg = 40,
			landing_duration_scale = 0.4,
			death_plane_z = -10,
		},
		camera = {cell_size = 32},
		sprite = {frame_size = 75, board_y_offset = 27},
		ui = {font_size = 20},
		customization = {
			skater_colors = [6][3]i32 {
				{230, 41, 55},
				{0, 228, 48},
				{0, 121, 241},
				{253, 249, 0},
				{255, 161, 0},
				{200, 122, 255},
			},
		},
	}
}

Load_Config_Error :: union {
	os.Error,
	json.Marshal_Error,
	json.Unmarshal_Error,
}

load_config_from_file :: proc(
	config: ^Config,
	path: string = DEFAULT_CONFIG_PATH,
) -> Load_Config_Error {
	init_config_with_defaults(config)

	config.last_updated_at = time.now()

	if os.exists(path) {
		data := os.read_entire_file(path, context.temp_allocator) or_return
		return json.unmarshal(data, &config.data)
	}

	data, err := json.marshal(config.data)
	if err != nil {
		fmt.eprintln(err)
		return err
	}
	return os.write_entire_file(path, data)
}

check_and_update :: proc(
	config: ^Config,
	path: string = DEFAULT_CONFIG_PATH,
) -> (
	err: Load_Config_Error,
) {
	info := os.stat(path, context.temp_allocator) or_return
	if time.diff(info.modification_time, config.last_updated_at) < 0 {
		return load_config_from_file(config, path)
	}
	return
}


DEFAULT_CONFIG_PATH :: "config.json"
