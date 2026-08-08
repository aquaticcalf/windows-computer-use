package uia

import "../win32"
import windows "core:sys/windows"
import "core:testing"

// Exercises the module through its surface only. Assertions describe
// outcomes, not internals. See DESIGN.md.
//
// Runs as one serialized test: the Odin test runner would otherwise run
// separate @(test) procs on parallel threads, which can race COM/UIA state.
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

	role, rerr := control_type(&el)
	testing.expect(t, rerr == .None)
	testing.expect(t, role > 0)

	enabled, ierr := is_enabled(&el)
	testing.expect(t, ierr == .None)
	_ = enabled

	rect, rrerr := bounding_rect(&el)
	testing.expect(t, rrerr == .None)
	testing.expect(t, rect.right > rect.left)

	// Tree walking from the desktop root (top-level windows exist).
	root, root_err := root_element(&a)
	testing.expect(t, root_err == .None)
	if root_err != .None {
		return
	}
	defer release_element(&root)

	child, ok := first_child(&a, &root)
	testing.expect(t, ok)
	if ok {
		defer release_element(&child)
	}

	arr, ferr := find_all(&a, &root, Tree_Scope_Children)
	testing.expect(t, ferr == .None)
	if ferr != .None {
		return
	}
	defer release_array(&arr)

	count, cerr := element_count(&arr)
	testing.expect(t, cerr == .None)
	testing.expect(t, count >= 1)

	// Patterns: an element without a pattern fails gracefully, and a real
	// Win32 button can be invoked without moving the cursor.
	testing.expect(t, invoke(&el) == .Pattern_Not_Available)
	testing.expect(t, toggle(&el) == .Pattern_Not_Available)
	testing.expect(t, select(&el) == .Pattern_Not_Available)

	button := create_button()
	testing.expect(t, button != nil)
	if button != nil {
		defer windows.DestroyWindow(button)
		bel, berr := element_from_handle(&a, button)
		testing.expect(t, berr == .None)
		if berr == .None {
			defer release_element(&bel)
			testing.expect(t, invoke(&bel) == .None)
		}
	}
}

// create_button makes a Win32 push button; UIA exposes InvokePattern on it.
create_button :: proc() -> windows.HWND {
	class_buf: [16]u16
	text_buf: [16]u16
	class := windows.utf8_to_wstring_buf(class_buf[:], "BUTTON")
	text := windows.utf8_to_wstring_buf(text_buf[:], "invoke me")
	// WS_CHILD | WS_VISIBLE | BS_PUSHBUTTON
	return windows.CreateWindowExW(
		0,
		class,
		text,
		0x50000000,
		0,
		0,
		40,
		20,
		windows.GetDesktopWindow(),
		nil,
		nil,
		nil,
	)
}
