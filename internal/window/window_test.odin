package window

import "../win32"
import "core:fmt"
import "core:strings"
import "core:sys/windows"
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

@(test)
test_resolve_by_title_and_pid :: proc(t: ^testing.T) {
	shell := win32.GetShellWindow()
	hwnd, ok := resolve("Program Manager")
	testing.expect(t, ok)
	testing.expect(t, hwnd == shell)

	rows, lok := list()
	testing.expect(t, lok)
	if lok {
		defer destroy(rows)
		if len(rows) > 0 {
			pid := rows[0].pid
			by_pid, pok := resolve(fmt.tprintf("%d", pid))
			testing.expect(t, pok)
			_ = by_pid
		}
	}
}

@(test)
test_window_ids_are_stable_and_resolvable :: proc(t: ^testing.T) {
	rows, lok := list()
	testing.expect(t, lok)
	if !lok {
		return
	}
	defer destroy(rows)
	testing.expect(t, len(rows) > 0)

	// Every window has a non-empty id.
	for w in rows {
		testing.expect(t, len(w.id) > 0)
	}

	// ids are unique across the list.
	for i in 0 ..< len(rows) {
		for j in i + 1 ..< len(rows) {
			testing.expect(t, rows[i].id != rows[j].id)
		}
	}

	// Resolving a row by its id returns the same window handle.
	for w in rows {
		hwnd, rok := resolve(w.id)
		testing.expect(t, rok)
		testing.expect(t, hwnd == w.handle)
	}
}

@(test)
test_assign_ids_marks_multi_window_processes :: proc(t: ^testing.T) {
	rows, lok := list()
	testing.expect(t, lok)
	if !lok {
		return
	}
	defer destroy(rows)

	// Find a process with multiple windows and confirm the dotted ids.
	saw_dotted := false
	for w in rows {
		if strings.contains(w.id, ".") {
			saw_dotted = true
		}
	}
	// Windows is full of multi-window processes (explorer, IME, ...); if none
	// appeared the id assignment is broken.
	testing.expect(t, saw_dotted)
}

@(test)
test_contains_ci :: proc(t: ^testing.T) {
	testing.expect(t, contains_ci("Program Manager", "program"))
	testing.expect(t, contains_ci("Program Manager", "MANAGER"))
	testing.expect(t, contains_ci("Slack - Workspace", "slack"))
	testing.expect(t, !contains_ci("abc", "xyz"))
}

@(test)
test_valid_detects_live_and_stale_handles :: proc(t: ^testing.T) {
	shell := win32.GetShellWindow()
	testing.expect(t, shell != nil)
	testing.expect(t, valid(shell))

	// A destroyed window's handle must read as stale.
	class_buf: [16]u16
	class := windows.utf8_to_wstring_buf(class_buf[:], "STATIC")
	hwnd := windows.CreateWindowExW(
		0,
		class,
		nil,
		0x40000000, // WS_CHILD
		0,
		0,
		1,
		1,
		shell,
		nil,
		nil,
		nil,
	)
	testing.expect(t, hwnd != nil)
	if hwnd != nil {
		testing.expect(t, valid(hwnd))
		windows.DestroyWindow(hwnd)
		testing.expect(t, !valid(hwnd))
	}
}
