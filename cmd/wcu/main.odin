package main

import actions "../../internal/actions"
import capture "../../internal/capture"
import perception "../../internal/perception"
import window "../../internal/window"
import "core:fmt"
import "core:os"
import "core:strconv"
import "core:strings"
import "core:sys/windows"

// VERSION is the semantic version of the CLI.
VERSION :: "0.0.1"

// main dispatches on the first argument and runs the matching command.
main :: proc() {
	args := os.args[1:]

	if len(args) == 0 {
		print_help()
		os.exit(0)
	}

	switch args[0] {
	case "-h", "--help", "help":
		print_help()
	case "version", "--version", "-v":
		fmt.printf("wcu %s\n", VERSION)
	case "list_apps":
		run_list_apps()
	case "state":
		run_state(args[1:])
	case "screenshot":
		run_screenshot(args[1:])
	case "click":
		run_click(args[1:])
	case "type":
		run_type(args[1:])
	case "key":
		run_key(args[1:])
	case "scroll":
		run_scroll(args[1:])
	case "set_value":
		run_set_value(args[1:])
	case "focus":
		run_focus(args[1:])
	case "wake":
		run_wake(args[1:])
	case "run":
		stub("run")
	case "new-desktop":
		stub("new-desktop")
	case "move-app":
		stub("move-app")
	case "doctor":
		stub("doctor")
	case "mcp":
		stub("mcp")
	case:
		fmt.eprintf("wcu: unknown command '%s'\n", args[0])
		fmt.eprintln()
		print_help()
		os.exit(1)
	}
}

// stub reports that a command is not implemented yet.
stub :: proc(command: string) {
	fmt.eprintf("wcu: '%s' is not implemented yet (tracked on the project board).\n", command)
}

// run_list_apps prints every top-level window as a table.
run_list_apps :: proc() {
	rows, ok := window.list()
	if !ok {
		fmt.eprintln("wcu: failed to enumerate windows")
		os.exit(1)
	}
	defer window.destroy(rows)

	fmt.println("HANDLE     PID   VIS  TITLE")
	for w in rows {
		fmt.printf("%08x  %5d  %v  %s\n", uintptr(w.handle), w.pid, w.visible, w.title)
	}
}

// run_state renders an app's accessibility tree as text.
run_state :: proc(args: []string) {
	if len(args) < 1 {
		fmt.eprintln("wcu: state requires an app (name, pid, or title)")
		os.exit(2)
	}

	app_query := args[0]
	limits := perception.default_limits()
	for i := 1; i < len(args); i += 1 {
		switch args[i] {
		case "--max-nodes":
			if i + 1 < len(args) {
				limits.max_nodes = parse_int(args[i + 1], limits.max_nodes)
				i += 1
			}
		case "--max-depth":
			if i + 1 < len(args) {
				limits.max_depth = parse_int(args[i + 1], limits.max_depth)
				i += 1
			}
		case "--text-limit":
			if i + 1 < len(args) {
				limits.text_limit = parse_int(args[i + 1], limits.text_limit)
				i += 1
			}
		}
	}

	hwnd, ok := window.resolve(app_query)
	if !ok {
		fmt.eprintf("wcu: no window matched '%s'\n", app_query)
		os.exit(1)
	}

	session, serr := perception.open()
	if serr != .None {
		fmt.eprintln("wcu: failed to open perception session")
		os.exit(1)
	}
	defer perception.close(&session)

	text, terr := perception.state(&session, hwnd, limits)
	if terr != .None {
		fmt.eprintln("wcu: failed to read app state")
		os.exit(1)
	}
	defer delete(text)

	fmt.print(text)
}

// run_screenshot captures an app's window to a PNG or JPEG file. The format
// is chosen by the output extension; --quality applies to JPEG only.
run_screenshot :: proc(args: []string) {
	if len(args) < 1 {
		fmt.eprintln("wcu: screenshot requires an app (name, pid, or title)")
		os.exit(2)
	}

	app_query := args[0]
	out_path := "wcu.png"
	quality := 85
	for i := 1; i < len(args); i += 1 {
		switch args[i] {
		case "--out":
			if i + 1 < len(args) {
				out_path = args[i + 1]
				i += 1
			}
		case "--quality":
			if i + 1 < len(args) {
				quality = parse_int(args[i + 1], quality)
				i += 1
			}
		}
	}

	hwnd, ok := window.resolve(app_query)
	if !ok {
		fmt.eprintf("wcu: no window matched '%s'\n", app_query)
		os.exit(1)
	}

	lower := strings.to_lower(out_path)
	is_jpeg := strings.has_suffix(lower, ".jpg") || strings.has_suffix(lower, ".jpeg")

	data: []byte
	if is_jpeg {
		data, ok = capture.capture_window_jpeg(hwnd, quality)
	} else {
		data, ok = capture.capture_window(hwnd)
	}
	if !ok {
		fmt.eprintln("wcu: failed to capture window")
		os.exit(1)
	}
	defer delete(data)

	if werr := os.write_entire_file(out_path, data); werr == nil {
		fmt.printf("wrote %s (%d bytes)\n", out_path, len(data))
	} else {
		fmt.eprintf("wcu: failed to write file (%v)\n", werr)
		os.exit(1)
	}
}

