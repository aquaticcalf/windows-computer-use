package session

import "core:fmt"
import "core:os"
import "core:path/filepath"
import "core:sync"
import "core:sys/windows"
import "core:testing"
import "core:time"

// scratch_counter makes each test's registry file unique, even though the
// test runner runs tests on several threads at once.
scratch_counter: u64

// scratch_path builds a unique registry file path under the OS temp dir. The
// returned string is owned by the caller.
scratch_path :: proc() -> string {
	n := sync.atomic_add(&scratch_counter, 1)
	temp := os.get_env("TEMP", context.allocator)
	defer delete(temp)
	dir, _ := filepath.join(
		[]string{temp, fmt.tprintf("wcu-session-test-%d", n)},
		context.allocator,
	)
	defer delete(dir)
	path, _ := filepath.join([]string{dir, "sessions.json"}, context.allocator)
	return path
}

@(test)
test_register_and_get_round_trip :: proc(t: ^testing.T) {
	reg_path := scratch_path()
	reg, err := open(reg_path)
	testing.expect(t, err == .None)
	defer destroy(&reg)
	defer delete(reg_path)
	defer os.remove(reg_path)

	rec := Record {
		id      = "agent-1",
		pid     = 4242,
		target  = 0x1234,
		pending = 3,
		paused  = false,
		started = time.to_unix_seconds(time.now()),
	}
	testing.expect(t, register(&reg, rec) == .None)

	got, ok := get(&reg, "agent-1")
	testing.expect(t, ok)
	testing.expect(t, got.pid == 4242)
	testing.expect(t, got.target == 0x1234)
	testing.expect(t, got.pending == 3)
	testing.expect(t, got.paused == false)
}

@(test)
test_registry_persists_across_open :: proc(t: ^testing.T) {
	reg_path := scratch_path()
	defer delete(reg_path)
	defer os.remove(reg_path)

	{
		reg, err := open(reg_path)
		testing.expect(t, err == .None)
		defer destroy(&reg)
		testing.expect(
			t,
			register(&reg, Record{id = "agent-a", pid = 1111, target = 0x100}) == .None,
		)
		testing.expect(
			t,
			register(&reg, Record{id = "agent-b", pid = 2222, target = 0x200}) == .None,
		)
	}

	// A fresh registry reads back the two sessions, like `wcu status` does.
	reg, err := open(reg_path)
	testing.expect(t, err == .None)
	defer destroy(&reg)
	recs := list(&reg)
	defer delete(recs)
	testing.expect(t, len(recs) == 2)
	_, ok := get(&reg, "agent-a")
	testing.expect(t, ok)
	_, ok = get(&reg, "agent-b")
	testing.expect(t, ok)
}

@(test)
test_unregister_removes_session :: proc(t: ^testing.T) {
	reg_path := scratch_path()
	reg, err := open(reg_path)
	testing.expect(t, err == .None)
	defer destroy(&reg)
	defer delete(reg_path)
	defer os.remove(reg_path)

	testing.expect(t, register(&reg, Record{id = "agent-1", pid = 1, target = 0x100}) == .None)
	testing.expect(t, unregister(&reg, "agent-1") == .None)
	testing.expect(t, unregister(&reg, "agent-1") == .Not_Found)
	_, ok := get(&reg, "agent-1")
	testing.expect(t, !ok)
	testing.expect(t, len(list(&reg)) == 0)
}

@(test)
test_update_mutates_and_persists :: proc(t: ^testing.T) {
	reg_path := scratch_path()
	reg, err := open(reg_path)
	testing.expect(t, err == .None)
	defer destroy(&reg)
	defer delete(reg_path)
	defer os.remove(reg_path)

	testing.expect(
		t,
		register(&reg, Record{id = "agent-1", pid = 1, target = 0x100, pending = 2}) == .None,
	)
	testing.expect(
		t,
		update(&reg, "agent-1", proc(rec: ^Record) {rec.pending = 5; rec.paused = true}) == .None,
	)
	testing.expect(t, update(&reg, "ghost", proc(rec: ^Record) {}) == .Not_Found)

	got, ok := get(&reg, "agent-1")
	testing.expect(t, ok)
	testing.expect(t, got.pending == 5)
	testing.expect(t, got.paused == true)
}

@(test)
test_active_filters_dead_sessions :: proc(t: ^testing.T) {
	reg_path := scratch_path()
	reg, err := open(reg_path)
	testing.expect(t, err == .None)
	defer destroy(&reg)
	defer delete(reg_path)
	defer os.remove(reg_path)

	// Our own pid is alive; a pid nobody owns is dead.
	testing.expect(
		t,
		register(
			&reg,
			Record{id = "alive", pid = windows.GetCurrentProcessId(), target = 0x100},
		) ==
		.None,
	)
	testing.expect(t, register(&reg, Record{id = "dead", pid = 99999999, target = 0x200}) == .None)

	active_sessions := active(&reg)
	defer delete(active_sessions)
	testing.expect(t, len(active_sessions) == 1)
	testing.expect(t, active_sessions[0].id == "alive")
}

@(test)
test_pid_alive_is_true_for_self :: proc(t: ^testing.T) {
	testing.expect(t, pid_alive(windows.GetCurrentProcessId()))
	testing.expect(t, !pid_alive(99999999))
	testing.expect(t, !pid_alive(0))
}
