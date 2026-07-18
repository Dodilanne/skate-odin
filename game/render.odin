package game

import "core:math"
import "core:math/linalg"
import rl "vendor:raylib"

render :: proc(state: ^State) {
	bg: rl.Color
	if state.color_mode == .light {
		bg = rl.WHITE
	} else {
		bg = rl.DARKGRAY
	}
	rl.ClearBackground(bg)

	for &skater in state.skaters {
		for &surface in state.surfaces {
			if state.show_normals {
				rl.DrawCircleV(project(surface.o - skater.pos, state), 4, rl.BLUE)
				rl.DrawLineEx(
					project(surface.o - skater.pos, state),
					project(surface.o + surface.n - skater.pos, state),
					2,
					rl.RED,
				)
				rl.DrawLineEx(
					project(surface.o - skater.pos, state),
					project(surface.o + surface.u - skater.pos, state),
					2,
					rl.GREEN,
				)
				rl.DrawLineEx(
					project(surface.o - skater.pos, state),
					project(surface.o + surface.v - skater.pos, state),
					2,
					rl.YELLOW,
				)
			}
			for col in 0 ..= surface.w {
				start := surface.o + surface.u * col - skater.pos
				end := start + surface.v * surface.h
				rl.DrawLineEx(
					project(start, state),
					project(end, state),
					1.1,
					rl.Fade(rl.LIGHTGRAY, 0.5),
				)
			}
			for row in 0 ..= surface.h {
				start := surface.o + surface.v * row - skater.pos
				end := start + surface.u * surface.w
				rl.DrawLineEx(
					project(start, state),
					project(end, state),
					1.1,
					rl.Fade(rl.LIGHTGRAY, 0.5),
				)
			}
		}


		num_circles := 6
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
				start := base_points[c * points_per_circle + p]
				end := base_points[c * points_per_circle + (p + 1) % points_per_circle]
				color := rl.ORANGE
				if skater.airborne do color = rl.GREEN
				rl.DrawLineEx(project(start, state), project(end, state), 2, color)
			}
		}

		rl.DrawCircleV(project(-skater.pos, state), 2, rl.Fade(rl.LIGHTGRAY, 0.5))
		rl.DrawCircleV(project(rl.Vector3(0), state), 4, rl.Fade(rl.LIGHTGRAY, 0.5))

		if linalg.length(skater.vel) > 0 {
			rl.DrawLineEx(project(rl.Vector3(0), state), project(skater.vel, state), 4, rl.PINK)
		}

		rl.DrawLineEx(project(rl.Vector3(0), state), project(skater.move_dir, state), 4, rl.BLUE)

		rl.DrawLineEx(project(rl.Vector3(0), state), project(skater.look_dir, state), 4, rl.YELLOW)

	}

	rl.DrawFPS(0, 0)
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