// parse_int parses a decimal int, falling back to a default.
parse_int :: proc(s: string, fallback: int) -> int {
	if value, ok := strconv.parse_int(s, 10); ok {
		return value
	}
	return fallback
}

// resolve_app resolves an app query (name, pid, or title) to a window handle,
// exiting with an error when nothing matches.
resolve_app :: proc(query: string) -> windows.HWND {
	hwnd, ok := window.resolve(query)
	if !ok {
		fmt.eprintf("wcu: no window matched '%s'\n", query)
		os.exit(1)
	}
	return hwnd
}

// action_fail prints an action error and exits.
action_fail :: proc(what: string, err: actions.Error) {
	fmt.eprintf("wcu: %s: %v\n", what, err)
	os.exit(1)
}

// run_click clicks an element by index or at coordinates.
run_click :: proc(args: []string) {
	if len(args) < 1 {
		fmt.eprintln("wcu: click requires an app (name, pid, or title)")
		os.exit(2)
	}

	app_query := args[0]
	index := -1
	x, y: i32 = -1, -1
	has_xy := false
	method := actions.Method.Auto
	for i := 1; i < len(args); i += 1 {
		switch args[i] {
		case "--index":
			if i + 1 < len(args) {
				index = parse_int(args[i + 1], -1)
				i += 1
			}
		case "--x":
			if i + 1 < len(args) {
				x = i32(parse_int(args[i + 1], 0))
				has_xy = true
				i += 1
			}
		case "--y":
			if i + 1 < len(args) {
				y = i32(parse_int(args[i + 1], 0))
				has_xy = true
				i += 1
			}
		case "--method":
			if i + 1 < len(args) {
				method = parse_method(args[i + 1])
				i += 1
			}
		}
	}

	hwnd := resolve_app(app_query)
	session, serr := actions.open()
	if serr != .None {
		action_fail("failed to open action session", serr)
	}
	defer actions.close(&session)

	err: actions.Error
	if has_xy {
		err = actions.click_xy(hwnd, x, y)
	} else if index >= 0 {
		err = actions.click_index(&session, hwnd, index, method, perception.default_limits())
	} else {
		fmt.eprintln("wcu: click requires --index I or --x X --y Y")
		os.exit(2)
	}
	if err != .None {
		action_fail("click failed", err)
	}
	fmt.println("ok")
}

// parse_method maps a --method value to a click method.
parse_method :: proc(s: string) -> actions.Method {
	switch strings.to_lower(s) {
	case "uia":
		return .Uia
	case "sendinput":
		return .SendInput
	case "auto":
		return .Auto
	case:
		fmt.eprintf("wcu: unknown method '%s' (auto|uia|sendinput)\n", s)
		os.exit(2)
	}
	return .Auto
}

// run_type types text into the target window.
run_type :: proc(args: []string) {
	if len(args) < 2 {
		fmt.eprintln("wcu: type requires an app (name, pid, or title) and text")
		os.exit(2)
	}
	hwnd := resolve_app(args[0])
	text := strings.join(args[1:], " ")
	defer delete(text)

	err := actions.type_text(hwnd, text)
	if err != .None {
		action_fail("type failed", err)
	}
	fmt.println("ok")
}

// run_key presses an xdotool-style key spec into the target window.
run_key :: proc(args: []string) {
	if len(args) < 2 {
		fmt.eprintln("wcu: key requires an app (name, pid, or title) and keys (e.g. ctrl+s)")
		os.exit(2)
	}
	hwnd := resolve_app(args[0])
	spec := strings.join(args[1:], " ")
	defer delete(spec)

	err := actions.press_key(hwnd, spec)
	if err != .None {
		action_fail("key failed", err)
	}
	fmt.println("ok")
}

