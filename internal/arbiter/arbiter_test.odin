package arbiter

import "core:testing"

// fake_target builds a fake window handle for tests. The arbiter treats
// targets as opaque identities and never dereferences them, so these work
// without a real window.
fake_target :: proc(n: uintptr) -> Target {
	return Target(n)
}

// Logged_Frame records one executed frame plus the agent that ran it.
Logged_Frame :: struct {
	agent: Agent,
	frame: Frame,
}

// record_executor is the fake lane executor for tests: it appends each
// executed frame to the log behind e.data and always reports success.
record_executor :: proc(e: Executor, agent: Agent, frame: Frame) -> Error {
	log := (^[dynamic]Logged_Frame)(e.data)
	append(log, Logged_Frame{agent = agent, frame = frame})
	return .None
}

@(test)
test_claim_grants_exclusive_ownership :: proc(t: ^testing.T) {
	a: Arbiter
	defer destroy(&a)

	agent := Agent("agent-a")
	target := fake_target(0x1234)

	testing.expect(t, claim(&a, agent, target) == .None)
	testing.expect(t, count(&a) == 1)
	testing.expect(t, owned(&a, agent, target))

	owner, ok := owner_of(&a, target)
	testing.expect(t, ok)
	testing.expect(t, owner == agent)
}

@(test)
test_second_agent_claim_is_rejected :: proc(t: ^testing.T) {
	a: Arbiter
	defer destroy(&a)

	agent_a := Agent("agent-a")
	agent_b := Agent("agent-b")
	target := fake_target(0x2345)

	testing.expect(t, claim(&a, agent_a, target) == .None)
	testing.expect(t, claim(&a, agent_b, target) == .Target_Owned)
	// The first owner keeps its claim.
	testing.expect(t, owned(&a, agent_a, target))
	testing.expect(t, count(&a) == 1)
}

@(test)
test_reclaim_by_same_agent_is_noop :: proc(t: ^testing.T) {
	a: Arbiter
	defer destroy(&a)

	agent := Agent("agent")
	target := fake_target(0x3456)

	testing.expect(t, claim(&a, agent, target) == .None)
	testing.expect(t, claim(&a, agent, target) == .None)
	testing.expect(t, count(&a) == 1)
}

@(test)
test_distinct_targets_are_independent :: proc(t: ^testing.T) {
	a: Arbiter
	defer destroy(&a)

	agent_a := Agent("agent-a")
	agent_b := Agent("agent-b")
	t1 := fake_target(0x4567)
	t2 := fake_target(0x5678)

	testing.expect(t, claim(&a, agent_a, t1) == .None)
	testing.expect(t, claim(&a, agent_b, t2) == .None)
	testing.expect(t, count(&a) == 2)
	testing.expect(t, owned(&a, agent_a, t1))
	testing.expect(t, owned(&a, agent_b, t2))
}

@(test)
test_release_frees_targets_and_errors_on_none :: proc(t: ^testing.T) {
	a: Arbiter
	defer destroy(&a)

	agent := Agent("agent")
	t1 := fake_target(0x6789)
	t2 := fake_target(0x789a)

	testing.expect(t, claim(&a, agent, t1) == .None)
	testing.expect(t, claim(&a, agent, t2) == .None)

	testing.expect(t, release(&a, Agent("nobody")) == .Not_Found)

	testing.expect(t, release(&a, agent) == .None)
	testing.expect(t, count(&a) == 0)
	_, ok := owner_of(&a, t1)
	testing.expect(t, !ok)
	// Releasing again finds nothing.
	testing.expect(t, release(&a, agent) == .Not_Found)
}

@(test)
test_release_target_drops_single_target :: proc(t: ^testing.T) {
	a: Arbiter
	defer destroy(&a)

	agent_a := Agent("agent-a")
	agent_b := Agent("agent-b")
	t1 := fake_target(0x89ab)
	t2 := fake_target(0x9abc)

	testing.expect(t, claim(&a, agent_a, t1) == .None)
	testing.expect(t, claim(&a, agent_b, t2) == .None)

	testing.expect(t, release_target(&a, t1) == .None)
	testing.expect(t, release_target(&a, t1) == .Not_Found)
	testing.expect(t, !owned(&a, agent_a, t1))
	// Unrelated ownership survives.
	testing.expect(t, owned(&a, agent_b, t2))
}

