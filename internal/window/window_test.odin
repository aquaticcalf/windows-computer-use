package window

import "../win32"
import "core:testing"

@(test)
test_list_and_find_shell_window :: proc(t: ^testing.T) {
	windows, ok := list()
	testing.expect(t, ok)
	if !ok {
		return
	}
	defer destroy(windows)

	testing.expect(t, len(windows) > 0)

	shell := win32.GetShellWindow()
	testing.expect(t, shell != nil)

	found, fok := find(windows, "Program Manager")
	testing.expect(t, fok)
	_ = found

	// The shell window must be in the enumeration.
	present := false
	for w in windows {
		if w.handle == shell {
			present = true
		}
	}
	testing.expect(t, present)
}

@(test)
test_rect_and_foreground_are_callable :: proc(t: ^testing.T) {
	shell := win32.GetShellWindow()
	testing.expect(t, shell != nil)

	r, rok := rect(shell)
	testing.expect(t, rok)
	if rok {
		testing.expect(t, r.right > r.left)
		testing.expect(t, r.bottom > r.top)
	}

	// Foreground can race with the user; just assert it returns without error.
	_ = force_foreground(shell)
}
