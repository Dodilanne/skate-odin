package game
import "core:c"
import "core:fmt"
import "core:math"
import "core:math/linalg"
import "core:slice"
import rl "vendor:raylib"

Entity_Kind :: enum u8 {
	Object,
	Skater,
}

Entity :: struct {
	min:         rl.Vector3,
	max:         rl.Vector3,
	idx:         u16,
	entity_kind: Entity_Kind,
	object_kind: Object_Kind,
}

render :: proc(state: ^State) {
	rl.BeginShaderMode(state.shaders[.Customize])
	defer rl.EndShaderMode()

	rl.SetShaderValueTexture(state.shaders[.Customize], state.palette.loc, state.palette.tex)

	screen := rl.Vector2{f32(rl.GetScreenWidth()), f32(rl.GetScreenHeight())}
	state.offset = screen / 2

	time_of_day := state.config.data.customization.time_of_day
	sky_color := state.config.data.customization.sky_color[time_of_day]
	rl.ClearBackground(vec_to_color(sky_color.rgb))

	loc := rl.GetShaderLocation(state.shaders[.Customize], "skyColor")
	tint := sky_color / 255
	rl.SetShaderValue(state.shaders[.Customize], loc, &tint, .VEC4)

	target := &state.skaters[state.target_skater_idx]

	entities: [dynamic; MAX_SKATERS + MAX_OBJECTS]Entity
	for &object, idx in state.objects {
		max := object.pos + object.size
		if object.kind == .Ramp {max.z = object.pos.z}
		append(&entities, Entity{object.pos, max, u16(idx), .Object, object.kind})
	}
	for &skater, idx in state.skaters {
		append(&entities, Entity{skater.pos, skater.pos, u16(idx), .Skater, .Box})
	}
	slice.stable_sort_by(entities[:], proc(a, b: Entity) -> bool {
		return a.max.x <= b.min.x || a.max.y <= b.min.y || a.max.z <= b.min.z
	})

	for entity in entities {
		switch entity.entity_kind {
		case .Object:
			object := state.objects[entity.idx]
			offset := object.pos - target.pos
			draw_object(state, &object, offset)
		case .Skater:
			skater := state.skaters[entity.idx]
			skater_idx := int(entity.idx)
			offset := skater.pos - target.pos
			if state.drawing_mode == .Dimetric {
				draw_board(state, &skater, offset)
				draw_skater(state, &skater, skater_idx, offset)
			}
			if state.target_skater_idx == skater_idx &&
			   (state.show_normals || state.drawing_mode != .Dimetric) {
				draw_skater_collisions(state, &skater, skater_idx, offset)
				rl.DrawCircleV(project(offset, state), 4, rl.ORANGE)
			}
		}
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

	rl.DrawFPS(0, 0)
}

draw_object :: proc(state: ^State, object: ^Object, offset: rl.Vector3) {
	colors := state.config.data.objects.colors[object.mat]
	bg, outline := vec_to_color(colors.bg), vec_to_color(colors.outline)

	switch object.kind {
	case .Box:
		verts: [8]rl.Vector3
		slice.fill(verts[:], offset)
		verts[1].yy += object.size.yy
		verts[2].xy += object.size.xy
		verts[3].xx += object.size.xx
		verts[4].zzz += object.size.zzz
		verts[5].yyz += object.size.yyz
		verts[6].xyz += object.size.xyz
		verts[7].xxz += object.size.xxz

		proj: [len(verts)]rl.Vector2
		for p, i in verts {proj[i] = project(p, state)}

		// fill
		shape := [?]rl.Vector2{proj[4], proj[5], proj[1], proj[2], proj[3], proj[7]}
		rl.DrawTriangleFan(&shape[0], len(shape), bg)

		// bottom outline
		for i in 1 ..< 3 {rl.DrawLineEx(proj[i], proj[(i + 1)], 2, outline)}
		// top outline
		for i in 1 ..< 4 {rl.DrawLineEx(proj[i], proj[(i + 4)], 2, outline)}
		// vertical outlines
		for i in 0 ..< 4 {
			idx := 4 + [2]int{i, (i + 1) % 4}
			rl.DrawLineEx(proj[idx[0]], proj[idx[1]], 2, outline)
		}
	case .Ramp:
		verts: [6]rl.Vector3
		slice.fill(verts[:], offset)
		verts[1].yy += object.size.yy
		verts[2].xy += object.size.xy
		verts[3].xx += object.size.xx
		proj: [len(verts)]rl.Vector2

		switch object.orientation {
		case .North:
			verts[4].zzz += object.size.zzz
			verts[5].xxz += object.size.xxz

			for p, i in verts {proj[i] = project(p, state)}

			shape := [?]rl.Vector2{proj[4], proj[1], proj[2], proj[3], proj[5]}
			rl.DrawTriangleFan(&shape[0], len(shape), bg)

			rl.DrawLineEx(proj[4], proj[5], 2, outline)
			rl.DrawLineEx(proj[3], proj[5], 2, outline)
			rl.DrawLineEx(proj[4], proj[1], 2, outline)
			rl.DrawLineEx(proj[5], proj[2], 2, outline)
		case .East, .South:
			panic("not implemented")
		case .West:
			verts[4].zzz += object.size.zzz
			verts[5].yyz += object.size.yyz

			for p, i in verts {proj[i] = project(p, state)}

			shape := [?]rl.Vector2{proj[4], proj[5], proj[1], proj[2], proj[3]}
			rl.DrawTriangleFan(&shape[0], len(shape), bg)

			rl.DrawLineEx(proj[4], proj[5], 2, outline)
			rl.DrawLineEx(proj[1], proj[5], 2, outline)
			rl.DrawLineEx(proj[5], proj[2], 2, outline)
			rl.DrawLineEx(proj[4], proj[3], 2, outline)
		}

		for i in 1 ..< 3 {rl.DrawLineEx(proj[i], proj[(i + 1)], 2, outline)}
	}
}

project :: proc(point_3d: rl.Vector3, state: ^State) -> rl.Vector2 {
	cell_size := state.config.data.camera.cell_size
	point_2d: rl.Vector2
	#partial switch state.drawing_mode {
	case .Dimetric:
		point_2d = PRO_MATRIX * point_3d
	case .Top:
		point_2d = {point_3d.x, point_3d.y}
	case .South:
		point_2d = {point_3d.x, -point_3d.z}
	case .East:
		point_2d = {-point_3d.y, -point_3d.z}
	}

	return point_2d * cell_size + state.offset
}

