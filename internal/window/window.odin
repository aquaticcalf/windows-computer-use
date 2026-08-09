package window

import "../win32"
import "core:fmt"
import "core:strconv"
import "core:strings"
import "core:sys/windows"

// Window discovery and geometry helpers, plus the foreground trick. This is a
// small domain module over raw user32; keep the COM/UIA concerns elsewhere.
// See ARCHITECTURE.md (list_apps, focus) and DESIGN.md.

// Window describes one top-level window captured by list.
Window :: struct {
	handle:  windows.HWND,
	title:   string,
	pid:     u32,
	visible: bool,
	// Id is a stable identifier for this window: the pid when unique, or
	// "pid.index" when a process owns several top-level windows. It survives
	// title changes, unlike matching on title text.
	id:      string,
}

// Rect is an axis-aligned rectangle in screen coordinates.
Rect :: struct {
	left, top, right, bottom: i32,
}

// list enumerates top-level windows. The returned slice and its title strings
// are allocated with the supplied allocator; the caller owns them.
list :: proc(allocator := context.allocator) -> (result: []Window, ok: bool) {
	capacity := 1024
	buffer, berr := make([]windows.HWND, capacity, allocator)
	if berr != nil {
		return nil, false
	}
	defer delete(buffer)

	count: int
	collector := collect_context {
		handles  = raw_data(buffer),
		count    = &count,
		capacity = capacity,
	}
	windows.EnumWindows(collect_cb, windows.LPARAM(uintptr(&collector)))

	rows, rerr := make([]Window, count, allocator)
	if rerr != nil {
		return nil, false
	}
	result = rows
	for i in 0 ..< count {
		hwnd := buffer[i]
		result[i] = Window {
			handle  = hwnd,
			title   = title_of(hwnd, allocator),
			pid     = pid_of(hwnd),
			visible = bool(windows.IsWindowVisible(hwnd)),
		}
	}
	assign_ids(rows, allocator)
	return result, true
}

// assign_ids stamps each window with a stable id: the bare pid when a process
// owns exactly one top-level window, otherwise "pid.index" for the Nth window
// of that process.
assign_ids :: proc(rows: []Window, allocator := context.allocator) {
	for i in 0 ..< len(rows) {
		if pid_window_count(rows, rows[i].pid) == 1 {
			rows[i].id = fmt.aprintf("%d", rows[i].pid, allocator = allocator)
		} else {
			index := pid_window_index(rows, i, rows[i].pid)
			rows[i].id = fmt.aprintf("%d.%d", rows[i].pid, index, allocator = allocator)
		}
	}
}

// pid_window_count returns how many rows belong to the given process.
pid_window_count :: proc(rows: []Window, pid: u32) -> int {
	count := 0
	for w in rows {
		if w.pid == pid {
			count += 1
		}
	}
	return count
}

// pid_window_index returns the position of rows[i] among the windows of its
// own process (0-based), which anchors the ".index" part of the id.
pid_window_index :: proc(rows: []Window, i: int, pid: u32) -> int {
	index := 0
	for j in 0 ..< i {
		if rows[j].pid == pid {
			index += 1
		}
	}
	return index
}

// find returns the first window whose title contains the given substring.
find :: proc(windows_: []Window, substring: string) -> (Window, bool) {
	for w in windows_ {
		if strings.contains(w.title, substring) {
			return w, true
		}
	}
	return {}, false
}

// resolve finds a top-level window for an app query. The query is either an
// internal window id ("1234" or "1234.2"), a numeric pid, or a
// case-insensitive substring of a window title. Returns nil when nothing
// matches.
resolve :: proc(app_query: string, allocator := context.allocator) -> (windows.HWND, bool) {
	rows, listed := list(allocator)
	if !listed {
		return nil, false
	}
	defer destroy(rows, allocator)

	if id_match, id_ok := resolve_by_id(rows, app_query); id_ok {
		return id_match, true
	}

	if pid, parsed := strconv.parse_u64(app_query, 10); parsed {
		for w in rows {
			if u32(pid) == w.pid {
				return w.handle, true
			}
		}
		return nil, false
	}

	for w in rows {
		if contains_ci(w.title, app_query) {
			return w.handle, true
		}
	}
	return nil, false
}

// resolve_by_id matches a window id ("1234" or "1234.2") against the id
// stamped by assign_ids. Bare ids are accepted for single-window processes;
// dotted ids pick the Nth window of a process.
resolve_by_id :: proc(rows: []Window, query: string) -> (windows.HWND, bool) {
	if len(query) == 0 {
		return nil, false
	}
	for w in rows {
		if w.id == query {
			return w.handle, true
		}
	}
	return nil, false
}

