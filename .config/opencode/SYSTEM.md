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
