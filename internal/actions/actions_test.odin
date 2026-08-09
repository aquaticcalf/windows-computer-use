package actions

import "../perception"
import "../uia"
import "core:sys/windows"
import "core:testing"

// Exercises the actions surface end-to-end against a real Win32 button.
// Runs as one serialized test because COM/UIA state must not race across
// parallel test threads. See DESIGN.md (test at the seam).

@(test)
test_actions_surface :: proc(t: ^testing.T) {
	s, err := open()
	testing.expect(t, err == .None)
	if err != .None {
		return
	}
	defer close(&s)

	button := create_button()
	testing.expect(t, button != nil)
	if button == nil {
		return
	}
	defer windows.DestroyWindow(button)

	limits := perception.default_limits()

	// Index 0 is the button window itself, which exposes InvokePattern.
	cerr := click_index(&s, button, 0, .Uia, limits)
	testing.expect(t, cerr == .None)

	// An index far beyond the tree errors cleanly.
	oerr := click_index(&s, button, 999_999, .Auto, limits)
	testing.expect(t, oerr == .Index_Out_Of_Range)

	// The element resolved at index 0 is our button.
	el, eerr := element_at_index(&s, button, 0, limits)
	testing.expect(t, eerr == .None)
	if eerr == .None {
		defer uia.release_element(&el)
		name, nerr := uia.name(&el)
		testing.expect(t, nerr == .None)
		testing.expect(t, name == "invoke me")
		delete(name)
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
