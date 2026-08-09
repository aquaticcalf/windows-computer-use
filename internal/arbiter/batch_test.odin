package arbiter

import "core:strings"
import "core:testing"

// Fake_World simulates an app's visible tree (content) plus a log of every
// frame the fake lane executed.
Fake_World :: struct {
	content: [dynamic]string,
	log:     [dynamic]Logged_Frame,
}

// world_destroy frees a Fake_World.
world_destroy :: proc(w: ^Fake_World) {
	for line in w.content {
		delete(line)
	}
	delete(w.content)
	delete(w.log)
}

// world_executor simulates a lane: Type/Key/Click make text appear in the
// world, and Wait_Until checks whether its match text is present, failing
// with Not_Met otherwise. This lets batch semantics be exercised end to end.
world_executor :: proc(e: Executor, agent: Agent, frame: Frame) -> Error {
	w := (^Fake_World)(e.data)
	append(&w.log, Logged_Frame{agent = agent, frame = frame})
	switch frame.op {
	case .Type, .Key, .Click:
		if frame.text != "" {
			append(&w.content, strings.clone(frame.text))
		}
	case .Wait_Until:
		for line in w.content {
			if line == frame.text {
				return .None
			}
		}
		return .Not_Met
	case .Scroll, .Set_Value, .Focus, .Wake:
	// no simulated effect
	}
	return .None
}

// fail_first_executor fails on its first call, then succeeds.
fail_first_executor :: proc(e: Executor, agent: Agent, frame: Frame) -> Error {
	calls := (^i32)(e.data)
	calls^ += 1
	if calls^ == 1 {
		return .Execution_Failed
	}
	return .None
}

@(test)
test_batch_succeeds_when_condition_is_met :: proc(t: ^testing.T) {
	a: Arbiter
	defer destroy(&a)
	w := Fake_World{}
	defer world_destroy(&w)
	exec := Executor {
		data = &w,
		run  = world_executor,
	}
	agent := Agent("agent")
	target := fake_target(0xf00)

	batch := [2]Frame {
		{lane = .Uia, target = target, op = .Type, text = "hello"},
		{lane = .Uia, target = target, op = .Wait_Until, text = "hello"},
	}
	testing.expect(t, push_batch(&a, agent, batch[:]) == .None)

	testing.expect(t, execute(&a, exec, agent) == .None)
	testing.expect(t, execute(&a, exec, agent) == .None)
	testing.expect(t, execute(&a, exec, agent) == .Empty)
	testing.expect(t, pending(&a, agent) == 0)
}

@(test)
test_batch_fails_fast_when_condition_is_not_met :: proc(t: ^testing.T) {
	a: Arbiter
	defer destroy(&a)
	w := Fake_World{}
	defer world_destroy(&w)
	exec := Executor {
		data = &w,
		run  = world_executor,
	}
	agent := Agent("agent")
	target := fake_target(0x1000)

	batch := [3]Frame {
		{lane = .Uia, target = target, op = .Click},
		{lane = .Uia, target = target, op = .Wait_Until, text = "menu"},
		{lane = .Uia, target = target, op = .Click, text = "menu-item"},
	}
	testing.expect(t, push_batch(&a, agent, batch[:]) == .None)

	testing.expect(t, execute(&a, exec, agent) == .None)
	// The condition was not met, so the batch fails fast.
	testing.expect(t, execute(&a, exec, agent) == .Not_Met)
	// The rest of the batch was dropped; the queue is now empty.
	testing.expect(t, execute(&a, exec, agent) == .Empty)
	testing.expect(t, pending(&a, agent) == 0)
	// The dropped frame never ran.
	testing.expect(t, len(w.log) == 2)
}

@(test)
test_failed_batch_does_not_affect_other_agents :: proc(t: ^testing.T) {
	a: Arbiter
	defer destroy(&a)
	w := Fake_World{}
	defer world_destroy(&w)
	exec := Executor {
		data = &w,
		run  = world_executor,
	}
	agent_a := Agent("agent-a")
	agent_b := Agent("agent-b")
	t1 := fake_target(0x1100)
	t2 := fake_target(0x1200)

	batch := [2]Frame {
		{lane = .Uia, target = t1, op = .Wait_Until, text = "missing"},
		{lane = .Uia, target = t1, op = .Click, text = "dropped"},
	}
	testing.expect(t, push_batch(&a, agent_a, batch[:]) == .None)
	testing.expect(
		t,
		push(&a, agent_b, Frame{lane = .Uia, target = t2, op = .Click, text = "b-action"}) ==
		.None,
	)

	testing.expect(t, execute(&a, exec, agent_a) == .Not_Met)
	// Agent B's queue is untouched by A's failed batch.
	testing.expect(t, execute(&a, exec, agent_b) == .None)
	testing.expect(t, pending(&a, agent_b) == 0)
}

@(test)
test_failed_standalone_frame_does_not_drop_others :: proc(t: ^testing.T) {
	a: Arbiter
	defer destroy(&a)
	calls: i32
	exec := Executor {
		data = &calls,
		run  = fail_first_executor,
	}
	agent := Agent("agent")
	target := fake_target(0x1300)

	testing.expect(t, push(&a, agent, Frame{lane = .Uia, target = target, op = .Click}) == .None)
	testing.expect(t, push(&a, agent, Frame{lane = .Uia, target = target, op = .Click}) == .None)

	testing.expect(t, execute(&a, exec, agent) == .Execution_Failed)
	// A standalone failure leaves the rest of the queue alone.
	testing.expect(t, execute(&a, exec, agent) == .None)
	testing.expect(t, pending(&a, agent) == 0)
}
