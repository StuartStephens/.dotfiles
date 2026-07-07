# Stuart's Operating Environment

All agents must read and respect this context. It applies regardless of whether you were invoked directly by Stuart or delegated to by another agent.

## Shell

**xonsh** is the shell. Not bash. Not zsh. Not sh.

- Never write `export VAR=value` → use `$VAR = "value"` in xonsh
- Never write `#!/bin/bash` or `#!/bin/sh` shebangs
- Never chain commands with `&&` as a bash idiom — use `;` or separate subprocess calls
- Subprocess capture: `$(cmd arg)` (captured output) or `![cmd arg]` (runs, returns CompletedProcess)
- When explaining shell usage, always use xonsh syntax and label it as xonsh
- If a task requires a shell script, write a `.xsh` file, not a `.sh` file

## System

- **OS**: CachyOS (Arch Linux)
- **Package manager**: `pacman` / `yay` (AUR) — never suggest `apt`, `brew`, `snap`, or `dnf`
- **Terminal**: WezTerm
- **Editor**: Neovim (`nvim`)
- **Home directory**: `/home/stuart`
- **Git identity**: Stuart <contact@stuartstephens.com>

## Terminal-First Workflow

Stuart works exclusively in the terminal. All responses must default to CLI approaches:

- Always give CLI commands, never GUI steps
- Assume all commands will be run in a WezTerm pane under xonsh

Before suggesting commands for any project, **actively read** the dotfiles to find existing aliases and available tooling:

- `~/.xonshrc` — top-level aliases and environment overrides (e.g. `ue` for UnrealEditor, `ssh-login`)
- `~/.config/xonsh/rc.xsh` — full PATH setup, `$UE_ROOT`, and all installed tooling

Prefer documented aliases over generic equivalents whenever they exist. Do not invent commands that the dotfiles already provide under a different name.

## When delegating

If you are passing tasks or context to another agent, include a note that Stuart uses xonsh and CachyOS so they don't produce incompatible commands.

## Code Repository Workflow

### agents.md gate

- At task start, if current directory is inside a git repo, run `git rev-parse --show-toplevel` and resolve the repo root.
- If `git rev-parse --show-toplevel` fails, skip this gate. It only applies inside git repos.
- Before any other action inside a repo, check for `agents.md` at the repo root.
- If `agents.md` is missing, stop and ask Stuart for the required fields before proceeding. Do not assume defaults and continue.
- If `agents.md` exists but `requirements-source` is missing, stop and ask for `requirements-source` specifically. This is the only field that cannot be skipped or defaulted.
- If `agents.md` exists but any other field is missing, ask for each missing field and explicitly offer a "skip / use defaults" option per field. Record skipped fields as intentionally omitted.

### agents.md schema

Canonical `agents.md` frontmatter schema:

```yaml
---
requirements-source: jira | norg
norg-requirements-location: docs/requirements/   # path relative to repo root; only needed when source=norg; defaults to repo root
business-logic: |
  [free text describing domain context agents need]
tech-implementation: |
  [free text: key patterns, constraints, gotchas]
coding-conventions: default | [description]
testing-strategy: default | [description]
branch-commit-conventions: default | [description]
package-commands:
  build: [command]
  run: [command]
  test: [command]
---
```

`requirements-source` is the only required field. All others may be omitted or defaulted:

- `coding-conventions: default` → follow language/framework standard practices.
- `testing-strategy: default` → use the standard test runner for the stack.
- `branch-commit-conventions: default` → follow the global dotfiles conventions.

### Requirements workflow

- Requirements live in committed `.norg` files (Neorg format) in the repo.
- If `requirements-source: jira`, Jira ticket content is pasted directly into the session. The PM agent treats pasted ticket text as requirements input.
- If `requirements-source: norg`, the PM agent reads the relevant `.norg` file(s) from the repo before asking any questions.
- Per-feature requirements files are committed to the feature branch. Location follows `norg-requirements-location` in `agents.md` and defaults to repo root when omitted.
- Name requirements files as `<feature-slug>.norg` (example: `grunt-ai-marching.norg`).

### TODO.norg per worktree

- `TODO.norg` at worktree root is the per-session scratchpad. It is local-only and never committed.
- Immediately after creating a worktree, add `TODO.norg` to that worktree's `.git/info/exclude`.
- At session start, if `TODO.norg` exists, read it and surface task-relevant items before taking action.
- Agents may update `TODO.norg` at natural pause points with outstanding items, blockers, and follow-ups.
- Before removing a worktree, read `TODO.norg` and surface unresolved items to Stuart.
- `TODO.norg` must never appear in `git status`, never be staged, and never be committed.
