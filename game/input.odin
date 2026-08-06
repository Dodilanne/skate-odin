package game

import "core:testing"
import rl "vendor:raylib"

Input_State :: struct {
	actions: [Input_Action]bit_set[Input_Flag],
}

Input_Action :: enum u8 {
	None = 0,
	Up,
	Right,
	Down,
	Left,
	Toggle_Drawing_Mode,
	Toggle_Normals,
	Push,
	Break,
	Reset,
	Cycle_Target,
	Trick_W,
	Trick_O, // origin
	Trick_E,
	Trick_WN,
	Trick_N,
	Trick_NE,
	Trick_ES,
	Trick_S,
	Trick_SW,
}

Input_Flag :: enum u8 {
	Down,
	Pressed,
	Released,
}

input_flags :: proc(key: rl.KeyboardKey) -> (flags: bit_set[Input_Flag]) {
	if rl.IsKeyDown(key) {flags |= {.Down}}
	if rl.IsKeyPressed(key) {flags |= {.Pressed}}
	if rl.IsKeyReleased(key) {flags |= {.Released}}
	return
}

// Clears flags that should only be true in one simulation loop (pressed, released)
// Doesn't touch continuous flags (down)
clear_input_flags :: proc(state: ^Input_State, flags: bit_set[Input_Flag]) {
	for &action in state.actions {
		action &= ~flags
	}
}

gather_input :: proc(state: ^Input_State) {
	state.actions[.Up] = input_flags(.F)
	state.actions[.Right] = input_flags(.T)
	state.actions[.Down] = input_flags(.S)
	state.actions[.Left] = input_flags(.R)
	state.actions[.Toggle_Drawing_Mode] = input_flags(.D)
	state.actions[.Toggle_Normals] = input_flags(.X)
	state.actions[.Push] = input_flags(.N) | input_flags(.ENTER)
	state.actions[.Break] = input_flags(.SPACE)
	state.actions[.Reset] = input_flags(.ZERO)
	state.actions[.Cycle_Target] = input_flags(.Z)
	state.actions[.Trick_O] = input_flags(.E)
	state.actions[.Trick_N] = input_flags(.U)
	state.actions[.Trick_NE] = input_flags(.Y)
	state.actions[.Trick_E] = input_flags(.I)
	state.actions[.Trick_ES] = input_flags(.PERIOD)
	state.actions[.Trick_S] = input_flags(.COMMA)
	state.actions[.Trick_SW] = input_flags(.H)
	state.actions[.Trick_W] = input_flags(.N)
	state.actions[.Trick_WN] = input_flags(.L)
}

// Adds b's input to a
add_input :: proc(a: ^Input_State, b: Input_State) {
	for flags, action in b.actions {
		a.actions[action] |= flags
	}
}

@(test)
test_clear_input :: proc(t: ^testing.T) {
	state: Input_State
	state.actions[.Right] = {.Down, .Released}
	state.actions[.Up] = {.Released, .Pressed}
	clear_input_flags(&state, {.Pressed, .Released})
	testing.expect_value(t, state.actions[.Right], bit_set[Input_Flag]{.Down})
	testing.expect_value(t, state.actions[.Up], bit_set[Input_Flag]{})
}
