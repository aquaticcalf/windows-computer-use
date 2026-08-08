package main

import capture "../../internal/capture"
import perception "../../internal/perception"
import window "../../internal/window"
import "core:fmt"
import "core:os"
import "core:strconv"

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
		stub("click")
	case "type":
		stub("type")
	case "key":
		stub("key")
	case "scroll":
		stub("scroll")
	case "set_value":
		stub("set_value")
	case "focus":
		stub("focus")
	case "wake":
		stub("wake")
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

// run_screenshot captures an app's window to a PNG file.
run_screenshot :: proc(args: []string) {
	if len(args) < 1 {
		fmt.eprintln("wcu: screenshot requires an app (name, pid, or title)")
		os.exit(2)
	}

	app_query := args[0]
	out_path := "wcu.png"
	for i := 1; i < len(args); i += 1 {
		if args[i] == "--out" && i + 1 < len(args) {
			out_path = args[i + 1]
			i += 1
		}
	}

	hwnd, ok := window.resolve(app_query)
	if !ok {
		fmt.eprintf("wcu: no window matched '%s'\n", app_query)
		os.exit(1)
	}

	png, cok := capture.capture_window(hwnd)
	if !cok {
		fmt.eprintln("wcu: failed to capture window")
		os.exit(1)
	}
	defer delete(png)

	if werr := os.write_entire_file(out_path, png); werr == nil {
		fmt.printf("wrote %s (%d bytes)\n", out_path, len(png))
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
	fmt.println("  click <app>                Click an element by index or x/y")
	fmt.println("  type <app> <text>          Type text into the target")
	fmt.println("  key <app> <keys>           Press keys (e.g. ctrl+s)")
	fmt.println("  scroll <app>               Scroll an element")
	fmt.println("  set_value <app>            Set an element value")
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
