package uia

import "../win32"
import windows "core:sys/windows"
import "core:testing"

// Runs as one serialized test: the Odin test runner would otherwise run
// separate @(test) procs on parallel threads, which can race COM/UIA state.
@(test)
test_automation_root_and_element_from_handle :: proc(t: ^testing.T) {
	windows.CoInitialize(nil)
	defer windows.CoUninitialize()

	a, hr := create()
	testing.expect(t, hr == 0)
	if hr != 0 {
		return
	}
	defer destroy(&a)

	root, rhr := root_element(&a)
	testing.expect(t, rhr == 0)
	testing.expect(t, root != nil)

	hwnd := win32.GetShellWindow()
	if hwnd == nil {
		hwnd = windows.GetForegroundWindow()
	}
	testing.expect(t, hwnd != nil)

	el, ehr := element_from_handle(&a, hwnd)
	testing.expect(t, ehr == 0)
	testing.expect(t, el != nil)
}