// run_scroll scrolls an element in a direction.
run_scroll :: proc(args: []string) {
	if len(args) < 1 {
		fmt.eprintln("wcu: scroll requires an app (name, pid, or title)")
		os.exit(2)
	}

	app_query := args[0]
	index := -1
	dir := actions.Direction.Down
	pages := 1
	for i := 1; i < len(args); i += 1 {
		switch args[i] {
		case "--index":
			if i + 1 < len(args) {
				index = parse_int(args[i + 1], -1)
				i += 1
			}
		case "--dir":
			if i + 1 < len(args) {
				dir = parse_direction(args[i + 1])
				i += 1
			}
		case "--pages":
			if i + 1 < len(args) {
				pages = max(parse_int(args[i + 1], 1), 1)
				i += 1
			}
		}
	}
	if index < 0 {
		fmt.eprintln("wcu: scroll requires --index I")
		os.exit(2)
	}

	hwnd := resolve_app(app_query)
	session, serr := actions.open()
	if serr != .None {
		action_fail("failed to open action session", serr)
	}
	defer actions.close(&session)

	err := actions.scroll_index(&session, hwnd, index, dir, pages, perception.default_limits())
	if err != .None {
		action_fail("scroll failed", err)
	}
	fmt.println("ok")
}

// parse_direction maps a --dir value to a scroll direction.
parse_direction :: proc(s: string) -> actions.Direction {
	switch strings.to_lower(s) {
	case "up":
		return .Up
	case "down":
		return .Down
	case "left":
		return .Left
	case "right":
		return .Right
	case:
		fmt.eprintf("wcu: unknown direction '%s' (up|down|left|right)\n", s)
		os.exit(2)
	}
	return .Down
}

// run_set_value writes a value into an element.
run_set_value :: proc(args: []string) {
	if len(args) < 1 {
		fmt.eprintln("wcu: set_value requires an app (name, pid, or title)")
		os.exit(2)
	}

	app_query := args[0]
	index := -1
	value := ""
	for i := 1; i < len(args); i += 1 {
		switch args[i] {
		case "--index":
			if i + 1 < len(args) {
				index = parse_int(args[i + 1], -1)
				i += 1
			}
		case "--value":
			if i + 1 < len(args) {
				value = args[i + 1]
				i += 1
			}
		}
	}
	if index < 0 {
		fmt.eprintln("wcu: set_value requires --index I")
		os.exit(2)
	}
	if value == "" {
		fmt.eprintln("wcu: set_value requires --value V")
		os.exit(2)
	}

	hwnd := resolve_app(app_query)
	session, serr := actions.open()
	if serr != .None {
		action_fail("failed to open action session", serr)
	}
	defer actions.close(&session)

	err := actions.set_value_index(&session, hwnd, index, value, perception.default_limits())
	if err != .None {
		action_fail("set_value failed", err)
	}
	fmt.println("ok")
}

// run_focus brings a window to the foreground.
run_focus :: proc(args: []string) {
	if len(args) < 1 {
		fmt.eprintln("wcu: focus requires an app (name, pid, or title)")
		os.exit(2)
	}
	hwnd := resolve_app(args[0])

	err := actions.focus(hwnd)
	if err != .None {
		action_fail("focus failed", err)
	}
	fmt.println("ok")
}

// run_wake sends WM_GETOBJECT to a window and its children.
run_wake :: proc(args: []string) {
	if len(args) < 1 {
		fmt.eprintln("wcu: wake requires an app (name, pid, or title)")
		os.exit(2)
	}
	hwnd := resolve_app(args[0])

	err := actions.wake(hwnd)
	if err != .None {
		action_fail("wake failed", err)
	}
	fmt.println("ok")
}

// print_help writes usage text for every command to stdout.
print_help :: proc() {
	fmt.println("wcu - Windows Computer Use (CLI + MCP server)")
	fmt.println()
	fmt.println("USAGE")
	fmt.println("  wcu <command> [flags]")
	fmt.println()
	fmt.println("COMMANDS")
	fmt.println("  list_apps                  List running apps and windows")
	fmt.println("  state <app>                Render an app UI tree as text")
	fmt.println("  click <app> [--index I | --x X --y Y] [--method auto|uia|sendinput]")
	fmt.println("  type <app> <text>          Type text into the target")
	fmt.println("  key <app> <keys>           Press keys (e.g. ctrl+s)")
	fmt.println("  scroll <app> --index I --dir up|down|left|right [--pages N]")
	fmt.println("  set_value <app> --index I --value <v>")
	fmt.println("  focus <app>                Bring a window to the foreground")
	fmt.println("  wake <app>                 Wake Chromium accessibility")
	fmt.println("  run <command>              Run a shell command (gated)")
	fmt.println("  screenshot <app>           Capture a window to PNG")
	fmt.println("  new-desktop <name>         Create a workspace for an agent")
	fmt.println("  move-app <app> <desktop>   Move an app to a desktop")
	fmt.println("  doctor                     Health checks")
	fmt.println("  mcp                        Run the MCP server (stdio)")
	fmt.println("  version                    Show the version")
	fmt.println()
	fmt.println("FLAGS")
	fmt.println("  -h, --help   show this help")
}
