package win32

import "core:sys/windows"

// Constants and bindings absent from core:sys/windows but needed by wcu.
// See issue #7. Keep this list minimal and documented.

foreign import user32 "system:User32.lib"

@(default_calling_convention = "system")
foreign user32 {
	// Beats the Windows foreground lock so a background window can take input focus.
	AttachThreadInput :: proc(id_attach, id_attach_to: windows.DWORD, f_attach: windows.BOOL) -> windows.BOOL ---
	// Shell desktop window (Program Manager); useful as a stable UIA test target.
	GetShellWindow :: proc() -> windows.HWND ---
}

// WM_GETOBJECT lParam used to wake Chromium accessibility on a window.
OBJID_CLIENT :: 0xFFFFFFFC

// KEYEVENTF_* flags for SendInput keyboard events.
KEYEVENTF_KEYUP :: 0x0002
// KEYEVENTF_UNICODE marks a scan-code based (text) key event.
KEYEVENTF_UNICODE :: 0x0004
// KEYEVENTF_EXTENDEDKEY marks an extended keyboard key.
KEYEVENTF_EXTENDEDKEY :: 0x0001

// ShowWindow commands.
SW_RESTORE :: 9

// WM_GETOBJECT message id (also present in window_messages.odin as WM_GETOBJECT).
WM_GETOBJECT :: 0x003D

// CreateProcess creation flags: do not open a new console window for the child.
CREATE_NO_WINDOW :: 0x08000000

// STILL_ACTIVE is the exit code reported while a process is still running.
STILL_ACTIVE :: 259