@(test)
test_two_agents_interleave_without_cross_talk :: proc(t: ^testing.T) {
	a: Arbiter
	defer destroy(&a)

	log: [dynamic]Logged_Frame
	defer delete(log)
	exec := Executor {
		data = &log,
		run  = record_executor,
	}

	agent_a := Agent("agent-a")
	agent_b := Agent("agent-b")
	slack := fake_target(0xa000)
	notes := fake_target(0xb000)

	// Both agents queue actions on their own windows.
	testing.expect(
		t,
		push(&a, agent_a, Frame{lane = .Uia, target = slack, op = .Type, text = "hello"}) == .None,
	)
	testing.expect(
		t,
		push(&a, agent_a, Frame{lane = .Uia, target = slack, op = .Key, text = "ctrl+s"}) == .None,
	)
	testing.expect(t, push(&a, agent_b, Frame{lane = .Cdp, target = notes, op = .Click}) == .None)

	// B cannot queue anything that targets A's window.
	testing.expect(
		t,
		push(&a, agent_b, Frame{lane = .Uia, target = slack, op = .Click}) == .Target_Owned,
	)

	// Interleaved execution: each agent only ever runs its own frames.
	testing.expect(t, execute(&a, exec, agent_a) == .None)
	testing.expect(t, execute(&a, exec, agent_b) == .None)
	testing.expect(t, execute(&a, exec, agent_a) == .None)
	testing.expect(t, execute(&a, exec, agent_a) == .Empty)
	testing.expect(t, execute(&a, exec, agent_b) == .Empty)

	testing.expect(t, len(log) == 3)
	// Execution interleaved, but each entry is tagged with its own agent and
	// its own window, in per-agent push order.
	testing.expect(t, log[0].agent == agent_a)
	testing.expect(t, log[0].frame.target == slack)
	testing.expect(t, log[0].frame.op == .Type)
	testing.expect(t, log[1].agent == agent_b)
	testing.expect(t, log[1].frame.target == notes)
	testing.expect(t, log[1].frame.op == .Click)
	testing.expect(t, log[2].agent == agent_a)
	testing.expect(t, log[2].frame.target == slack)
	testing.expect(t, log[2].frame.op == .Key)
	// No logged frame touched the other agent's window.
	for entry in log {
		testing.expect(t, (entry.agent == agent_a) == (entry.frame.target == slack))
	}
}

@(test)
test_execute_runs_frames_in_push_order :: proc(t: ^testing.T) {
	a: Arbiter
	defer destroy(&a)

	log: [dynamic]Logged_Frame
	defer delete(log)
	exec := Executor {
		data = &log,
		run  = record_executor,
	}

	agent := Agent("agent")
	target := fake_target(0xc000)

	ops := [3]Op{.Wake, .Type, .Key}
	for op in ops {
		testing.expect(t, push(&a, agent, Frame{lane = .Uia, target = target, op = op}) == .None)
	}

	for i in 0 ..< len(ops) {
		testing.expect(t, execute(&a, exec, agent) == .None)
		testing.expect(t, log[i].frame.op == ops[i])
	}
	testing.expect(t, pending(&a, agent) == 0)
}

@(test)
test_pause_blocks_execution_until_resume :: proc(t: ^testing.T) {
	a: Arbiter
	defer destroy(&a)

	log: [dynamic]Logged_Frame
	defer delete(log)
	exec := Executor {
		data = &log,
		run  = record_executor,
	}

	agent := Agent("agent")
	target := fake_target(0xd000)

	testing.expect(t, push(&a, agent, Frame{lane = .Uia, target = target, op = .Click}) == .None)
	testing.expect(t, push(&a, agent, Frame{lane = .Uia, target = target, op = .Click}) == .None)

	testing.expect(t, pause(&a, agent) == .None)
	testing.expect(t, is_paused(&a, agent))
	testing.expect(t, execute(&a, exec, agent) == .Paused)
	// Paused execution keeps the queue untouched.
	testing.expect(t, pending(&a, agent) == 2)
	testing.expect(t, len(log) == 0)

	testing.expect(t, resume(&a, agent) == .None)
	testing.expect(t, !is_paused(&a, agent))
	testing.expect(t, execute(&a, exec, agent) == .None)
	testing.expect(t, execute(&a, exec, agent) == .None)
	testing.expect(t, pending(&a, agent) == 0)
	testing.expect(t, execute(&a, exec, agent) == .Empty)

	// Resuming an unpaused agent is a no-op.
	testing.expect(t, resume(&a, agent) == .None)
}

@(test)
test_pause_resume_require_known_agent :: proc(t: ^testing.T) {
	a: Arbiter
	defer destroy(&a)

	testing.expect(t, pause(&a, Agent("ghost")) == .Not_Found)
	testing.expect(t, resume(&a, Agent("ghost")) == .Not_Found)
}

@(test)
test_execute_reports_not_owner_after_release :: proc(t: ^testing.T) {
	a: Arbiter
	defer destroy(&a)

	log: [dynamic]Logged_Frame
	defer delete(log)
	exec := Executor {
		data = &log,
		run  = record_executor,
	}

	agent := Agent("agent")
	target := fake_target(0xe000)

	testing.expect(t, push(&a, agent, Frame{lane = .Uia, target = target, op = .Click}) == .None)
	// The target is released (e.g. the window closed) before it executes.
	testing.expect(t, release_target(&a, target) == .None)

	testing.expect(t, execute(&a, exec, agent) == .Not_Owner)
	// The stale frame is consumed, so the queue cannot stall.
	testing.expect(t, pending(&a, agent) == 0)
	testing.expect(t, len(log) == 0)
}

@(test)
test_execute_on_unknown_agent_is_empty :: proc(t: ^testing.T) {
	a: Arbiter
	defer destroy(&a)

	exec := Executor {
		data = nil,
		run  = record_executor,
	}
	testing.expect(t, execute(&a, exec, Agent("ghost")) == .Empty)
	testing.expect(t, pending(&a, Agent("ghost")) == 0)
}
