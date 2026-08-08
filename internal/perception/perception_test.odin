package perception

import "../win32"
import "core:strings"
import "core:sys/windows"
import "core:testing"

// Runs as one serialized test because COM/UIA state must not race across
// parallel test threads. Exercises the surface only: open, state, text.
@(test)
test_state_and_text_of_shell_window :: proc(t: ^testing.T) {
	s, err := open()
	testing.expect(t, err == .None)
	if err != .None {
		return
	}
	defer close(&s)

	hwnd := win32.GetShellWindow()
	testing.expect(t, hwnd != nil)

	limits := Limits {
		max_nodes  = 300,
		max_depth  = 10,
		text_limit = 200,
	}
	text, serr := state(&s, hwnd, limits)
	testing.expect(t, serr == .None)
	testing.expect(t, len(text) > 0)
	testing.expect(t, strings.has_prefix(text, "[0]"))
	testing.expect(t, strings.contains(text, "Program"))
	delete(text)

	// Text content may not be present on every element; it must not crash.
	_, terr := perception_text(&s, hwnd)
	_ = terr
}

// perception_text is a thin wrapper so the test can call text without
// colliding with the local variable name.
perception_text :: proc(s: ^Session, hwnd: windows.HWND) -> (string, Error) {
	return text(s, hwnd)
}
