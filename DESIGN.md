# Codebase Design Guide (wcu)

This is the design doctrine for this repository. Read it before designing a new
module, restructuring an existing one, or placing a seam. It works alongside
`ARCHITECTURE.md` (what we build) and `STYLEGUIDE.md` (how the code reads).

## The one aim

Prefer modules that **hide a lot of behaviour behind a tiny surface**. A caller
should get maximum capability for the smallest amount they have to learn, and a
maintainer should be able to change, debug, and verify one thing in one place
without touching the many places that use it.

## Shared vocabulary

Use these terms consistently in code reviews and docs. Do not reach for
looser words like "component", "service", or "boundary".

- **Module** - anything with an interface and an implementation. Deliberately
  scale-free: a procedure, a package, a whole tier. It can be small or large.
- **Interface** - everything a caller must know to use a module correctly:
  the signatures, but also ordering rules, error behavior, required setup, and
  performance expectations. Broader than "the public methods".
- **Implementation** - what lives inside the module. A thing may be a thin
  adapter with a lot of logic behind it, or a big adapter over a tiny core.
- **Seam** - a place where behaviour can be swapped without editing the
  callers. Where the interface physically lives.
- **Adapter** - a concrete thing that fills an interface at a seam. It is a
  role ("what slot it fills"), not a substance ("what it is made of").
- **Depth** - the payoff a caller gets per unit of interface they learn. Deep
  = lots of behaviour behind a small surface. Shallow = the surface is almost
  as complicated as what is inside.
- **Leverage** - what callers gain from depth: one implementation pays back
  across every call site and every test.
- **Locality** - what maintainers gain from depth: knowledge, bugs, and fixes
  concentrate in one module instead of spreading across callers.

## Deep beats shallow

Prefer this shape:

```
  tiny surface   <- few entry points, simple parameters
  --------------
  real behaviour <- the hard logic lives here
```

Avoid this one:

```
  big surface    <- many entry points, fiddly parameters
  --------------
  thin forwarding <- just passes through
```

When a surface grows, ask: can we drop an entry point? Can the parameters get
simpler? Can more work move behind the surface?

## Design rules

1. **Depth belongs at the surface, not inside.** A deep module may be built
   from small swappable parts; those parts just are not part of the public
   surface.
2. **The deletion test.** Imagine removing the module. If the complexity
   simply vanishes, it was a pass-through. If the complexity reappears at
   every call site, the module earns its place.
3. **The surface is the test surface.** Callers and tests cross the same
   seam. If a test must reach past the interface to be convincing, the module
   is probably the wrong shape.
4. **Seams must be earned.** One adapter proves nothing; it is indirection.
   A seam is real only when two adapters are genuinely justified, typically a
   production one and a test one. Do not add a port for a single adapter.
5. **Do not leak internal seams.** A module may keep private seams for its own
   tests; that is fine. Do not expose them through the public surface.

## Testability rules

- **Inject dependencies; do not build them inside.** If a procedure constructs
  its own hardware/network/tooling object, testing it means testing the world.
  Take the dependency as a parameter.
- **Return results instead of producing side effects.** A procedure that
  computes and returns a value is trivial to test. One that mutates shared
  state and returns nothing forces awkward setup and teardown.
- **Keep the surface small.** Fewer entry points means fewer tests; simpler
  parameters means simpler test fixtures.

## Dependency classes and how to handle them

When designing a module, classify each dependency and pick the approach that
matches:

| Class | What it is | Approach |
|---|---|---|
| In-process | Pure computation, memory only, no I/O | Deepen freely and test straight through the new surface |
| Local stand-in | Has a faithful local substitute (a fixture app, an in-memory tree) | Deepen; test against the stand-in; the seam stays internal |
| Owned remote | Our own service across a network | Define a port at the seam; production and test adapters |
| True external | Something we do not control (Windows COM, UIA, CDP, a vendor) | Treat as injected; provide a fake adapter in tests |

Windows specifics for this repo: UIA, COM, and CDP are all "true external"
dependencies. We must not let them leak through our modules. We define our own
interfaces for them and keep the raw bindings behind adapters, so tests run
against scripted fakes instead of a real desktop.

## Testing: replace, don't layer

- Once a deepened module has tests at its surface, drop the old shallow-module
  tests; they are dead weight.
- New tests assert observable outcomes through the surface, not internal
  state.
- Tests should survive a refactor of the implementation. If a test must change
  whenever the body changes, it is testing past the interface.

## How this maps onto wcu

| Area | The surface callers see | What hides behind it |
|---|---|---|
| Perception | `state <app>` returns a rendered text tree | UIA walking, Chromium wake + poll, limits, rendering |
| Input | One small set of action calls | Pattern dispatch, lane selection, focus discipline, SendInput fallback |
| Concurrency | Per-agent stack API (push, execute, pause, resume) | Target ownership, lane routing, the shared-input lock |
| CDP | A tiny driver surface (connect, dispatch key/mouse/text) | WebSocket + JSON-RPC framing |
| MCP | The tool registry + handlers | Stdio framing, sessions, annotations |
| Isolation | `Agent_Worker` per private desktop | Desktop creation, worker IPC, takeover, glow |

Placement notes:

- **Perception and input meet at a seam.** Perception produces element
  indices; input consumes them. Keep the two behind one small "app session"
  surface so agents never touch the internals of either.
- **Lanes sit behind the arbiter.** The arbiter exposes a minimal stack
  surface and treats each input lane (UIA, CDP, posted messages, SendInput)
  as an adapter. Tests drive the arbiter with a fake lane; only the SendInput
  lane needs the global lock.
- **UIA and CDP are adapters, never callers.** Raw COM and WebSocket code
  stays at the leaves. Everything above them sees only our own types.
- **The arbiter stays the single owner of concurrency.** Do not spread locks,
  ownership maps, or stack logic into individual tools.

## Designing a new module

1. Write a short user-facing statement of the problem: the constraints the
   surface must satisfy, the dependencies and which class each falls into, and
   a rough sketch to make the constraints concrete.
2. Sketch at least two or three deliberately different surfaces: one that
   minimizes entry points, one that maximizes flexibility, one that makes the
   common case trivial.
3. Compare them on depth (payoff per unit learned), locality (where change
   concentrates), and seam placement (is the seam earned?).
4. Pick one, or merge the best parts. Be decisive; record the choice and the
   reason in the module's doc comment or in `ARCHITECTURE.md`.

## Anti-patterns to reject

- Wrappers that only forward and add nothing.
- Modules with a big surface and no behaviour behind it.
- Ports with a single adapter.
- Tests that reach past the interface.
- Spreading concurrency control or lock logic across many small tools.

---

*Write it deep, surface it small, and test it at the seam.*
