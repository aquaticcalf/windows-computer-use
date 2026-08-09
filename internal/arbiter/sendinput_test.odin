package arbiter

import "core:sync"
import "core:sys/windows"
import "core:testing"
import "core:thread"

// Serialization_Counters tracks concurrent access to a fake lane executor.
Serialization_Counters :: struct {
	// inside is the number of threads currently in the lane.
	inside: i32,
	// peak is the largest value inside has ever reached.
	peak:   i32,
	// total is how many times the lane ran in total.
	total:  i32,
}

// serialization_probe is a fake lane executor that records how many threads
// are inside it at once and widens the race window with a short sleep. The
// wrapped executor is what guarantees only one thread is ever inside.
serialization_probe :: proc(e: Executor, agent: Agent, frame: Frame) -> Error {
	c := (^Serialization_Counters)(e.data)
	inside := sync.atomic_add(&c.inside, 1) + 1
	defer sync.atomic_add(&c.inside, -1)

	for {
		cur := sync.atomic_load(&c.peak)
		if inside <= cur {
			break
		}
		if _, swapped := sync.atomic_compare_exchange_strong(&c.peak, cur, inside); swapped {
			break
		}
	}
	sync.atomic_add(&c.total, 1)
	windows.Sleep(1)
	return .None
}

// Worker_Context carries one thread's executor, agent, and frame.
Worker_Context :: struct {
	exec:       Executor,
	agent:      Agent,
	iterations: int,
	frame:      Frame,
}

// worker runs the executor repeatedly, the way a concurrent agent would.
worker :: proc(t: ^thread.Thread) {
	ctx := (^Worker_Context)(t.data)
	for _ in 0 ..< ctx.iterations {
		err := ctx.exec.run(ctx.exec, ctx.agent, ctx.frame)
		assert(err == .None)
	}
}

@(test)
test_sendinput_executor_forwards_to_inner :: proc(t: ^testing.T) {
	log: [dynamic]Logged_Frame
	defer delete(log)
	inner := Executor {
		data = &log,
		run  = lane_log_executor,
	}
	wrapped := sendinput_executor(inner)
	defer free((^SendInput_Wrapper)(wrapped.data))

	agent := Agent("agent")
	frame := Frame {
		lane   = .SendInput,
		target = fake_target(0xb00),
		op     = .Click,
	}
	testing.expect(t, wrapped.run(wrapped, agent, frame) == .None)

	testing.expect(t, len(log) == 1)
	testing.expect(t, log[0].agent == agent)
	testing.expect(t, log[0].frame.lane == .SendInput)
}

@(test)
test_sendinput_lane_serializes_concurrent_agents :: proc(t: ^testing.T) {
	counters := Serialization_Counters{}
	inner := Executor {
		data = &counters,
		run  = serialization_probe,
	}
	wrapped := sendinput_executor(inner)
	defer free((^SendInput_Wrapper)(wrapped.data))

	threads := 4
	iterations := 25

	ctxs := make([]Worker_Context, threads)
	defer delete(ctxs)
	ts := make([]^thread.Thread, threads)
	defer delete(ts)
	for i in 0 ..< threads {
		ctxs[i] = Worker_Context {
			exec = wrapped,
			agent = Agent("agent"),
			iterations = iterations,
			frame = Frame {
				lane = .SendInput,
				target = fake_target(uintptr(i) + 0xa00),
				op = .Click,
			},
		}
		ts[i] = thread.create(worker)
		ts[i].data = &ctxs[i]
		thread.start(ts[i])
	}
	for i in 0 ..< threads {
		thread.join(ts[i])
	}
	for i in 0 ..< threads {
		thread.destroy(ts[i])
	}

	testing.expect(t, sync.atomic_load(&counters.total) == i32(threads * iterations))
	// At most one agent was inside the lane at any instant.
	testing.expect(t, sync.atomic_load(&counters.peak) == 1)
}

@(test)
test_set_lane_wraps_sendinput_in_global_lock :: proc(t: ^testing.T) {
	r := Router{}
	base := Executor {
		data = nil,
		run  = lane_log_executor,
	}

	set_lane(&r, .SendInput, base)
	testing.expect(t, r.lanes[.SendInput].run == sendinput_run)
	defer free((^SendInput_Wrapper)(r.lanes[.SendInput].data))

	// Non-physical lanes are installed unwrapped.
	set_lane(&r, .Uia, base)
	testing.expect(t, r.lanes[.Uia].run == lane_log_executor)
}
