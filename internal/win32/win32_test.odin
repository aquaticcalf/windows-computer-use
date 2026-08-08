package win32

import "core:testing"

@(test)
test_objid_client :: proc(t: ^testing.T) {
	testing.expect(t, OBJID_CLIENT == 0xFFFFFFFC)
}

@(test)
test_keyevent_flags :: proc(t: ^testing.T) {
	testing.expect(t, KEYEVENTF_KEYUP == 0x0002)
	testing.expect(t, KEYEVENTF_UNICODE == 0x0004)
	testing.expect(t, KEYEVENTF_EXTENDEDKEY == 0x0001)
}

@(test)
test_sw_restore :: proc(t: ^testing.T) {
	testing.expect(t, SW_RESTORE == 9)
}

@(test)
test_wm_getobject :: proc(t: ^testing.T) {
	testing.expect(t, WM_GETOBJECT == 0x003D)
}
