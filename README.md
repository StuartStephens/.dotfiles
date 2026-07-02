# dotfiles

Unified personal dotfiles for CachyOS.

## Managed configs

- `~/.wezterm.lua`
- `~/.xonshrc`
- `~/.config/xonsh/rc.xsh`
- `~/.config/opencode/opencode.jsonc`
- `~/.config/opencode/package.json`
- `~/.config/opencode/package-lock.json`
- `~/.config/gh-dash/config.yml`
- `~/.config/nvim/*` (copied from previous standalone repo)
- `~/.gitconfig`

## Notes

- Runtime/generated files are intentionally ignored.
- Optional local Git overrides live in `~/.gitconfig.local` (not tracked).

## Installation

### Prerequisites

> ⚠️ `fastfetch` is executed on every interactive xonsh startup in this config. Install it before using these shell files.

#### CachyOS (Arch-based)

```sh
sudo pacman -S git wezterm neovim fastfetch nodejs npm pipx
pipx install xonsh

# Alternative xonsh install:
yay -S xonsh

# Font used by wezterm config:
yay -S ttf-firacode-nerd
```

- Install `opencode` using the current official one-liner or binary from https://opencode.ai.

#### macOS (Homebrew)

```sh
brew install git neovim fastfetch node
brew install --cask wezterm
brew install xonsh
brew install --cask font-fira-code-nerd-font
```

- Install `opencode` using the current official install instructions at https://opencode.ai.

### Clone

```sh
git clone https://github.com/<your-username>/dotfiles.git ~/dotfiles
```

### Symlink managed files

> ⚠️ Back up existing configs before symlinking (for example: `~/.gitconfig`, `~/.wezterm.lua`, `~/.xonshrc`, `~/.config/xonsh/rc.xsh`, `~/.config/opencode/*`, `~/.config/gh-dash/config.yml`, and `~/.config/nvim`).

```sh
mkdir -p ~/.config/xonsh ~/.config/opencode ~/.config/gh-dash

ln -s ~/dotfiles/.gitconfig ~/.gitconfig
ln -s ~/dotfiles/.wezterm.lua ~/.wezterm.lua
ln -s ~/dotfiles/.xonshrc ~/.xonshrc

ln -s ~/dotfiles/.config/xonsh/rc.xsh ~/.config/xonsh/rc.xsh

ln -s ~/dotfiles/.config/opencode/opencode.jsonc ~/.config/opencode/opencode.jsonc
ln -s ~/dotfiles/.config/opencode/package.json ~/.config/opencode/package.json
ln -s ~/dotfiles/.config/opencode/package-lock.json ~/.config/opencode/package-lock.json

ln -s ~/dotfiles/.config/gh-dash/config.yml ~/.config/gh-dash/config.yml

ln -s ~/dotfiles/.config/nvim ~/.config/nvim
```

### Install opencode npm dependencies

```sh
cd ~/dotfiles/.config/opencode && npm install
```

### Set xonsh as default shell

#### Linux

```sh
echo $(which xonsh) | sudo tee -a /etc/shells && chsh -s $(which xonsh)
```

#### macOS

```sh
echo $(which xonsh) | sudo tee -a /etc/shells && chsh -s $(which xonsh)
```

`which xonsh` should resolve to `/opt/homebrew/bin/xonsh` on macOS.

### Personalisation

1. Copy local Git template, then edit name/email:

   ```sh
   cp ~/dotfiles/.gitconfig.local.example ~/.gitconfig.local
   ```

2. Update hardcoded paths:

   > ⚠️ `~/.xonshrc` and `~/.config/xonsh/rc.xsh` contain `/home/stuart/` paths. Replace them with your own home path (or `$HOME`).

3. Set `GITHUB_PERSONAL_PAT` (used by opencode GitHub MCP):

   ```sh
   export GITHUB_PERSONAL_PAT=<your token>
   ```

   Add this export to `~/.gitconfig.local` or your shell environment file. This variable is only needed for opencode's GitHub MCP integration.
