# Windows Computer Use - Product & Architecture Specification

**Status:** Draft v1.0
**Target platform:** Windows 10/11 (x64), Odin language, single static binary
**Codename:** `wcu` (Windows Computer Use)

---

## 1. Vision

**wcu** is a local computer-use system that lets AI agents see and operate any
Windows application - text-only, safely, and concurrently - while the human
keeps full control of their own desktop.

Three pillars define the product:

1. **Text-native perception.** The agent "sees" the screen as a structured,
   token-cheap accessibility tree - not screenshots. This makes it cheap enough
   for text-only models and fast enough for real work.
2. **Non-intrusive, parallel input.** Agents act through per-app virtual input
   channels (UI Automation, CDP for Chromium apps, posted messages) that never
   steal the user's cursor or focus. Many agents can work at once without
   interfering with each other or with the human.
3. **Trust & control by design.** The user is always one hotkey away from
   reclaiming input. A glow overlay communicates exactly when the AI is working
   versus when it has taken control. Destructive actions are gated.

---

## 2. Goals & Non-Goals

### Goals
- Operate any UIA-exposing Windows app and any Chromium/Electron app.
- Text-only operation (no screenshots required); optional screenshots for
  vision models.
- Run many agents concurrently on different apps without interference.
- Never disturb the user's mouse/keyboard except in explicit takeover mode.
- Single `wcu.exe` that works as both a CLI and an MCP server.
- Persist a live UI Automation connection to avoid Chromium's sparse-tree bug.

### Non-Goals (v1)
- Not a VM / cloud service (local machine only).
- No OS-level synthetic input devices (VHF/Interception) in v1.
- No full autonomy guarantees - agents are still bounded by approval policy.
- No mobile/remote (RDP) session orchestration in v1.

---

## 3. Personas

| Persona | Description | Primary need |
|---|---|---|
| **The Developer** (sampreeth) | Builds apps, automates chores | Drive their own machine, review agent work, stay in control |
| **The Agent** (opencode / Claude / Codex-style) | AI assistant connected via MCP | See an app, act on it, verify results, work in parallel with other agents |
| **The Admin** (future, enterprise) | Governs usage | Approval policy, allow/deny lists, audit |

---

## 4. User Stories

### 4.1 Single-agent basics

**US-01 - List running apps**
> As an agent, I want to list running apps and their windows, so I can pick a
> target.

**Acceptance:** `wcu list_apps` returns app name, PID, window title(s), and
visibility, within 1s.

**US-02 - Read an app's state as text**
> As an agent, I want the accessibility tree of a target window rendered as
> compact text, so I can understand the UI without screenshots.

**Acceptance:** `wcu state <app>` prints lines like
`[42] button "Send" rect(120,300,60,28)`. Supports `text_limit`,
`max_nodes`, `max_depth`. Returns within 2s.

**US-03 - Click an element**
> As an agent, I want to click a button by its element index, so I can
> navigate an app.

**Acceptance:** `wcu click <app> --index 42` invokes the element via UIA where
possible, without moving the user's cursor. Falls back to `--x --y`.

**US-04 - Type text**
> As an agent, I want to type text into the focused field, so I can fill
> forms.

**Acceptance:** `wcu type <app> "hello"` inserts text; special chars handled
via Unicode key events.

**US-05 - Press keys / chords**
> As an agent, I want to press keys and combinations, so I can use shortcuts.

**Acceptance:** `wcu key <app> "ctrl+s"`, `"Return"`, `"super+e"` (xdotool
syntax).

**US-06 - Scroll & set values**
> As an agent, I want to scroll an element and set editable values.

**Acceptance:** `wcu scroll <app> --index 12 --dir down --pages 1`;
`wcu set_value <app> --index 7 --value "x"`.

### 4.2 Parallelism & isolation

**US-07 - Many agents, many apps, no interference**
> As a developer, I want three agents to operate Slack, Brave, and Notepad
> simultaneously without errors or focus fights.

**Acceptance:** Each agent owns exactly one target (arbiter enforces it).
Actions on different targets never block each other. SendInput (rare) is the
only globally serialized lane.

**US-08 - Agent works invisibly while I keep my mouse/keyboard**
> As a developer, I want the agent to work on a private desktop I can't see,
> so my cursor and keys are never disturbed.

