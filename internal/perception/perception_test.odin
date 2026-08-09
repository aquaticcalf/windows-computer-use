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

	// The --match filter keeps only lines containing the needle.
	matched, merr := state(&s, hwnd, limits, "Recycle")
	testing.expect(t, merr == .None)
	testing.expect(t, strings.contains(matched, "Recycle Bin"))
	testing.expect(t, !strings.contains(matched, "Program Manager"))
	delete(matched)

	// The node-range view limits output to the requested span.
	partial, perr := state(&s, hwnd, limits, "", Node_Range{start = 0, count = 2})
	testing.expect(t, perr == .None)
	testing.expect(t, strings.has_prefix(partial, "[0]"))
	testing.expect(t, !strings.contains(partial, "[2]"))
	delete(partial)

	// A range beyond the tree reports no nodes.
	empty, eerr := state(&s, hwnd, limits, "", Node_Range{start = 999, count = 5})
	testing.expect(t, eerr == .None)
	testing.expect(t, strings.contains(empty, "no nodes in range"))
	delete(empty)

	// Text content may not be present on every element; it must not crash.
	_, terr := perception_text(&s, hwnd)
	_ = terr

	// Deep-walk the shell window with a large budget. Regression for the NULL
	// name BSTR crash: some providers return S_OK with a nil name, which the
	// old code dereferenced.
	deep_limits := Limits {
		max_nodes  = 5000,
		max_depth  = 64,
		text_limit = 100,
	}
	deep, derr := state(&s, hwnd, deep_limits)
	testing.expect(t, derr == .None)
	if derr == .None {
		testing.expect(t, len(deep) > 0)
		delete(deep)
	}
}

// perception_text is a thin wrapper so the test can call text without
// colliding with the local variable name.
perception_text :: proc(s: ^Session, hwnd: windows.HWND) -> (string, Error) {
	return text(s, hwnd)
}
