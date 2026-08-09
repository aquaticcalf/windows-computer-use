package arbiter

import "core:testing"

// caps_source is a fake Capability_Probe that returns the Capabilities held
// behind data for every target.
caps_source :: proc(data: rawptr, target: Target) -> Capabilities {
	return (^Capabilities)(data)^
}

@(test)
test_select_defaults_to_uia_for_regular_apps :: proc(t: ^testing.T) {
	caps := Capabilities {
		uia = true,
	}
	r := Router {
		probe = Capability_Probe{data = &caps, probe = caps_source},
	}

	lane, err := select(&r, Frame{lane = .Auto, target = fake_target(0x100), op = .Click})
	testing.expect(t, err == .None)
	testing.expect(t, lane == .Uia)
}

@(test)
test_select_routes_browsers_to_cdp_when_enabled :: proc(t: ^testing.T) {
	// A browser with an attached CDP session: UIA is not the preferred lane,
	// so the priority falls through to CDP.
	caps := Capabilities {
		cdp = true,
	}
	r := Router {
		probe = Capability_Probe{data = &caps, probe = caps_source},
	}

	lane, err := select(&r, Frame{lane = .Auto, target = fake_target(0x200), op = .Click})
	testing.expect(t, err == .None)
	testing.expect(t, lane == .Cdp)
}

@(test)
test_select_prefers_uia_over_cdp :: proc(t: ^testing.T) {
	caps := Capabilities {
		uia = true,
		cdp = true,
	}
	r := Router {
		probe = Capability_Probe{data = &caps, probe = caps_source},
	}

	lane, err := select(&r, Frame{lane = .Auto, target = fake_target(0x300), op = .Click})
	testing.expect(t, err == .None)
	testing.expect(t, lane == .Uia)
}

@(test)
test_select_falls_through_the_priority_chain :: proc(t: ^testing.T) {
	// Only SendInput is available, so Auto must land there.
	caps := Capabilities {
		send_input = true,
	}
	r := Router {
		probe = Capability_Probe{data = &caps, probe = caps_source},
	}
	lane, err := select(&r, Frame{lane = .Auto, target = fake_target(0x400), op = .Click})
	testing.expect(t, err == .None)
	testing.expect(t, lane == .SendInput)
}

@(test)
test_select_honors_a_forced_lane :: proc(t: ^testing.T) {
	caps := Capabilities {
		uia        = true,
		send_input = true,
	}
	r := Router {
		probe = Capability_Probe{data = &caps, probe = caps_source},
	}

	lane, err := select(&r, Frame{lane = .SendInput, target = fake_target(0x500), op = .Click})
	testing.expect(t, err == .None)
	testing.expect(t, lane == .SendInput)
}

@(test)
test_select_fails_when_forced_lane_is_unavailable :: proc(t: ^testing.T) {
	caps := Capabilities {
		uia = true,
	}
	r := Router {
		probe = Capability_Probe{data = &caps, probe = caps_source},
	}

	_, err := select(&r, Frame{lane = .SendInput, target = fake_target(0x600), op = .Click})
	testing.expect(t, err == .Lane_Unavailable)
}

@(test)
test_select_fails_when_no_lane_is_available :: proc(t: ^testing.T) {
	caps := Capabilities{}
	r := Router {
		probe = Capability_Probe{data = &caps, probe = caps_source},
	}

	_, err := select(&r, Frame{lane = .Auto, target = fake_target(0x700), op = .Click})
	testing.expect(t, err == .No_Lane)
}

// lane_log_executor records the frames a specific lane runs into the log
// behind e.data, marking which lane received them.
lane_log_executor :: proc(e: Executor, agent: Agent, frame: Frame) -> Error {
	log := (^[dynamic]Logged_Frame)(e.data)
	append(log, Logged_Frame{agent = agent, frame = frame})
	return .None
}

@(test)
test_router_dispatches_to_the_selected_lane :: proc(t: ^testing.T) {
	caps := Capabilities {
		uia = true,
		cdp = true,
	}
	r := Router {
		probe = Capability_Probe{data = &caps, probe = caps_source},
	}
	log: [dynamic]Logged_Frame
	defer delete(log)
	r.lanes[.Uia] = Executor {
		data = &log,
		run  = lane_log_executor,
	}
	r.lanes[.Cdp] = Executor {
		data = &log,
		run  = lane_log_executor,
	}

	a: Arbiter
	defer destroy(&a)
	agent := Agent("agent")
	target := fake_target(0x800)

	testing.expect(t, push(&a, agent, Frame{lane = .Auto, target = target, op = .Click}) == .None)
	exec := executor(&r)
	testing.expect(t, execute(&a, exec, agent) == .None)

	testing.expect(t, len(log) == 1)
	// The frame was routed to UIA and stamped with the resolved lane.
	testing.expect(t, log[0].agent == agent)
	testing.expect(t, log[0].frame.target == target)
	testing.expect(t, log[0].frame.lane == .Uia)
}

@(test)
test_router_rejects_when_selected_lane_has_no_executor :: proc(t: ^testing.T) {
	caps := Capabilities {
		uia = true,
	}
	r := Router {
		probe = Capability_Probe{data = &caps, probe = caps_source},
	}

	a: Arbiter
	defer destroy(&a)
	agent := Agent("agent")
	target := fake_target(0x900)

	testing.expect(t, push(&a, agent, Frame{lane = .Auto, target = target, op = .Click}) == .None)
	exec := executor(&r)
	testing.expect(t, execute(&a, exec, agent) == .Lane_Unavailable)
}
