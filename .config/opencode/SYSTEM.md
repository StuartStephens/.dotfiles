# Stuart's Operating Environment

All agents must read and respect this context. It applies regardless of whether you were invoked directly by Stuart or delegated to by another agent.

## OS Detection (Read This First)

Before providing any terminal commands or package manager recommendations, **detect which OS you are running on**:

**On Linux:**
```xonsh
cat /etc/os-release
```
Look for `ID=` field:
- `ID=bazzite` → Use Bazzite rules
- `ID=cachyos` or `ID_LIKE="arch"` → Use CachyOS/Arch rules  
- `ID=linuxmint` or `ID=mint` → Use Linux Mint rules
- `ID=kubuntu` or `ID=ubuntu` with KDE → Use Kubuntu rules

**On macOS:**
```xonsh
uname
```
Returns `Darwin` → Use macOS rules

**If detection fails or you're unsure:** Ask Stuart which OS, but only as a last resort.

**Always log your detection** in responses when providing OS-specific commands (e.g., "Detected OS: Bazzite, using flatpak/brew").

## Shell

**xonsh** is the shell. Not bash. Not zsh. Not sh.

- Never write `export VAR=value` → use `$VAR = "value"` in xonsh
- Never write `#!/bin/bash` or `#!/bin/sh` shebangs
- Never chain commands with `&&` as a bash idiom — use `;` or separate subprocess calls
- Subprocess capture: `$(cmd arg)` (captured output) or `![cmd arg]` (runs, returns CompletedProcess)
- When explaining shell usage, always use xonsh syntax and label it as xonsh
- If a task requires a shell script, write a `.xsh` file, not a `.sh` file

## System

- **OS**: Multi-machine (see OS Detection section above)
- **Package manager**: OS-specific (see Package Manager Rules below)
- **Terminal**: WezTerm
- **Editor**: Neovim (`nvim`)
- **Home directory**: Always use `$HOME` in all commands and paths — never hardcode `/home/stuart`, `/var/home/sstephens`, or `/Users/stuart`
  - `$HOME` expands to `/var/home/sstephens` on Bazzite, `/home/stuart` on CachyOS/Kubuntu/Mint, `/Users/stuart` on macOS
- **Git identity**: Stuart <contact@stuartstephens.com>

## Package Manager Rules by OS

Use the detected OS (see "OS Detection" above) to determine the correct package manager:

### Bazzite (Fedora-based, immutable/ostree)

- **System packages** (requires reboot): `rpm-ostree install <pkg>` — avoid unless necessary
- **GUI applications** (preferred): `flatpak install <pkg>`
- **Dev tools/CLI** (preferred): `brew install <pkg>` — Homebrew is installed at `/home/linuxbrew/.linuxbrew/bin`
- **Never use**: `dnf` (legacy compatibility only), `pacman`, `apt`
- **Mutable environments**: `distrobox` for development containers (check if inside before recommending packages)

### CachyOS (Arch Linux)

- **System packages**: `pacman -S <pkg>`
- **AUR packages**: `yay -S <pkg>`
- **Never use**: `apt`, `dnf`, `snap`
- **Homebrew**: Installed but not preferred — only suggest if Stuart explicitly requests it

### macOS

- **Everything**: `brew install <pkg>`
- **GUI applications**: `brew install --cask <pkg>`
- **Never use**: `pacman`, `apt`, `port`

### Linux Mint (Ubuntu-based)

- **System packages**: `apt install <pkg>`
- **GUI applications**: `flatpak install <pkg>` (if available)
- **Never use**: `pacman`, `dnf`, `brew`

### Kubuntu (Ubuntu-based with KDE Plasma)

- **System packages**: `apt install <pkg>`
- **GUI applications**: `flatpak install <pkg>` (if available) or `apt install <pkg>`
- **KDE-specific apps**: Check for `kde-*` packages in apt first
- **Never use**: `pacman`, `dnf`, `brew`

## Terminal-First Workflow

Stuart works exclusively in the terminal. All responses must default to CLI approaches:

- Always give CLI commands, never GUI steps
- Assume all commands will be run in a WezTerm pane under xonsh
- **Always use `$HOME` in paths** — never hardcode user directories like `/home/stuart` or `/Users/stuart`
- Use environment variables (`$HOME`, `$UE_ROOT`, etc.) instead of absolute paths wherever possible

### Read First, Ask Second

Before asking Stuart for information, **always check these sources first** in this order:

1. **This file** (`~/.config/opencode/SYSTEM.md`) — OS info, shell syntax, general environment
2. **Dotfiles** — aliases, paths, tooling:
   - `~/.xonshrc` — top-level aliases and environment overrides (e.g. `ue` for UnrealEditor, `ssh-login`)
   - `~/.config/xonsh/rc.xsh` — full PATH setup, `$UE_ROOT`, and all installed tooling
3. **OS detection** — `/etc/os-release` or `uname` for package manager rules
4. **Only then ask Stuart** — if the information isn't documented anywhere above

Prefer documented aliases over generic equivalents whenever they exist. Do not invent commands that the dotfiles already provide under a different name.

## When delegating

If you are passing tasks or context to another agent, include a note that Stuart uses xonsh on [detected OS] so they don't produce incompatible commands.
