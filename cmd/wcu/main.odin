package main

import "core:fmt"
import "core:os"

VERSION :: "0.0.1"

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
		stub("list_apps")
	case "state":
		stub("state")
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
	case "screenshot":
		stub("screenshot")
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

stub :: proc(command: string) {
	fmt.eprintf("wcu: '%s' is not implemented yet (tracked on the project board).\n", command)
}

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