PRO_MATRIX :: matrix[2, 3]f32{
	1, -1, 0,
	0.5, 0.5, -1,
}

draw_skater_collisions :: proc(
	state: ^State,
	skater: ^Skater,
	skater_idx: int,
	offset: rl.Vector3,
) {
	num_circles := 4
	base_points: [100]rl.Vector3
	points_per_circle := len(base_points) / num_circles

	for c in 0 ..< num_circles {
		for p in 0 ..< points_per_circle {
			y_angle := math.PI * 2 / f32(points_per_circle) * f32(p)
			y_rot := matrix[3, 3]f32{
				math.cos(y_angle), 0, math.sin(y_angle),
				0, 1, 0,
				-math.sin(y_angle), 0, math.cos(y_angle),
			}

			z_angle := math.PI / f32(num_circles) * f32(c)
			z_angle += skater.angle
			z_rot := matrix[3, 3]f32{
				math.cos(z_angle), -math.sin(z_angle), 0,
				math.sin(z_angle), math.cos(z_angle), 0,
				0, 0, 1,
			}

			base_points[c * points_per_circle + p] =
				z_rot * y_rot * rl.Vector3{1, 0, 0} * skater.radius
		}
	}

	for c in 0 ..< num_circles {
		for p in 0 ..< points_per_circle {
			start := base_points[c * points_per_circle + p] + offset
			end := base_points[c * points_per_circle + (p + 1) % points_per_circle] + offset

			color := skater.color
			if skater.state == .Airborne {
				color = rl.ColorBrightness(color, 0.5)
			}

			rl.DrawLineEx(project(start, state), project(end, state), 2, color)
		}
	}

}

draw_skater :: proc(state: ^State, skater: ^Skater, skater_idx: int, offset: rl.Vector3) {
	frame_size := state.config.data.sprite.frame_size
	sprite_pos := skater.animation.progress.idx * frame_size
	config := animation_configs[skater.animation.state]
	target_pos := project(offset, state)
	target_pos.x -= frame_size * 0.5
	target_pos.y -= frame_size * 0.8

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
