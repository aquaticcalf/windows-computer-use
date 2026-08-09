package arbiter

import "core:strings"
import "core:testing"

// The multi-agent integration test drives three agents ("Slack", "Brave",
// "Notepad") through the full arbiter + router stack in one scenario and
// asserts the P3 promise: concurrent agents on different targets with zero
// cross-talk. Agents interleave on the host scheduler thread the way the MCP
// server event loop will dispatch them; the SendInput lane is the only path
// that needs real thread serialization (covered by sendinput_test).

// Sim_Worlds groups the fake per-app trees, one per simulated target.
Sim_Worlds :: struct {
	slack:   Fake_World,
	brave:   Fake_World,
	notepad: Fake_World,
}

// sim_world_for returns the simulated app an agent drives.
sim_world_for :: proc(worlds: ^Sim_Worlds, agent: Agent) -> ^Fake_World {
	switch agent {
	case "slack":
		return &worlds.slack
	case "brave":
		return &worlds.brave
	case "notepad":
		return &worlds.notepad
	case:
		return nil
	}
}

// sim_executor drives whichever simulated app a frame belongs to, so the
// whole arbiter + router stack can be exercised end to end.
sim_executor :: proc(e: Executor, agent: Agent, frame: Frame) -> Error {
	worlds := (^Sim_Worlds)(e.data)
	w := sim_world_for(worlds, agent)
	assert(w != nil)
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

// Target_Cap ties one target to the lanes it exposes.
Target_Cap :: struct {
	target: Target,
	caps:   Capabilities,
}

// caps_table is a fake Capability_Probe over a fixed table of per-target
// caps. The table lives behind data as a [3]Target_Cap, so the probe makes
// no allocations.
caps_table :: proc(data: rawptr, target: Target) -> Capabilities {
	table := (^[3]Target_Cap)(data)
	for &entry in table {
		if entry.target == target {
			return entry.caps
		}
	}
	return {}
}

// check_log asserts every frame a world logged belongs to its agent and its
// window, which is the zero-cross-talk invariant.
check_log :: proc(log: ^[dynamic]Logged_Frame, agent: Agent, target: Target, t: ^testing.T) {
	for entry in log {
		testing.expect(t, entry.agent == agent)
		testing.expect(t, entry.frame.target == target)
	}
}

@(test)
test_three_agents_drive_targets_without_cross_talk :: proc(t: ^testing.T) {
	worlds := Sim_Worlds{}
	defer world_destroy(&worlds.slack)
	defer world_destroy(&worlds.brave)
	defer world_destroy(&worlds.notepad)

	slack_hwnd := fake_target(0x5000)
	brave_hwnd := fake_target(0x6000)
	notes_hwnd := fake_target(0x7000)

	// Slack and Notepad are a11y apps; Brave is Chromium with CDP attached.
	caps := [3]Target_Cap {
		{target = slack_hwnd, caps = Capabilities{uia = true}},
		{target = brave_hwnd, caps = Capabilities{cdp = true}},
		{target = notes_hwnd, caps = Capabilities{uia = true, send_input = true}},
	}

	r := Router {
		probe = Capability_Probe{data = &caps, probe = caps_table},
	}
	base := Executor {
		data = &worlds,
		run  = sim_executor,
	}
	set_lane(&r, .Uia, base)
	set_lane(&r, .Cdp, base)
	set_lane(&r, .Post, base)
	set_lane(&r, .SendInput, base)
	// set_lane wrapped the SendInput executor in the global lock; free the
	// wrapper it allocated.
	defer free((^SendInput_Wrapper)(r.lanes[.SendInput].data))
	exec := executor(&r)

	a: Arbiter
	defer destroy(&a)
	slack := Agent("slack")
	brave := Agent("brave")
	notepad := Agent("notepad")

	// Slack: type, self-verify, then a keypress.
	slack_batch := [2]Frame {
		{lane = .Auto, target = slack_hwnd, op = .Type, text = "hello"},
		{lane = .Auto, target = slack_hwnd, op = .Wait_Until, text = "hello"},
	}
	testing.expect(t, push_batch(&a, slack, slack_batch[:]) == .None)
	testing.expect(
		t,
		push(
			&a,
			slack,
			Frame{lane = .Auto, target = slack_hwnd, op = .Key, text = "ctrl+enter"},
		) ==
		.None,
	)

	// Brave: a batch whose condition never materializes.
	brave_batch := [3]Frame {
		{lane = .Auto, target = brave_hwnd, op = .Click},
		{lane = .Auto, target = brave_hwnd, op = .Wait_Until, text = "menu"},
		{lane = .Auto, target = brave_hwnd, op = .Click, text = "bookmarks"},
	}
	testing.expect(t, push_batch(&a, brave, brave_batch[:]) == .None)

	// Notepad: a plain action plus one forced onto the serialized SendInput lane.
	testing.expect(
		t,
		push(&a, notepad, Frame{lane = .Auto, target = notes_hwnd, op = .Type, text = "notes"}) ==
		.None,
	)
	testing.expect(
		t,
		push(
			&a,
			notepad,
			Frame{lane = .SendInput, target = notes_hwnd, op = .Key, text = "ctrl+s"},
		) ==
		.None,
	)

	// A fourth party trying to grab Slack's window is rejected up front.
	testing.expect(
		t,
		push(&a, Agent("intruder"), Frame{lane = .Auto, target = slack_hwnd, op = .Click}) ==
		.Target_Owned,
	)

	// The host scheduler interleaves the three agents.
	testing.expect(t, execute(&a, exec, slack) == .None)
	testing.expect(t, execute(&a, exec, notepad) == .None)
	testing.expect(t, execute(&a, exec, brave) == .None)
	testing.expect(t, execute(&a, exec, slack) == .None)
	testing.expect(t, execute(&a, exec, notepad) == .None)
	testing.expect(t, execute(&a, exec, brave) == .Not_Met)
	testing.expect(t, execute(&a, exec, slack) == .None)
	testing.expect(t, execute(&a, exec, slack) == .Empty)
	testing.expect(t, execute(&a, exec, notepad) == .Empty)
	// Brave's batch aborted: the "bookmarks" frame was dropped.
	testing.expect(t, execute(&a, exec, brave) == .Empty)

	// Zero cross-talk: every logged frame belongs to the agent that owns its
	// window, and each agent's frames ran in push order.
	check_log(&worlds.slack.log, slack, slack_hwnd, t)
	check_log(&worlds.brave.log, brave, brave_hwnd, t)
	check_log(&worlds.notepad.log, notepad, notes_hwnd, t)
	testing.expect(t, len(worlds.slack.log) == 3)
	// Brave's batch aborted: the click and the failed waitUntil ran, but the
	// "bookmarks" frame was dropped and never executed.
	testing.expect(t, len(worlds.brave.log) == 2)
	testing.expect(t, len(worlds.notepad.log) == 2)
	for entry in worlds.brave.log {
		testing.expect(t, entry.frame.text != "bookmarks")
	}

	// Ordering: Slack ran type, then waitUntil, then the keypress.
	testing.expect(t, worlds.slack.log[0].frame.op == .Type)
	testing.expect(t, worlds.slack.log[1].frame.op == .Wait_Until)
	testing.expect(t, worlds.slack.log[2].frame.op == .Key)
	// The Notepad keypress went through the serialized lane.
	testing.expect(t, worlds.notepad.log[1].frame.lane == .SendInput)
}
