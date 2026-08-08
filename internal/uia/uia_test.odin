package uia

import "../win32"
import windows "core:sys/windows"
import "core:testing"

// Exercises the module through its surface only: create, resolve an element,
// read its name. Assertions describe outcomes, not internals. See DESIGN.md.
@(test)
test_surface_end_to_end :: proc(t: ^testing.T) {
	windows.CoInitialize(nil)
	defer windows.CoUninitialize()

	a, err := create()
	testing.expect(t, err == .None)
	if err != .None {
		return
	}
	defer destroy(&a)

	root, rerr := root_element(&a)
	testing.expect(t, rerr == .None)
	if rerr == .None {
		defer release_element(&root)
		testing.expect(t, root.ptr != nil)
	}

	hwnd := win32.GetShellWindow()
	if hwnd == nil {
		hwnd = windows.GetForegroundWindow()
	}
	testing.expect(t, hwnd != nil)

	el, eerr := element_from_handle(&a, hwnd)
	testing.expect(t, eerr == .None)
	if eerr != .None {
		return
	}
	defer release_element(&el)

	text, nerr := name(&el)
	testing.expect(t, nerr == .None)
	testing.expect(t, len(text) > 0)
	delete(text)
}
