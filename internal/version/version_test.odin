package version

import "core:testing"

@(test)
test_version_is_not_empty :: proc(t: ^testing.T) {
	testing.expect(t, len(VERSION) > 0)
}
