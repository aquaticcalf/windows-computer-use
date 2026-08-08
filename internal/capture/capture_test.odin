package capture

import "../win32"
import "core:testing"

@(test)
test_capture_shell_window :: proc(t: ^testing.T) {
	shell := win32.GetShellWindow()
	testing.expect(t, shell != nil)

	png, ok := capture_window(shell)
	testing.expect(t, ok)
	if !ok {
		return
	}
	defer delete(png)

	testing.expect(t, len(png) > 24)
	// PNG signature: 89 50 4E 47 0D 0A 1A 0A
	testing.expect(t, png[0] == 0x89)
	testing.expect(t, png[1] == 'P')
	testing.expect(t, png[2] == 'N')
	testing.expect(t, png[3] == 'G')
}
