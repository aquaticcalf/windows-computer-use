# wcu - Windows Computer Use

Local computer use for AI agents on Windows. Agents see the screen as a
text accessibility tree and act through non-intrusive input channels, so many
agents can work at once without stealing your mouse or keyboard.

- Text-native perception: UI Automation tree rendered as compact text (no screenshots required)
- Parallel input: UIA, CDP (Chromium/Electron), posted messages; SendInput only as a serialized fallback
- Isolation: optional private desktops, takeover mode with a glow overlay
- Ships as a CLI and an MCP server (stdio)

## Status

Early development. The full product and architecture are described in
[ARCHITECTURE.md](ARCHITECTURE.md). Work is tracked on the
[project board](https://github.com/users/aquaticcalf/projects/9).

## Requirements

- Windows 10 or 11 (x64)
- [Odin](https://odin-lang.org) (nightly dev build)

## Quickstart

```powershell
# build
odin build cmd/wcu -out:bin\wcu.exe

# or use the wrapper
.\build.ps1 build

# run
.\bin\wcu.exe -h
.\bin\wcu.exe version
```

## Commands

| Command | Description |
|---|---|
| `list_apps` | List running apps and windows |
| `state <app>` | Render an app UI tree as text |
| `click <app>` | Click an element by index or x/y |
| `type <app> <text>` | Type text into the target |
| `key <app> <keys>` | Press keys (e.g. ctrl+s) |
| `scroll <app>` | Scroll an element |
| `set_value <app>` | Set an element value |
| `focus <app>` | Bring a window to the foreground |
| `wake <app>` | Wake Chromium accessibility |
| `run <command>` | Run a shell command (gated) |
| `screenshot <app>` | Capture a window to PNG |
| `new-desktop <name>` | Create a workspace for an agent |
| `move-app <app> <desktop>` | Move an app to a desktop |
| `doctor` | Health checks |
| `mcp` | Run the MCP server (stdio) |
| `version` | Show the version |

## Development

- [CONTRIBUTING.md](CONTRIBUTING.md) for the workflow
- [AGENTS.md](AGENTS.md) for AI agents contributing to this repo
- `make build` / `make test` / `make check` or `.\build.ps1`

## License

[MIT](LICENSE)
