package input

import "../win32"
import "core:sys/windows"

// Physical input fallback for apps without UIA support. Use this module only
// when a target cannot be driven through accessibility; it injects into the
// global input stream. See ARCHITECTURE.md (Actions) and DESIGN.md.

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

key_input :: proc(vk: u16, scan: u16, flags: u32) -> windows.INPUT {
	return windows.INPUT{type = .KEYBOARD, ki = {wVk = vk, wScan = scan, dwFlags = flags}}
}

click :: proc(x, y: i32, button: Mouse_Button = .Left) {
	down, up := mouse_button_flags(button)
	windows.SetCursorPos(x, y)
	send(mouse_input(0, 0, down))
	send(mouse_input(0, 0, up))
}

press_key :: proc(vk: u16) {
	send(key_input(vk, 0, 0))
	send(key_input(vk, 0, win32.KEYEVENTF_KEYUP))
}

type_text :: proc(text: string) {
	for ch in text {
		unit := u16(ch)
		send(key_input(0, unit, win32.KEYEVENTF_UNICODE))
		send(key_input(0, unit, win32.KEYEVENTF_UNICODE | win32.KEYEVENTF_KEYUP))
	}
}

send :: proc(input: windows.INPUT) {
	local := input
	windows.SendInput(1, &local, size_of(windows.INPUT))
}

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
