# Contributing

Thanks for contributing to wcu. This project is tracked issue-by-issue on the
GitHub project board, so the workflow is small and reviewable.

## Pick up work

The source of truth for what to do next is the project board:

```powershell
gh project item-list 9 --owner aquaticcalf
```

Or filter issues by area:

```powershell
gh issue list --repo aquaticcalf/windows-computer-use --label "area:perception"
```

Rules of thumb:

- Move an issue to `In Progress` before starting it.
- Keep work to one issue per commit where possible.
- Move the issue to `Done` only after the acceptance criteria pass.

## Setup

```powershell
git clone https://github.com/aquaticcalf/windows-computer-use
cd windows-computer-use
.\build.ps1 build
.\build.ps1 test
```

## Workflow

1. Branch from `main`: `git checkout -b fix/descriptive-name`
2. Implement, keeping the change small and focused.
3. Run checks locally:
   - `odin check cmd/wcu`
   - `odin test internal/version`
   - `.\build.ps1 build`
4. Commit with a concise message; reference the issue it closes:

   ```
   Implement xyz

   Closes #N
   ```
5. Push and open a pull request against `main`.
6. Move the linked issue to `Done` once merged and verified.

CI is manual only (Actions > CI > Run workflow); there is no push-triggered CI.

## Conventions

- Odin. This repo targets the nightly dev build of Odin.
- Type checks use `odin check` (the `vet` command does not exist in this
  Odin version).
- Use `name: Type` declarations, not `var name: Type`.
- No trailing commas in multi-line procedure calls.
- Keep imports to `core:` and `internal/`; no new third-party deps without a
  discussion.
- Written text uses hyphens, not em dashes.
- Keep code and config free of credentials. Never commit tokens, keys, or
  personal emails in code, docs, or config files.

## Structure

```
cmd/wcu/         CLI entrypoint
internal/        shared packages (version, then windows, perception, input...)
.github/workflows/ci.yml   manual CI
ARCHITECTURE.md  product and system specification
```

## Security

- Treat every shell command and destructive action as gated.
- Never hardcode secrets; read them from environment variables or local,
  gitignored config files only.
