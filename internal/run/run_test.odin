package run

import "core:strings"
import "core:testing"

// All run tests live in one serialized proc: they spawn child processes and
// flip the process-global WCU_ALLOW_RUN env var, so they must not run on
// parallel threads. See DESIGN.md (test at the seam).

@(test)
test_run_module_surface :: proc(t: ^testing.T) {
	set_approved_for_test(true)

	// Capture stdout from a direct command.
	stdout := run_command("cmd /c echo hello")
	testing.expect(t, stdout.Started)
	testing.expect(t, !stdout.Timed_Out)
	testing.expect(t, stdout.Exit_Code == 0)
	testing.expect(t, strings.contains(stdout.Stdout, "hello"))
	destroy(&stdout)

	// Capture stderr and a non-zero exit code.
	stderr := run_command("cmd /c echo err 1>&2 & exit 3")
	testing.expect(t, stderr.Started)
	testing.expect(t, stderr.Exit_Code == 3)
	testing.expect(t, strings.contains(stderr.Stderr, "err"))
	destroy(&stderr)

	// The approval gate denies when the env var is not set to "1".
	set_approved_for_test(false)
	testing.expect(t, !approved())

	// And allows when it is.
	set_approved_for_test(true)
	testing.expect(t, approved())

	// A directly-executed long process times out. A cmd wrapper would spawn a
	// grandchild that keeps the pipe open past the timeout.
	long := run_command("C:/Windows/System32/ping.exe -n 100 127.0.0.1", 200)
	testing.expect(t, long.Started)
	testing.expect(t, long.Timed_Out)
	destroy(&long)

	// A builtin (echo) is auto-wrapped in cmd /c.
	builtin := run_command("echo auto-wrapped")
	testing.expect(t, builtin.Started)
	testing.expect(t, builtin.Exit_Code == 0)
	testing.expect(t, strings.contains(builtin.Stdout, "auto-wrapped"))
	destroy(&builtin)

	// A real executable is not wrapped.
	direct := prepare_command("C:/Windows/System32/whoami.exe")
	testing.expect(t, strings.has_prefix(direct, "C:/Windows/System32/whoami.exe"))
	delete(direct)

	wrapped := prepare_command("echo hi")
	testing.expect(t, strings.has_prefix(wrapped, "cmd /c "))
	delete(wrapped)

	set_approved_for_test(false)
}