// contains_ci reports whether hay contains needle, case-insensitively, for
// ASCII text.
contains_ci :: proc(hay, needle: string) -> bool {
	if len(needle) == 0 {
		return true
	}
	if len(hay) < len(needle) {
		return false
	}
	for i in 0 ..= len(hay) - len(needle) {
		match := true
		for j in 0 ..< len(needle) {
			if to_lower(hay[i + j]) != to_lower(needle[j]) {
				match = false
				break
			}
		}
		if match {
			return true
		}
	}
	return false
}

// to_lower lowercases an ASCII byte.
to_lower :: proc(b: byte) -> byte {
	if 'A' <= b && b <= 'Z' {
		return b + ('a' - 'A')
	}
	return b
}

// destroy frees a window list produced by list, including its title and id
// strings.
destroy :: proc(windows_: []Window, allocator := context.allocator) {
	for w in windows_ {
		delete(w.title, allocator)
		delete(w.id, allocator)
	}
	delete(windows_, allocator)
}

// title returns a window's title text, allocated with the supplied allocator.
title :: proc(hwnd: windows.HWND, allocator := context.allocator) -> string {
	return title_of(hwnd, allocator)
}

// valid reports whether a window handle still names a live window. Handles go
// stale when an app closes or recreates its window; callers should re-resolve
// before acting when this returns false.
valid :: proc(hwnd: windows.HWND) -> bool {
	return bool(windows.IsWindow(hwnd))
}

// rect returns a window's bounding rectangle in screen coordinates.
rect :: proc(hwnd: windows.HWND) -> (Rect, bool) {
	r: windows.RECT
	if windows.GetWindowRect(hwnd, &r) {
		return Rect{left = r.left, top = r.top, right = r.right, bottom = r.bottom}, true
	}
	return {}, false
}

// force_foreground brings a window to the foreground even from a background
// process, beating the foreground lock, then verifies the result. Maximized
// windows keep their geometry; only minimized windows are restored.
force_foreground :: proc(hwnd: windows.HWND) -> bool {
	foreground := windows.GetForegroundWindow()
	if foreground == hwnd {
		return true
	}

	foreground_thread := windows.GetWindowThreadProcessId(foreground, nil)
	my_thread := windows.GetCurrentThreadId()
	if win32.AttachThreadInput(foreground_thread, my_thread, true) {
		if bool(windows.IsIconic(hwnd)) {
			windows.ShowWindow(hwnd, win32.SW_RESTORE)
		}
		windows.SetForegroundWindow(hwnd)
		win32.AttachThreadInput(foreground_thread, my_thread, false)
	}
	return windows.GetForegroundWindow() == hwnd
}

// wake sends WM_GETOBJECT (OBJID_CLIENT) to a window and all of its descendant
// child windows, prompting Chromium-based apps to materialize their UIA tree.
// It posts messages without waiting so it never blocks on a hung window.
wake :: proc(hwnd: windows.HWND) -> int {
	ctx := wake_context {
		count = 0,
	}
	windows.PostMessageW(hwnd, win32.WM_GETOBJECT, 0, win32.OBJID_CLIENT)
	ctx.count += 1
	windows.EnumChildWindows(hwnd, wake_cb, windows.LPARAM(uintptr(&ctx)))
	return ctx.count
}

// wake_context carries the message counter for wake.
wake_context :: struct {
	count: int,
}

// wake_cb posts WM_GETOBJECT to one child window.
wake_cb :: proc "system" (child: windows.HWND, lparam: windows.LPARAM) -> windows.BOOL {
	ctx := (^wake_context)(uintptr(lparam))
	windows.PostMessageW(child, win32.WM_GETOBJECT, 0, win32.OBJID_CLIENT)
	ctx.count += 1
	return windows.BOOL(true)
}

// collect_context carries the scratch buffer and cursor for the EnumWindows
// callback. It exists to keep the callback allocation-free.
collect_context :: struct {
	handles:  [^]windows.HWND,
	count:    ^int,
	capacity: int,
}

// collect_cb appends one top-level window handle into the collect_context.
collect_cb :: proc "system" (hwnd: windows.HWND, lparam: windows.LPARAM) -> windows.BOOL {
	c := (^collect_context)(uintptr(lparam))
	if c.count^ < c.capacity {
		c.handles[c.count^] = hwnd
		c.count^ += 1
	}
	return windows.BOOL(true)
}

// title_of reads a window title into a UTF-8 string on the given allocator.
title_of :: proc(hwnd: windows.HWND, allocator := context.allocator) -> string {
	buf: [1024]u16
	length := windows.GetWindowTextW(hwnd, &buf[0], 1024)
	if length <= 0 {
		return ""
	}
	text, _ := windows.wstring_to_utf8_alloc(windows.wstring(&buf[0]), int(length), allocator)
	return text
}

// pid_of returns the process id that owns a window.
pid_of :: proc(hwnd: windows.HWND) -> u32 {
	pid: u32
	windows.GetWindowThreadProcessId(hwnd, &pid)
	return pid
}
