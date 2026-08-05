package game
import "core:c"
import "core:fmt"
import "core:math"
import "core:math/linalg"
import "core:slice"
import rl "vendor:raylib"

render :: proc(state: ^State) {
	rl.BeginShaderMode(state.shaders[.Customize])
	defer rl.EndShaderMode()

	rl.SetShaderValueTexture(state.shaders[.Customize], state.palette.loc, state.palette.tex)

	screen := rl.Vector2{f32(rl.GetScreenWidth()), f32(rl.GetScreenHeight())}
	state.offset = screen / 2

	bg := rl.DARKGRAY
	if state.color_mode == .Light {
		bg = rl.WHITE
	}

	rl.ClearBackground(bg)

	rl.DrawFPS(0, 0)

	target := &state.skaters[state.target_skater_idx]

	// for &surface in state.surfaces {
	// 	offset := surface.o - target.pos
	// 	draw_surface(state, &surface, offset)
	// }

	for &object in state.objects {
		offset := object.pos - target.pos
		draw_object(state, &object, offset)
	}

	font_size := state.config.data.ui.font_size
	if target.trick_committed != .None {
		str := fmt.ctprintf("%s", target.trick_committed)
		measure := rl.MeasureText(str, font_size)
		rl.DrawText(
			str,
			(rl.GetScreenWidth() - measure) / 2,
			(rl.GetScreenHeight() - font_size) / 2 - i32(state.config.data.sprite.frame_size),
			font_size,
			rl.ORANGE,
		)
	}

	for &skater, skater_idx in state.skaters {
		offset := skater.pos - target.pos
		draw_board(state, &skater, offset)
		draw_skater(state, &skater, skater_idx, offset)
	}
}

draw_object :: proc(state: ^State, object: ^Object, offset: rl.Vector3) {
	switch object.kind {
	case .Box:
		bg, outline: rl.Color
		switch object.mat {
		case .Concrete:
			bg = {124, 122, 115, 255}
			outline = {84, 82, 76, 255}
		case .Wood:
			bg = {150, 111, 74, 255}
			outline = {107, 79, 53, 255}
		case .Brick:
			bg = {178, 89, 68, 255}
			outline = {130, 63, 48, 255}
		}

		points: [4]rl.Vector3
		projected: [4]rl.Vector2
		{ 	// top face
			slice.fill(points[:], offset)
			points[0].z += object.size.z
			points[1].yz += object.size.yz
			points[2] += object.size
			points[3].xz += object.size.xz
			for p, i in points {projected[i] = project(p, state)}
			// for p in projected {rl.DrawCircleV(p, 2, rl.RED)}
			rl.DrawTriangleFan(&projected[0], 4, bg)
			for i in 0 ..< 4 {rl.DrawLineEx(projected[i], projected[(i + 1) % 4], 2, outline)}
		}
		{ 	// side left
			slice.fill(points[:], offset)
			points[0].yz += object.size.yz
			points[1].y += object.size.y
			points[2].xy += object.size.xy
			points[3] += object.size
			for p, i in points {projected[i] = project(p, state)}
			// for p in projected {rl.DrawCircleV(p, 2, rl.PINK)}
			rl.DrawTriangleFan(&projected[0], 4, bg)
			for i in 0 ..< 4 {rl.DrawLineEx(projected[i], projected[(i + 1) % 4], 2, outline)}
		}
		{ 	// side right
			slice.fill(points[:], offset)
			points[0] += object.size
			points[1].xy += object.size.xy
			points[2].x += object.size.x
			points[3].xz += object.size.xz
			for p, i in points {projected[i] = project(p, state)}
			// for p in projected {rl.DrawCircleV(p, 2, rl.GREEN)}
			rl.DrawTriangleFan(&projected[0], 4, bg)
			for i in 0 ..< 4 {rl.DrawLineEx(projected[i], projected[(i + 1) % 4], 2, outline)}
		}
	case .Ramp:
		panic("not implemented")
	}
}