**Acceptance:** The agent's app lives on a private desktop
(`CreateDesktop` + worker process). My desktop remains the input desktop.
I see only a subtle glow.

**US-09 - Agent takes over input (explicit)**
> As a developer, when an agent needs physical control, I want a clear
> indicator that I don't have my devices, plus a hotkey to reclaim them.

**Acceptance:** On takeover, the system switches input to the agent's desktop
and shows a **strong glow ring** around the screen. Pressing the reclaim
hotkey restores my input instantly.

**US-10 - Glow communicates state**
> As a developer, I want to know at a glance whether the AI is idle, working
> in the background, or in control.

**Acceptance:** Idle = no glow; background work = subtle glow; takeover =
strong glow + "AI in control" HUD label.

**US-11 - Live preview (optional)**
> As a developer, I want a small live thumbnail of the agent's desktop so I
> can peek without switching.

**Acceptance:** `DwmRegisterThumbnail` mini-preview in a corner, toggleable.

### 4.3 Safety & control

**US-12 - Approval-gated shell**
> As a developer, I want `run` (shell commands) to require approval by
> default, so the agent can't silently execute arbitrary commands.

**Acceptance:** `run` is denied unless `--allow-run` / MCP approval policy
permits it.

**US-13 - Destructive actions annotated**
> As an agent orchestrator, I want to know which tools are read-only vs.
> destructive, so I can gate them.

**Acceptance:** MCP tool annotations (`readOnlyHint`, `destructiveHint`)
correct on every tool.

**US-14 - Allow/deny app policy**
> As a developer, I want to restrict which apps agents may touch.

**Acceptance:** Config file lists allowed apps; disallowed targets return an
error.

**US-15 - Emergency stop**
> As a developer, I want to halt all agent activity instantly.

**Acceptance:** Global hotkey cancels in-flight actions, switches back to my
desktop, and clears the glow.

### 4.4 Reliability

**US-16 - Chromium apps never "go dark"**
> As an agent, I want Slack/Brave's accessibility tree to stay readable during
> a session.

**Acceptance:** The persistent process + `WM_GETOBJECT` wake + poll recovers
the tree whenever it lapses (proven against Slack).

**US-17 - Fresh state after every action**
> As an agent, I want the element indices I act on to be valid.

**Acceptance:** Every action returns a refreshed snapshot; indices are
documented as valid only within that snapshot.

**US-18 - Self-healing windows**
> As an agent, when a target window closes or changes, I want a clear error
> and a way to re-target.

**Acceptance:** Stale window handles are detected; `wcu doctor` reports
session health.

---

## 5. Functional Requirements

1. **Perception**
   - Enumerate apps/windows (EnumWindows + process lookup).
   - Build a UIA accessibility tree for a target window.
   - Render tree as compact text with stable per-snapshot indices.
   - Optional screenshot (GDI/DXGI) and optional TextPattern extraction.
2. **Action**
   - Click (by index or coordinates; click_method: auto / uia / sendinput).
   - type_text, press_key (xdotool syntax), scroll, set_value, drag, focus.
   - run (shell, approval-gated).
3. **Concurrency (Input Stack System)**
   - Per-agent action stacks; target ownership map; lane router.
   - Parallel lanes: UIA, CDP, PostMessage. Serialized lane: SendInput.
4. **Isolation & takeover**
   - Private-desktop workers (`CreateDesktop`, `SetThreadDesktop`).
   - Takeover via `SwitchDesktop`; reclaim hotkey.
   - Glow overlay (layered click-through window) driven by a state machine.
5. **Interface**
   - CLI subcommands (see §12).
   - MCP server over stdio (JSON-RPC), persistent, tool registry.

---

## 6. System Architecture

