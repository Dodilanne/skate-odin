package game

import "core:encoding/json"
import "core:log"
import "core:os"
import "core:time"

Movement_Config :: struct {
	push_impulse:              f32,
	riding_steer_rate:         f32,
	stopped_steer_speed:       f32,
	airborne_steer_speed:      f32,
	max_speed:                 f32,
	drop_time_before_airborne: f32,
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
	board_angle_snap_deg:   int,
	landing_duration_scale: f32,
	death_plane_z:          f32,
}

Camera_Config :: struct {
	cell_size: f32,
}

Sprite_Config :: struct {
	frame_size:      f32,
	skater_y_offset: f32,
	board_y_offset:  f32,
}

UI_Config :: struct {
	font_size: i32,
}

Time_Of_Day :: enum u8 {
	Day,
	Night,
}

Customization_Config :: struct {
	palettes:    [dynamic; MAX_SKATERS][COLORS_PER_PALETTE][3]f32,
	sky_color:   [Time_Of_Day][4]f32,
	time_of_day: Time_Of_Day,
}

Objects_Config :: struct {
	colors: [Object_Material]struct {
		bg:      [3]f32,
		outline: [3]f32,
	},
}

Config_Data :: struct {
	movement:      Movement_Config,
	physics:       Physics_Config,
	tricks:        Trick_Config,
	landing:       Landing_Config,
	camera:        Camera_Config,
	sprite:        Sprite_Config,
	ui:            UI_Config,
	objects:       Objects_Config,
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
			drop_time_before_airborne = 0.5,
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
		landing = {board_angle_snap_deg = 40, landing_duration_scale = 0.4, death_plane_z = -10},
		camera = {cell_size = 32},
		sprite = {frame_size = 75, skater_y_offset = 10, board_y_offset = 5},
		ui = {font_size = 20},
		objects = {
			colors = {
				.Concrete = {bg = {124, 122, 115}, outline = {84, 82, 76}},
				.Wood = {bg = {150, 111, 74}, outline = {107, 79, 53}},
				.Brick = {bg = {178, 89, 68}, outline = {130, 63, 48}},
			},
		},
		customization = {
			palettes = {
				{
					{23.0, 23.0, 23.0},
					{68.0, 135.0, 28.0},
					{88.0, 56.0, 6.0},
					{225.0, 169.0, 137.0},
					{220.0, 220.0, 220.0},
					{1.0, 1.0, 1.0},
				},
			},
			sky_color = {.Day = {107, 164, 230, 20}, .Night = {66.0, 70.0, 86.0, 100}},
			time_of_day = .Night,
		},
	}

}

// Palette of the source sprite sheets
src_palette :: proc() -> [COLORS_PER_PALETTE][3]f32 {
	return {
		{225, 230, 227},
		{107, 164, 230},
		{88, 56, 6},
		{225, 169, 137},
		{37, 37, 37},
		{1, 1, 1},
	}
}

Load_Config_Error :: union #shared_nil {
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

	data := json.marshal(config.data, {}, context.temp_allocator) or_return
	return os.write_entire_file(path, data)
}


check_and_update :: proc(
	config: ^Config,
	path: string = DEFAULT_CONFIG_PATH,
) -> (
	reloaded: bool,
	err: Load_Config_Error,
) {
	if !os.exists(path) {
		log.errorf("Config file doesn't exist, writing current config to file")
		data := json.marshal(config.data, {}, context.temp_allocator) or_return
		return false, os.write_entire_file(path, data)
	}

	info := os.stat(path, context.temp_allocator) or_return
	if time.diff(info.modification_time, config.last_updated_at) < 0 {
		return true, load_config_from_file(config, path)
	}

	return false, nil
}


DEFAULT_CONFIG_PATH :: "config.json"
