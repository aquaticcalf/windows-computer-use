# Odin Style Guide (wcu)

The one rule that is not negotiable: **code must compile clean under the
strict vet flags**. Treat warnings as errors, and run `odinfmt` before
finishing.

```
odin build cmd/wcu -vet -strict-style -vet-tabs -disallow-do -warnings-as-errors
```

If the compiler or formatter pushes back, that is a signal to write it the
idiomatic way, not to work around the tooling.

## Formatting

- Tabs for indentation. Spaces for alignment across lines (tab-width
  independent).
- Opening brace at end of line (1TBS), for procs, structs, and control flow.
  This matches what `-strict-style` enforces.
- No single-line `do` blocks. Always use braces.
- Run `odinfmt` (configured via `odinfmt.json`) before finishing; it enforces
  width, tabs, brace style, `do` conversion, and import sorting.

## Naming

| Kind | Case | Example |
|---|---|---|
| Types | `Ada_Case` | `Http_Request`, `Roster` |
| Enum values | `Ada_Case` | `.Running`, `.Not_Found` |
| Procedures | `snake_case` | `load_roster`, `parse_header` |
| Variables, fields | `snake_case` | `window_width`, `age` |
| Constants | `SCREAMING_SNAKE_CASE` | `MAX_ENTITIES`, `OBJID_CLIENT` |
| Package / import names | `snake_case`, one word | `package uia`, `import vmem` |

One package per directory; the `package` name matches the folder. Alias long
imports to a short name.

## Comments and documentation

Documentation is a first-class part of the code. Every public symbol in a
package carries a doc comment so an IDE, another agent, and a future reader
know exactly what it is without reading the body.

- **Doc comments on everything public**: every procedure, type, enum value,
  constant, and non-obvious struct field gets a `//` comment above it.
- **Start the comment with the symbol name** (Go-style): `// list enumerates
  top-level windows.` The first sentence says what the thing is in one line.
- **Say what, why, and the contract**: for procedures, cover parameters,
  return values, error behavior, ownership of allocated memory, and any
  ordering or lifetime rules a caller must honor. For types, describe the
  zero value and when it is valid.
- **Document the surface, not the body.** Do not restate the code line by
  line; say what a caller needs to know. Comment the tricky internals only
  where the why is not obvious.
- **Keep comments current.** A comment that no longer matches the code is
  worse than none; update it in the same change that edits the code.
- Package files start with a short comment naming the package and its
  purpose (what it owns and what lives behind it, per DESIGN.md).

```odin
// create builds a UI Automation session and its control-view walker.
// The caller owns the session and must call destroy when done.
create :: proc() -> (Automation, Error) { ... }
```

Regular `//` line comments are for intent ("why"), not restatements ("what").


## Declarations and initialization

- Write `val: int` and `val := 5` (colon hugs the name, space after it).
- Prefer type inference: `x := f()` over `x: T = f()`.
- Prefer `x := T { field = ..., }` over `x: T = { ... }`. Use compound
  literals with a trailing comma instead of field-by-field assignment.
- Design types so the zero value is valid; rely on zero-initialization.
- Keep types concrete; avoid speculative generics and OOP patterns. No
  inheritance, no RAII, no constructors. Structs plus free procedures.

## Errors

- Errors are values, not exceptions. Each package owns its error type
  (enum or union); there is no universal error type.
- Propagate with `or_return`, supply fallbacks with `or_else`. Use
  `or_return` freely within a package; be deliberate across package
  boundaries.
- `ensure`/`assert` only for invariants and unrecoverable failures, never for
  errors a caller could handle.

## Control flow and defer

- Iterate read-only with `for x in xs`; mutate with `for &x in xs`.
- Use `defer` only when a scope has multiple exit paths and cleanup must run
  in all of them. Single-exit scopes: write cleanup inline.

## Memory and allocators

- Procedures that allocate take `allocator := context.allocator` and pass it
  through.
- Prefer slices `[]T` in parameters. Pass `^[dynamic]T` only when resizing
  the container.
- Pair every `make`/`new` with `delete`/`free` (or a `destroy_*` proc).
- Use `context.temp_allocator` for scratch work.
- Do not repurpose `context` fields; the context exists for callers to
  intercept allocation, logging, and rng.

## Dependencies

No package manager. Prefer `core:` and `vendor:`; copy small dependencies
into the repo and pin them. Do not add a dependency without discussion.

## Project tooling

- Build and check with the strict flags above via `build.ps1` / `make`.
- `ols.json` wires OLS to run the same checks in the editor.
- New Odin files must pass `odinfmt` and the strict flags before commit.