```
                    AGENTS (opencode / Claude / Codex / custom)
                                   │
                          MCP over stdio  │  CLI
                                   ▼
              ┌──────────────────────────────────────────┐
              │            wcu  (main process)            │
              │  CLI parser ── MCP server ── config/perm │
              │                                           │
              │        INPUT ARBITER (scheduler)          │
              │  • per-agent stacks   • target ownership  │
              │  • lane router        • SendInput lock    │
              │  • takeover state machine                 │
              └──────┬──────────┬───────────┬─────────────┘
                     ▼          ▼           ▼
            ┌────────────┐ ┌─────────┐ ┌────────────────────┐
            │ UIA engine │ │ CDP drv │ │ Glow overlay / HUD │
            │ (tree+act) │ │ (Chrom) │ └────────────────────┘
            └─────┬──────┘ └────┬────┘
                  └─────┬───────┘
                        ▼
            ┌──────────────────────────────┐
            │   AGENT WORKERS (per desktop) │  ← each pinned to a private
            │  worker<Slack> on Desktop A   │    desktop (CreateDesktop)
            │  worker<Brave> on Desktop B   │
            │  worker<Notepad> on Desktop C │
            └──────────────────────────────┘
                        │
            ┌───────────▼────────────────────┐
            │  Windows layer                 │
            │  core:sys/windows + hand-written│
            │  UIA COM bindings + CDP WS     │
            └────────────────────────────────┘
```

Key principle: the **arbiter is a scheduler, not a bottleneck** - most actions
flow through parallel lanes and never meet.

---

## 7. Perception System (the "eyes")

- **Text tree is the screen.** Render:
  ```
  App=Slack.exe (pid 8123)  Window: "workspace - Slack"
  [0]  window "workspace - Slack"
  [1]    pane
  [2]      button "New message"     (20,48,120,32)
  [3]      textbox value="hello"    (0,600,640,150)
  Focused element: [6] textbox
  ```
- Each node carries: index, role, name/value, enabled, bounding rect.
- Token budget controls: `max_nodes` (default ~1200), `max_depth` (default
  ~64), `text_limit` (default 500 chars).
- **TextPattern extraction** reads actual message/document content (how we
  read Slack messages as text).
- **Screenshot** is an accessory for vision models, never required.

---

## 8. Action System (the "hands")

Preference order (mirrors open-computer-use):

1. **UIA patterns** - `Invoke`, `SetValue`, `Scroll`, `SelectionItem`.
   No cursor, no focus, fully concurrent.
2. **CDP Input** (Chromium/Electron) - `Input.dispatchKeyEvent`,
   `Input.dispatchMouseEvent`, `Input.dispatchTouchEvent`,
   `Input.insertText`, `Input.synthesizeScrollGesture`.
   Per-browser-instance, fully independent.
3. **Posted messages** - `PostMessage`/`SendMessage` to the target HWND
   (classic Win32 windows; same-desktop, same-integrity only).
4. **SendInput** - physical cursor/keys, **globally serialized**, gated
   behind `ALLOW_GLOBAL_POINTER_FALLBACKS=1`.

Every action returns a **fresh snapshot** so the agent can verify its effect.

---

## 9. Input Stack System (concurrency)

The unit of concurrency is a **per-agent action stack**:

```
 Agent A  ──stack──▶  target: Slack     lanes: [UIA, CDP]
 Agent B  ──stack──▶  target: Brave     lanes: [CDP]
 Agent C  ──stack──▶  target: Notepad   lanes: [UIA, PostMessage]
        │
        ▼
        INPUT ARBITER
        • target ownership map  (1 agent per target)
        • lane router
        • global mutex ONLY on SendInput lane
        • focus discipline  (foreground = own target only)
        • takeover state machine + glow control
```

**Stack semantics**
- **push(action)** - append a frame `{lane, target, op, args}` to an agent's
  stack.
- **execute** - pop serially; route to the correct lane.
- Per-agent ordering, isolation, and pause/resume.
- **Batch frames**: `push(type "...")` + `push(waitUntil(tree contains "..."))`
  for self-verifying sequences.

**Non-interference guarantees**
| Guarantee | Mechanism |
|---|---|
| No shared targets | ownership map; arbiter rejects double-claim |
| No shared cursor/keys | parallel lanes; only SendInput takes a mutex |
| No focus fights | each agent foregrounds only its own window |
| No shared perception | each agent reads only its own tree/DOM |

---

## 10. Virtual Input Channels

| Channel | Scope | Concurrency | Notes |
|---|---|---|---|
| **UIA patterns** | any a11y-exposing desktop app | ✅ parallel | primary |
| **CDP Input** | Chromium/Electron (Chrome, Edge, Brave, Slack) | ✅ parallel | WS + JSON-RPC per instance |
| **PostMessage** | classic Win32 windows | ✅ parallel | same-desktop, same-integrity; ignored by some modern apps |
| **SendInput** | anything | ❌ serialized | global lock, physical cursor |

