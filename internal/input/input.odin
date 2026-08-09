package input

import "../win32"
import "core:sys/windows"

// Physical input fallback for apps without UIA support. Use this module only
// when a target cannot be driven through accessibility; it injects into the
// global input stream. See ARCHITECTURE.md (Actions) and DESIGN.md.

// Mouse_Button selects which button click simulates.
Mouse_Button :: enum u32 {
	Left   = 0,
	Right  = 1,
	Middle = 2,
}

// Constructors are pure: they only build INPUT structs, so they are trivially
// testable (return results instead of producing side effects).
mouse_input :: proc(x, y: i32, flags: u32) -> windows.INPUT {
	return windows.INPUT{type = .MOUSE, mi = {dx = x, dy = y, dwFlags = flags}}
}

// key_input builds a keyboard INPUT struct from a virtual key, scan code,
// and flags.
key_input :: proc(vk: u16, scan: u16, flags: u32) -> windows.INPUT {
	return windows.INPUT{type = .KEYBOARD, ki = {wVk = vk, wScan = scan, dwFlags = flags}}
}

// click moves the pointer to x, y and presses the given mouse button.
click :: proc(x, y: i32, button: Mouse_Button = .Left) {
	down, up := mouse_button_flags(button)
	windows.SetCursorPos(x, y)
	send(mouse_input(0, 0, down))
	send(mouse_input(0, 0, up))
}

// key_down presses a virtual key without releasing it. The extended flag marks
// navigation keys (arrows, Delete, Home, ...) so the scan code is correct.
key_down :: proc(vk: u16, extended: bool = false) {
	flags := extended ? win32.KEYEVENTF_EXTENDEDKEY : u32(0)
	send(key_input(vk, 0, flags))
}

// key_up releases a virtual key previously held with key_down.
key_up :: proc(vk: u16, extended: bool = false) {
	flags: u32 = win32.KEYEVENTF_KEYUP
	if extended {
		flags |= win32.KEYEVENTF_EXTENDEDKEY
	}
	send(key_input(vk, 0, flags))
}

// press_key presses and releases the virtual key with the given code.
press_key :: proc(vk: u16, extended: bool = false) {
	key_down(vk, extended)
	key_up(vk, extended)
}

// type_text sends the text as Unicode keyboard events. Each character is
// injected as a down/up pair in one SendInput batch. A short pause follows a
// space: Windows auto-repeat logic misfires if the next key arrives too fast
// after a space, repeating a phantom key over the rest of the text.
type_text :: proc(text: string) {
	for ch in text {
		unit := u16(ch)
		events := [2]windows.INPUT {
			key_input(0, unit, win32.KEYEVENTF_UNICODE),
			key_input(0, unit, win32.KEYEVENTF_UNICODE | win32.KEYEVENTF_KEYUP),
		}
		send_many(events[:])
		if ch == ' ' {
			windows.Sleep(80)
		}
	}
}

// scroll_wheel turns the mouse wheel by delta units. Each notch is
// WHEEL_DELTA (120); a positive delta scrolls up (or right when horizontal).
scroll_wheel :: proc(delta: i32, horizontal: bool = false) {
	send(wheel_input(delta, horizontal))
}

// wheel_input builds a mouse INPUT struct for a wheel turn. It is pure so it
// can be tested without injecting input.
wheel_input :: proc(delta: i32, horizontal: bool) -> windows.INPUT {
	flags: u32 = windows.MOUSEEVENTF_WHEEL
	if horizontal {
		flags = windows.MOUSEEVENTF_HWHEEL
	}
	return windows.INPUT{type = .MOUSE, mi = {mouseData = u32(delta), dwFlags = flags}}
}

// send injects one INPUT event into the global input stream.
send :: proc(input: windows.INPUT) {
	local := input
	windows.SendInput(1, &local, size_of(windows.INPUT))
}

// send_many injects a batch of INPUT events atomically in one SendInput call.
send_many :: proc(events: []windows.INPUT) {
	if len(events) == 0 {
		return
	}
	windows.SendInput(u32(len(events)), raw_data(events), size_of(windows.INPUT))
}

// mouse_button_flags returns the down and up event flags for a button.
mouse_button_flags :: proc(button: Mouse_Button) -> (down, up: u32) {
	switch button {
	case .Left:
		return windows.MOUSEEVENTF_LEFTDOWN, windows.MOUSEEVENTF_LEFTUP
	case .Right:
		return windows.MOUSEEVENTF_RIGHTDOWN, windows.MOUSEEVENTF_RIGHTUP
	case .Middle:
		return windows.MOUSEEVENTF_MIDDLEDOWN, windows.MOUSEEVENTF_MIDDLEUP
	}
	return
}
