package arbiter

import "core:testing"

// fake_target builds a fake window handle for tests. The arbiter treats
// targets as opaque identities and never dereferences them, so these work
// without a real window.
fake_target :: proc(n: uintptr) -> Target {
	return Target(n)
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
