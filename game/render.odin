package game

import "core:fmt"
import "core:math"
import "core:math/linalg"
import rl "vendor:raylib"

render :: proc(state: ^State) {
	bg := rl.DARKGRAY
	if state.color_mode == .light {
		bg = rl.WHITE
	}

	rl.ClearBackground(bg)

	rl.DrawFPS(0, 0)

	target := &state.skaters[state.target_skater_idx]

	for &surface in state.surfaces {
		offset := surface.o - target.pos

		if state.show_normals {
			rl.DrawCircleV(project(offset, state), 4, rl.BLUE)
			rl.DrawLineEx(project(offset, state), project(surface.n + offset, state), 2, rl.RED)
			rl.DrawLineEx(project(offset, state), project(surface.u + offset, state), 2, rl.GREEN)
			rl.DrawLineEx(project(offset, state), project(surface.v + offset, state), 2, rl.YELLOW)
		}

		for col in 0 ..= surface.w {
			start := surface.u * col + offset
			end := start + surface.v * surface.h
			rl.DrawLineEx(
				project(start, state),
				project(end, state),
				1.1,
				rl.Fade(rl.LIGHTGRAY, 0.5),
			)
		}
		for row in 0 ..= surface.h {
			start := surface.v * row + offset
			end := start + surface.u * surface.w
			rl.DrawLineEx(
				project(start, state),
				project(end, state),
				1.1,
				rl.Fade(rl.LIGHTGRAY, 0.5),
			)
		}
	}

	for &skater in state.skaters {
		num_circles := 6
		base_points: [100]rl.Vector3
		points_per_circle := len(base_points) / num_circles
		offset := skater.pos - target.pos

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
				if skater.state == .airborne {
					color = rl.ColorBrightness(color, 0.5)
				}

				rl.DrawLineEx(project(start, state), project(end, state), 2, color)
			}
		}

		rl.DrawCircleV(project(-skater.pos + offset, state), 2, rl.Fade(rl.LIGHTGRAY, 0.5))
		rl.DrawCircleV(project(rl.Vector3(0) + offset, state), 4, rl.Fade(rl.LIGHTGRAY, 0.5))

		if linalg.length(skater.vel) > 0 {
			rl.DrawLineEx(
				project(rl.Vector3(0) + offset, state),
				project(skater.vel + offset, state),
				4,
				rl.PINK,
			)
		}

		rl.DrawLineEx(project(offset, state), project(skater.move_dir + offset, state), 4, rl.BLUE)

		rl.DrawLineEx(
			project(offset, state),
			project(skater.look_dir + offset, state),
			4,
			rl.YELLOW,
		)

		if state.show_normals {
			rl.DrawLineEx(project(offset, state), project(skater.norm + offset, state), 4, rl.RED)
		}

	}

	font_size: i32 = 20
	rl.DrawText(
		fmt.ctprintf("%f", target.state_timer),
		rl.GetScreenWidth() / 2 + 30,
		(rl.GetScreenHeight() - font_size) / 2,
		font_size,
		rl.WHITE,
	)
	if target.trick_committed != "" {
		str := fmt.ctprintf("%s", target.trick_committed)
		measure := rl.MeasureText(str, font_size)
		rl.DrawText(
			str,
			rl.GetScreenWidth() / 2 - 30 - measure,
			(rl.GetScreenHeight() - font_size) / 2,
			font_size,
			rl.YELLOW,
		)
	}
}

project :: proc(point: rl.Vector3, state: ^State) -> rl.Vector2 {
	if state.drawing_mode == .top_down {
		return point.xy * state.cell_size + state.offset
	}
	if state.drawing_mode == .side {
		return rl.Vector2{-point.y, -point.z} * state.cell_size + state.offset
	}
	return PRO_MATRIX * point * state.cell_size + state.offset
}

PRO_MATRIX :: matrix[2, 3]f32{
	1, -1, 0,
	0.5, 0.5, -1,
}
