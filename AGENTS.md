# AGENTS.md

This file is for AI agents working in this repository. Read it before doing
anything. It explains the project, how to use the GitHub project board as the
long-term plan, and the exact build/test/commit workflow.

## What this project is

`wcu` is a Windows computer use system for AI agents, written in Odin. Agents
see the screen as a text accessibility tree (UI Automation) and act through
non-intrusive input channels (UIA patterns, CDP for Chromium apps, posted
messages). SendInput is only a serialized fallback. It ships as a CLI and an
MCP server over stdio.

The full product and architecture is in `ARCHITECTURE.md`. Read it before
touching anything larger than a typo. It is the canonical design reference:
it contains the system diagram, the perception/action/concurrency/isolation
designs, the reliability rules, the roadmap (P0-P7), and the known
limitations. Whenever you implement an issue in a subsystem (perception,
actions, concurrency, cdp, mcp, isolation, safety), read the matching
`ARCHITECTURE.md` section first and follow it.

## The GitHub project board is the plan

All planned and in-flight work lives on the GitHub Project:
`https://github.com/users/aquaticcalf/projects/9` (owner `aquaticcalf`,
project number `9`, linked to this repo).

**Rules for long-term work:**

1. At the start of every session, read the board. Do not guess what to do.
2. Continue any issue in `In Progress` first.
3. Otherwise pick the next sensible issue from `Todo` (respect the roadmap in
   `ARCHITECTURE.md`: perception before actions, actions before MCP, etc.).
4. Never invent work that is not an issue. If you find real missing work, file
   an issue on the board first, then work it.
5. Keep the board truthful: move the issue you are working on to
   `In Progress`, and to `Done` only when its acceptance criteria pass.
6. Prefer small commits, one issue per commit, each referencing the issue.

### Reading the board

```powershell
# all board items with status
gh project item-list 9 --owner aquaticcalf

# just issues, by area
gh issue list --repo aquaticcalf/windows-computer-use --label "area:perception"
gh issue list --repo aquaticcalf/windows-computer-use --state open --limit 50

# read one issue (its acceptance criteria are in the body)
gh issue view 7 --repo aquaticcalf/windows-computer-use
```

### Updating the board

```powershell
# find the item id for an issue (last column is its status)
gh project item-list 9 --owner aquaticcalf

# move an item between columns (Status field options: Todo / In Progress / Done)
gh project item-edit --project-id PVT_kwHOB4hAIs4Bfwud --id <item-id> `
  --field-id PVTSSF_lAHOB4hAIs4BfwudzhaBUAI `
  --single-select-option-id <option-id>
```

Status option ids: `Todo` = `f75ad846`, `In Progress` = `47fc9ee4`,
`Done` = `98236657`. The `Area` field is already populated from each issue
label (Foundation, Perception, Actions, Concurrency, CDP, MCP, Isolation,
Safety, Reliability, Docs). Set `Area` on new items to match their label.

### Closing issues

Reference the issue in the commit body to auto-close it:

```
git commit -m "Implement xyz

Closes #N"
```

Then move the board item to `Done`.

## Build, check, test

```powershell
odin check cmd/wcu          # type check (there is no `odin vet` in this Odin version)
odin build cmd/wcu -out:bin\wcu.exe
odin test internal/version  # package tests
.\build.ps1 build           # wrapper: build | run | test | vet(check) | clean
.\build.ps1 test
```

Run `.\bin\wcu.exe -h` after building to confirm the CLI still works.

## Code structure

```
cmd/wcu/main.odin          CLI entrypoint, subcommand dispatch, help text
internal/version           version constant + test
internal/...               future: windows bindings, perception, input, arbiter, mcp
.github/workflows/ci.yml   manual-only CI (workflow_dispatch)
ARCHITECTURE.md            system spec and roadmap
```

Planned subsystems (in `ARCHITECTURE.md`) map to areas: windows/win32,
perception (UIA tree), actions (input), concurrency (input stack + arbiter),
cdp, mcp, isolation (desktops + glow), safety, reliability.

## Conventions

- Odin, nightly dev build, Windows only.
- `name: Type` declarations; do not use `var name: Type`.
- No trailing commas in multi-line procedure calls.
- Import `core:` packages and `internal/` only.
- Text uses hyphens, never em dashes.
- Keep it clean: fix warnings, keep the CLI help in sync with new commands.

## Security (mandatory)

- Never hardcode credentials, tokens, API keys, or personal emails anywhere,
  including code, docs, config files, or commit messages.
- Secrets come only from environment variables or local gitignored config.
- Treat `run` (shell) and destructive actions as approval-gated; document
  that gate when you implement it.
- Never log typed text or window contents that may contain secrets.
- Keep the repo public-safe: anything pushed must be safe to publish.
