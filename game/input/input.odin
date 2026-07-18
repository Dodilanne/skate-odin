package input

import "core:testing"
import rl "vendor:raylib"

State :: struct {
	actions: [Action]bit_set[Flag],
}

Action :: enum u8 {
	Up,
	Right,
	Down,
	Left,
	Toggle_Color_Mode,
	Toggle_Drawing_Mode,
	Toggle_Normals,
	Push,
	Break,
	Reset,
	Cycle_Target,
	Trick_O,
	Trick_N,
	Trick_NE,
	Trick_E,
	Trick_ES,
	Trick_S,
	Trick_SW,
	Trick_W,
	Trick_WN,
}

Flag :: enum u8 {
	Down,
	Pressed,
	Released,
}

flags :: proc(key: rl.KeyboardKey) -> (flags: bit_set[Flag]) {
	if rl.IsKeyDown(key) do flags |= {.Down}
	if rl.IsKeyPressed(key) do flags |= {.Pressed}
	if rl.IsKeyReleased(key) do flags |= {.Released}
	return
}

// Clears flags that should only be true in one simulation loop (pressed, released)
// Doesn't touch continuous flags (down)
clear_flags :: proc(state: ^State, flags: bit_set[Flag]) {
	for &action in state.actions {
		action &= ~flags
	}
}

gather :: proc(state: ^State) {
	state.actions[.Up] = flags(.F)
	state.actions[.Right] = flags(.T)
	state.actions[.Down] = flags(.S)
	state.actions[.Left] = flags(.R)
	state.actions[.Toggle_Color_Mode] = flags(.C)
	state.actions[.Toggle_Drawing_Mode] = flags(.D)
	state.actions[.Toggle_Normals] = flags(.X)
	state.actions[.Push] = flags(.ENTER)
	state.actions[.Break] = flags(.SPACE)
	state.actions[.Reset] = flags(.ZERO)
	state.actions[.Cycle_Target] = flags(.Z)
	state.actions[.Trick_O] = flags(.E)
	state.actions[.Trick_N] = flags(.U)
	state.actions[.Trick_NE] = flags(.Y)
	state.actions[.Trick_E] = flags(.I)
	state.actions[.Trick_ES] = flags(.PERIOD)
	state.actions[.Trick_S] = flags(.COMMA)
	state.actions[.Trick_SW] = flags(.H)
	state.actions[.Trick_W] = flags(.N)
	state.actions[.Trick_WN] = flags(.L)
}

// Adds b's input to a
add :: proc(a: ^State, b: State) {
	for flags, action in b.actions {
		a.actions[action] |= flags
	}
}

@(test)
test_clear :: proc(t: ^testing.T) {
	state: State
	state.actions[.Right] = {.Down, .Released}
	state.actions[.Up] = {.Released, .Pressed}
	clear_flags(&state, {.Pressed, .Released})
	testing.expect_value(t, state.actions[.Right], bit_set[Flag]{.Down})
	testing.expect_value(t, state.actions[.Up], bit_set[Flag]{})
}
