package arbiter

// The arbiter owns the target ownership map and the per-agent action stacks:
// at most one agent may claim a target at a time, and each agent's queued
// actions run in order, isolated from every other agent. It is the single
// owner of concurrency decisions in wcu; the lane router and the SendInput
// lock build on top of it. See ARCHITECTURE.md (Input Stack System) and
// DESIGN.md.

import "core:strings"
import "core:sys/windows"

// Agent identifies a client that drives targets: an MCP session id, a CLI
// invocation, or a worker process.
Agent :: distinct string

// Target is an opaque window identity that an agent claims exclusively. The
// arbiter never dereferences handles, so it stays testable with fake ids.
Target :: windows.HWND

// Lane names an input channel that executes frames.
Lane :: enum {
	Uia,
	Cdp,
	Post,
	SendInput,
}

// Op names a user-level action that a lane executor interprets.
Op :: enum {
	Click,
	Type,
	Key,
	Scroll,
	Set_Value,
	Focus,
	Wake,
	Wait_Until,
}

// Frame is one queued action for an agent. The arbiter owns frame.text: push
// makes a private copy and execute frees it after the frame runs, so callers
// may pass literals or borrowed strings and the lane executor must treat text
// as borrowed during run.
Frame :: struct {
	lane:   Lane,
	target: Target,
	op:     Op,
	// text carries the string argument: typed text, a key spec, a value, or
	// a match string for Wait_Until.
	text:   string,
}

// Executor runs a frame on a lane. It is the seam behind which the real lane
// adapters (UIA, CDP, posted messages, SendInput) plug in; tests drive the
// arbiter with a fake that records frames. See DESIGN.md.
Executor :: struct {
	// data is opaque context for run, set by the producer of the executor.
	data: rawptr,
	// run executes frame for agent on the executor's lane.
	run:  proc(e: Executor, agent: Agent, frame: Frame) -> Error,
}

// Stack is one agent's ordered queue of pending frames.
Stack :: struct {
	frames: [dynamic]Frame,
}

// Arbiter tracks target ownership and per-agent stacks. The zero value is an
// empty, usable arbiter; destroy releases its maps and queued frames.
Arbiter :: struct {
	// owners maps each claimed target to its exclusive agent.
	owners: map[Target]Agent,
	// stacks maps each agent to its pending frame queue.
	stacks: map[Agent]^Stack,
	// paused marks agents whose execute calls do nothing.
	paused: map[Agent]bool,
}

// Error is this package's error type.
Error :: enum {
	// None reports a successful operation.
	None,
	// Target_Owned reports that a different agent already owns the target.
	Target_Owned,
	// Not_Owner reports that a queued frame targets a window the agent no
	// longer owns.
	Not_Owner,
	// Not_Found reports that a pause or resume named an unknown agent.
	Not_Found,
	// Paused reports that the agent is paused, so execute did nothing.
	Paused,
	// Empty reports that the agent has no pending frames.
	Empty,
}

// destroy releases the arbiter's maps, queued frames, and stacks.
destroy :: proc(a: ^Arbiter) {
	for _, s in a.stacks {
		for frame in s.frames {
			delete(frame.text)
		}
		delete(s.frames)
		free(s)
	}
	if a.owners != nil {
		delete(a.owners)
	}
	if a.stacks != nil {
		delete(a.stacks)
	}
	if a.paused != nil {
		delete(a.paused)
	}
	a.owners = nil
	a.stacks = nil
	a.paused = nil
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
// agent owned no targets. Queued frames are left in place; execute reports
// Not_Owner for a frame whose target was released.
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

// push queues a frame for agent. It claims frame.target for agent when the
// target is free and rejects the push with Target_Owned when a different
// agent already owns it, which is what keeps agents from acting on each
// other's windows. The arbiter copies frame.text and owns that copy.
push :: proc(a: ^Arbiter, agent: Agent, frame: Frame) -> Error {
	if frame.target != nil {
		if err := claim(a, agent, frame.target); err != .None {
			return err
		}
	}
	queued := frame
	queued.text = strings.clone(frame.text)
	s := a.stacks[agent]
	if s == nil {
		s = new(Stack)
		a.stacks[agent] = s
	}
	append(&s.frames, queued)
	return .None
}

// execute runs the agent's next queued frame on the given executor. The
// frame is popped whether it succeeds or fails, so the queue can never stall
// on a repeated failure. A paused agent keeps its queue and returns Paused.
execute :: proc(a: ^Arbiter, exec: Executor, agent: Agent) -> Error {
	assert(exec.run != nil)
	if is_paused(a, agent) {
		return .Paused
	}
	s := a.stacks[agent]
	if s == nil || len(s.frames) == 0 {
		return .Empty
	}
	frame := pop_front(&s.frames)
	defer delete(frame.text)
	if frame.target != nil {
		if owner, ok := a.owners[frame.target]; !ok || owner != agent {
			return .Not_Owner
		}
	}
	return exec.run(exec, agent, frame)
}

// pause stops agent's queue from executing. Paused agents keep their pending
// frames and report .Paused from execute until resumed. It returns
// Not_Found for an unknown agent.
pause :: proc(a: ^Arbiter, agent: Agent) -> Error {
	if _, ok := a.stacks[agent]; !ok {
		return .Not_Found
	}
	if a.paused == nil {
		a.paused = make(map[Agent]bool)
	}
	a.paused[agent] = true
	return .None
}

// resume clears agent's paused flag so execute runs again. It returns
// Not_Found for an unknown agent and is a no-op when the agent is not paused.
resume :: proc(a: ^Arbiter, agent: Agent) -> Error {
	if _, ok := a.stacks[agent]; !ok {
		return .Not_Found
	}
	if a.paused != nil {
		delete_key(&a.paused, agent)
	}
	return .None
}

// pending returns how many frames are queued for agent (zero for unknown
// agents).
pending :: proc(a: ^Arbiter, agent: Agent) -> int {
	s := a.stacks[agent]
	if s == nil {
		return 0
	}
	return len(s.frames)
}

// is_paused reports whether agent is paused (false for unknown agents).
is_paused :: proc(a: ^Arbiter, agent: Agent) -> bool {
	return a.paused[agent]
}

// pop_front removes and returns the first frame of the queue, shifting the
// rest down so the queue stays ordered.
pop_front :: proc(frames: ^[dynamic]Frame) -> Frame {
	front := frames[0]
	for i in 0 ..< len(frames) - 1 {
		frames[i] = frames[i + 1]
	}
	pop(frames)
	return front
}