Synthetic HID devices (VHF/Interception) are explicitly **not** used: they
still feed the single global input stream and give no per-app routing.

---

## 11. Isolation & Takeover

### 11.1 Private desktops
- Each agent's app runs on a **private desktop** (`CreateDesktop`), invisible
  to the user.
- A **worker process** per desktop (`SetThreadDesktop`) hosts that desktop's
  UIA client and CDP connection, because UIA/COM and window messages only
  flow between processes on the **same desktop**.
- The user's desktop stays the **input desktop** → the agent physically cannot
  steal the user's cursor in background mode.

### 11.2 Takeover state machine
| State | Input owner | Visual |
|---|---|---|
| Idle | user | no glow |
| Background work | user (agent uses virtual channels) | subtle glow |
| Takeover | agent (`SwitchDesktop`) | strong glow + "AI in control" |

- **Reclaim hotkey** → `SwitchDesktop(default)`, glow fades.
- **Emergency stop hotkey** → cancels in-flight work, reclaims desktop.

### 11.3 Glow overlay
- Full-screen, always-on-top, **click-through** window:
  `WS_EX_LAYERED | WS_EX_TRANSPARENT | WS_EX_TOOLWINDOW | WS_EX_NOACTIVATE`.
- `UpdateLayeredWindow` per-pixel alpha → glowing border ring; transparent
  center.
- Color/opacity driven by the state machine; optional HUD label.
- Optional live preview via `DwmRegisterThumbnail`.

---

## 12. CLI & MCP Interface

### 12.1 CLI (human/script surface)
```
wcu list_apps
wcu state <app> [--text-limit N] [--max-nodes N] [--max-depth N] [--screenshot]
wcu click <app> [--index I | --x X --y Y] [--method auto|uia|sendinput]
wcu type <app> "<text>"
wcu key <app> "<ctrl+s>"
wcu scroll <app> --index I --dir up|down|left|right [--pages N]
wcu set_value <app> --index I --value "<v>"
wcu focus <app>
wcu wake <app>
wcu run "<command>"            # approval-gated
wcu screenshot <app> --out f.png
wcu new-desktop <name>         # create a workspace for an agent
wcu move-app <app> <desktop>
wcu doctor
wcu mcp                        # run the MCP server (stdio, persistent)
```

### 12.2 MCP tools (agent surface)
| Tool | Kind | Notes |
|---|---|---|
| `list_apps` | read | running apps/windows |
| `get_app_state` | read | text tree (+ optional screenshot) |
| `click` | action | element_index primary, x/y fallback |
| `type_text` | action | focused/element target |
| `press_key` | action | xdotool syntax |
| `scroll` | action | element, direction, pages |
| `set_value` | action | settable elements |
| `focus` | action | foreground a window |
| `wake` | action | force Chromium accessibility |
| `run` | action | shell, approval-gated |
| `screenshot` | read/action | PNG, optional |
| `doctor` | read | permissions/session health |

All tools carry `readOnlyHint`/`destructiveHint` annotations.

---

## 13. Reliability Engineering

Proven rules (validated against Slack and Brave):

1. **Persistent process.** The MCP server never tears down its UIA client →
   fixes Chromium's sparse-tree behavior.
2. **Wake + poll.** Before every snapshot, send `WM_GETOBJECT (OBJID_CLIENT)`
   to the top-level window and all descendant HWNDs; poll up to ~15s.
3. **Force-foreground before input.** Thread-attach trick + verify
   `GetForegroundWindow()==target`.
4. **Fresh snapshot after every action** (indices are per-snapshot).
5. **Handle revalidation** with clear errors; `doctor` for health.

---

## 14. Security & Safety

- Approval policy for `run` and destructive actions (MCP annotations +
  config).
- Allow/deny app list.
- No secrets logged; config holds no tokens.
- Input never crosses integrity boundaries (UIPI respected - equal/lower
  integrity only).
- Takeover is always user-revocable (hotkeys).

---

## 15. Non-Functional Requirements

| Concern | Requirement |
|---|---|
| Binary size | single static `.exe`, < 10 MB target |
| Latency | `state` < 2s; actions < 1s typical |
| Concurrency | ≥ 4 simultaneous agents on different targets |
| Idle CPU | ~0 when idle; no busy polling |
| Memory | < 100 MB typical |
| Platform | Windows 10/11 x64; no admin required for user-level use |
| Observability | `doctor`; per-agent logs; glow reflects state |

