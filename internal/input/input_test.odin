package input

import "../win32"
import "core:sys/windows"
import "core:testing"

// Pure construction only: no physical input is injected in tests.

@(test)
test_key_input_construction :: proc(t: ^testing.T) {
	k := key_input('A', 0, 0)
	testing.expect(t, k.type == .KEYBOARD)
	testing.expect(t, k.ki.wVk == u16('A'))

	u := key_input(0, 'x', win32.KEYEVENTF_UNICODE)
	testing.expect(t, u.ki.wScan == u16('x'))
	testing.expect(t, u.ki.dwFlags == win32.KEYEVENTF_UNICODE)
}

@(test)
test_mouse_input_construction :: proc(t: ^testing.T) {
	m := mouse_input(5, 7, windows.MOUSEEVENTF_LEFTDOWN)
	testing.expect(t, m.type == .MOUSE)
	testing.expect(t, m.mi.dx == 5)
	testing.expect(t, m.mi.dy == 7)
	testing.expect(t, m.mi.dwFlags == windows.MOUSEEVENTF_LEFTDOWN)
}

@(test)
test_mouse_button_flags :: proc(t: ^testing.T) {
	down, up := mouse_button_flags(.Right)
	testing.expect(t, down == windows.MOUSEEVENTF_RIGHTDOWN)
	testing.expect(t, up == windows.MOUSEEVENTF_RIGHTUP)

	down, up = mouse_button_flags(.Middle)
	testing.expect(t, down == windows.MOUSEEVENTF_MIDDLEDOWN)
	testing.expect(t, up == windows.MOUSEEVENTF_MIDDLEUP)
}
