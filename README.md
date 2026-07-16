# dotfiles

Unified personal dotfiles for **CachyOS (Arch), Bazzite (Fedora/ostree), and macOS**.

## Managed configs

- `~/.wezterm.lua` or Ghostty config
- `~/.xonshrc`
- `~/.config/xonsh/rc.xsh`
- `~/.config/opencode/opencode.jsonc`
- `~/.config/opencode/package.json`
- `~/.config/opencode/package-lock.json`
- `~/.config/opencode/agent/*.md` (custom agents)
- `~/.config/gh-dash/config.yml`
- `~/.config/nvim/*`
- `~/.gitconfig`

## Notes

- Runtime/generated files are intentionally ignored.
- Optional local Git overrides live in `~/.gitconfig.local` (not tracked) - used on Mac for work profile switching.
- All paths use `$HOME` for cross-platform compatibility.

## Installation

### Prerequisites

> ⚠️ `fastfetch` is executed on every interactive xonsh startup in this config. Install it before using these shell files.

**Universal Requirements:**
- Terminal: ghostty, wezterm, or similar
- Shell: xonsh
- Editor: neovim with Copilot plugin
- Tools: fastfetch, git, nodejs, npm

#### CachyOS (Arch-based)

```sh
sudo pacman -S git wezterm neovim fastfetch nodejs npm pipx
pipx install xonsh

# Alternative xonsh install:
yay -S xonsh

# Font used by wezterm/ghostty config:
yay -S ttf-firacode-nerd
```

- Install `opencode` using the current official instructions from https://opencode.ai

#### Bazzite (Fedora/ostree)

```sh
# System packages (layered via rpm-ostree)
rpm-ostree install xonsh neovim npm go python3-neovim

# Ghostty (AppImage or from source)
# Fastfetch (pre-installed on Bazzite)

# Homebrew for additional tools
brew install gh
```

- Install `opencode` using the current official instructions from https://opencode.ai

#### macOS

```sh
brew install wezterm neovim fastfetch git nodejs
brew install --cask font-fira-code-nerd-font
pip3 install xonsh

# For work profile: create ~/.gitconfig.local with includeIf
```

- Install `opencode` using the current official instructions from https://opencode.ai

### Clone

```sh
git clone https://github.com/StuartStephens/dotfiles.git ~/.dotfiles
```

### Symlinking

After prerequisites are installed, symlink configs:

```sh
# Top-level files
ln -sf ~/.dotfiles/.xonshrc ~/.xonshrc
ln -sf ~/.dotfiles/.gitconfig ~/.gitconfig
ln -sf ~/.dotfiles/.wezterm.lua ~/.wezterm.lua

# Config directories
ln -sf ~/.dotfiles/.config/nvim ~/.config/nvim
ln -sf ~/.dotfiles/.config/opencode ~/.config/opencode
ln -sf ~/.dotfiles/.config/gh-dash ~/.config/gh-dash
ln -sf ~/.dotfiles/.config/xonsh ~/.config/xonsh

# Install OpenCode plugins
cd ~/.config/opencode && npm install

# Set xonsh as default shell
chsh -s $(which xonsh)
```

> **Note:** On Bazzite/Fedora, you may need to add xonsh to `/etc/shells` first if not already present:
> ```sh
> echo $(which xonsh) | sudo tee -a /etc/shells
> ```

### macOS Work Profile Setup

On Mac only (for work/personal git profile switching):

```sh
# Create ~/.gitconfig.local
cat > ~/.gitconfig.local << 'EOF'
[includeIf "gitdir:~/work/"]
    path = ~/.gitconfig.work
EOF

# Create ~/.gitconfig.work
cat > ~/.gitconfig.work << 'EOF'
[user]
    name = Stuart Stephens
    email = stuart@company.com
    signingkey = ~/.ssh/id_ed25519_work.pub
EOF
```

Now personal projects use personal SSH key, work projects use work SSH key automatically.