project :: proc(point: rl.Vector3, state: ^State) -> rl.Vector2 {
	cell_size := state.config.data.camera.cell_size
	if state.drawing_mode == .Top_Down {
		return point.xy * cell_size + state.offset
	}
	if state.drawing_mode == .Side {
		return rl.Vector2{-point.y, -point.z} * cell_size + state.offset
	}
	return PRO_MATRIX * point * cell_size + state.offset
}

PRO_MATRIX :: matrix[2, 3]f32{
	1, -1, 0,
	0.5, 0.5, -1,
}

draw_skater :: proc(state: ^State, skater: ^Skater, skater_idx: int, offset: rl.Vector3) {
	frame_size := state.config.data.sprite.frame_size
	sprite_pos := skater.animation.progress.idx * frame_size
	config := animation_configs[skater.animation.state]
	target_pos := project(offset, state) - frame_size / 2

	rl.DrawTexturePro(
		state.skater_assets[config.asset],
		{sprite_pos.x, sprite_pos.y, frame_size, frame_size},
		{target_pos.x, target_pos.y, frame_size, frame_size},
		{0, 0},
		0,
		rl.Color{u8(skater_idx + 1), 0, 0, 0},
	)
}

draw_board :: proc(state: ^State, skater: ^Skater, offset: rl.Vector3) {
	if skater.state != .Airborne {return}
	if skater.skate_angles.zw == {} {return}

	rad := skater.skate_angles.zw
	rad.x += linalg.atan2(skater.look_dir.y, skater.look_dir.x)
	deg := rad * rl.RAD2DEG
	sign := linalg.sign(deg)
	orientation := linalg.mod(deg * sign, 360)
	if sign.x < 0 {orientation.x = 360 - orientation.x}
	if sign.y < 0 {orientation.y = 360 - orientation.y}
	asset_idx := math.round(orientation.x * BOARD_ASSET_COUNT / 360)
	asset_idx = math.clamp(asset_idx, 0, BOARD_ASSET_COUNT - 1)

	frame_size: f32 = 50
	target_pos := project(offset, state) - frame_size / 2
	target_pos.y += state.config.data.sprite.board_y_offset

	sprite_idx: rl.Vector2
	sprite_idx.x = math.round(orientation.y * 21 / 360)
	sprite_idx.x = math.clamp(sprite_idx.x, 0, 20)
	sprite_idx.y = math.ceil(orientation.x * 5 / 360)
	sprite_idx.y = math.clamp(sprite_idx.y, 0, 4)
	sprite_pos := sprite_idx * 50

	rl.DrawTexturePro(
		state.board_assets[int(asset_idx)],
		{sprite_pos.x, sprite_pos.y, frame_size, frame_size},
		{target_pos.x, target_pos.y, frame_size, frame_size},
		{0, 0},
		0,
		rl.WHITE,
	)
}

draw_surface :: proc(state: ^State, surface: ^Surface, offset: rl.Vector3) {
	if state.show_normals {
		rl.DrawCircleV(project(offset, state), 4, rl.BLUE)
		rl.DrawLineEx(project(offset, state), project(surface.n + offset, state), 2, rl.RED)
		rl.DrawLineEx(project(offset, state), project(surface.u + offset, state), 2, rl.GREEN)
		rl.DrawLineEx(project(offset, state), project(surface.v + offset, state), 2, rl.YELLOW)
	}

	for col in 0 ..= surface.w {
		start := surface.u * col + offset
		end := start + surface.v * surface.h
		rl.DrawLineEx(project(start, state), project(end, state), 1.1, rl.Fade(rl.LIGHTGRAY, 0.5))
	}
	for row in 0 ..= surface.h {
		start := surface.v * row + offset
		end := start + surface.u * surface.w
		rl.DrawLineEx(project(start, state), project(end, state), 1.1, rl.Fade(rl.LIGHTGRAY, 0.5))
	}
}
