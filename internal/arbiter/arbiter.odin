package arbiter

// The arbiter owns the target ownership map: at most one agent may claim a
// target at a time, which prevents two agents from driving the same window
// and fighting over it. It is the single owner of concurrency decisions in
// wcu; per-agent stacks, the lane router, and the SendInput lock build on
// top of it. See ARCHITECTURE.md (Input Stack System) and DESIGN.md.

import "core:sys/windows"

// Agent identifies a client that drives targets: an MCP session id, a CLI
// invocation, or a worker process.
Agent :: distinct string

// Target is an opaque window identity that an agent claims exclusively. The
// arbiter never dereferences handles, so it stays testable with fake ids.
Target :: windows.HWND

// Arbiter tracks which agent owns each claimed target. The zero value is an
// empty, usable arbiter; destroy releases its map.
Arbiter :: struct {
	// owners maps each claimed target to its exclusive agent.
	owners: map[Target]Agent,
}

// Error is this package's error type.
Error :: enum {
	// None reports a successful claim or release.
	None,
	// Target_Owned reports that a different agent already owns the target.
	Target_Owned,
	// Not_Found reports that a release matched no owned target.
	Not_Found,
}

// destroy releases the arbiter's ownership map.
destroy :: proc(a: ^Arbiter) {
	if a.owners != nil {
		delete(a.owners)
		a.owners = nil
	}
}

// claim gives agent exclusive ownership of target. Claiming a target the
// agent already owns succeeds as a no-op. Claiming a target owned by a
// different agent fails with Target_Owned and leaves the current owner
// untouched.
claim :: proc(a: ^Arbiter, agent: Agent, target: Target) -> Error {
	if a.owners == nil {
		a.owners = make(map[Target]Agent)
	}
	if owner, ok := a.owners[target]; ok {
		if owner == agent {
			return .None
		}
		return .Target_Owned
	}
	a.owners[target] = agent
	return .None
}

// release drops every target claimed by agent. It returns Not_Found when the
// agent owned no targets.
release :: proc(a: ^Arbiter, agent: Agent) -> Error {
	owned: [dynamic]Target
	defer delete(owned)
	for target, owner in a.owners {
		if owner == agent {
			append(&owned, target)
		}
	}
	if len(owned) == 0 {
		return .Not_Found
	}
	for target in owned {
		delete_key(&a.owners, target)
	}
	return .None
}

// release_target drops a single target no matter who owns it. It returns
// Not_Found when the target was not claimed.
release_target :: proc(a: ^Arbiter, target: Target) -> Error {
	if _, ok := a.owners[target]; !ok {
		return .Not_Found
	}
	delete_key(&a.owners, target)
	return .None
}

// owner_of returns the agent that currently owns target, if any.
owner_of :: proc(a: ^Arbiter, target: Target) -> (Agent, bool) {
	owner, ok := a.owners[target]
	return owner, ok
}

// owned reports whether agent already owns target.
owned :: proc(a: ^Arbiter, agent: Agent, target: Target) -> bool {
	owner, ok := a.owners[target]
	return ok && owner == agent
}

// count returns how many targets are currently claimed.
count :: proc(a: ^Arbiter) -> int {
	return len(a.owners)
}