---

## 16. Technology Choices & Rationale

- **Odin** - static binary, direct Win32/COM interop, fast compile; we proved
  the pattern with `rickroll`.
- **core:sys/windows** - windowing, SendInput, COM base, ShellExecute.
- **Hand-written UIA COM bindings** - `IUIAutomation`, elements, patterns,
  tree walkers (the one gap in core:sys/windows).
- **CDP over WebSocket** - per-Chromium-instance input; small WS/JSON-RPC
  client (Odin `core:net` + a minimal WS implementation or vendored lib).
- **MCP stdio** - JSON-RPC framing, hand-rolled (small), agent-agnostic.

---

## 17. Roadmap

| Phase | Scope | Exit criteria |
|---|---|---|
| **P0 ✅** | Proofs: window find/foreground/click/keys (rickroll); UIA tree + wake + send (Slack); persistence fix | done |
| **P1** | Project skeleton, UIA COM bindings, window discovery, text-tree renderer → `list_apps` + `state` | `state` renders Notepad + Slack correctly |
| **P2** | Actions: click-by-index (Invoke), set_value, scroll, type_text, press_key; SendInput fallback; focus | click/type work on Notepad + Slack |
| **P3** | Input Stack System: stacks, arbiter, ownership, parallel lanes | two agents on two apps concurrently |
| **P4** | MCP server (stdio, persistent), tool registry, annotations | connect from opencode/Claude |
| **P5** | CDP driver, `run`, screenshot, `wake`, config/permissions | Chromium input via CDP |
| **P6** | Isolation: private-desktop workers, takeover, glow overlay, preview | takeover + glow demo |
| **P7** | Hardening: retries, `doctor`, tests, docs, packaging | release-candidate |

---

## 18. Testing Strategy

- **UIA-rich apps:** Notepad, File Explorer (control-type coverage).
- **Chromium wake:** Slack, Brave (wake/poll/persistence).
- **Parallelism:** script 3 agents against 3 apps; assert no cross-talk.
- **Takeover:** assert input-desktop switches + glow state transitions +
  hotkey reclaim.
- **E2E demo:** the Slack self-chat flow (read → type → send → verify).

---

## 19. Known Limitations & Mitigations

| Limitation | Mitigation |
|---|---|
| Chromium a11y is lazy (Electron apps "go dark") | wake + poll + persistent client (proven) |
| Apps with no a11y (games, some canvas apps) | CDP for web; SendInput fallback; documented blind spot |
| Posted messages ignored by modern apps | prefer UIA/CDP; post only as last Win32 option |
| SendInput only works on input desktop | never rely on it for private-desktop agents; virtual channels only |
| UIPI blocks cross-integrity input | equal/lower integrity targets only |
| Virtual desktops share one input queue | they're for viewing, not isolation (private desktops are) |

---

## 20. Risks

| Risk | Severity | Mitigation |
|---|---|---|
| Agent misbehaves on user's apps | High | approval policy, allow/deny, emergency stop |
| Takeover leaves user "locked out" | Med | reclaim hotkey, timeout auto-reclaim |
| UIA gaps in specific apps | Med | CDP + SendInput lanes, docs |
| Odin CDP WS client effort | Med | minimal hand-rolled client; vendored lib fallback |
| Feature creep | Med | strict phases; non-goals enforced |

---

## 21. Glossary

- **UIA / UI Automation** - Windows accessibility API exposing UI elements as
  a tree with roles, names, values, rects, and patterns (Invoke, Value, …).
- **CDP** - Chrome DevTools Protocol; per-browser-instance control plane,
  includes an Input domain for dispatching events into a page.
- **Input desktop** - the single active desktop that receives physical and
  injected input.
- **Private desktop** - a non-visible desktop created via `CreateDesktop`,
  used to isolate an agent's app from the user's.
- **SendInput** - Win32 API that injects serialized keyboard/mouse events into
  the global input stream.
- **MCP** - Model Context Protocol; agent-to-tool protocol over JSON-RPC.
- **Sparse tree** - Chromium temporarily dropping its accessibility tree when
  no client is connected.

---

*End of specification.*
