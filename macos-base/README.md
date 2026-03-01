# macOS Base

The foundation layer of the DevOps stack. This directory manages Homebrew packages, macOS system preferences (`defaults`), shell environment, and global dotfiles so any new Mac can be bootstrapped to a consistent state in a single command.

---

## Role in This Stack

Every other directory in this repository depends on tools installed via Homebrew. `macos-base/` is the layer that installs and maintains those tools. Run `./scripts/manage.sh setup` first on any new machine before using `terraform/`, `kubernetes/`, or `networking/`.

---

## Prerequisites

| Requirement | Install | Notes |
|-------------|---------|-------|
| macOS ≥ 14 Sonoma | — | Apple Silicon (arm64) or Intel (x86_64) |
| Xcode CLT | `xcode-select --install` | Required by Homebrew and many formulae |
| Homebrew | See below | Installed automatically by `manage.sh setup` if missing |

---

## Directory Structure

```
macos-base/
├── README.md
├── scripts/
│   └── manage.sh              # Lifecycle: setup, healthcheck, teardown
└── supporting_files/
    └── Brewfile               # Declarative list of all Homebrew packages
```

---

## Common Recipes

| Task | Command |
|------|---------|
| Full setup (new machine) | `./scripts/manage.sh setup` |
| Update all packages | `./scripts/manage.sh healthcheck` |
| Show outdated packages | `brew outdated` |
| Install from Brewfile | `brew bundle --file=supporting_files/Brewfile` |
| Dump current installs | `brew bundle dump --file=supporting_files/Brewfile --force` |
| Apply macOS defaults | `./scripts/manage.sh setup` (included) |
| List all installed formulae | `brew list --formula` |
| List all installed casks | `brew list --cask` |
| Cleanup old versions | `brew cleanup --prune=7` |

---

## macOS System Defaults

`manage.sh setup` applies a set of `defaults write` commands to tune macOS for developer productivity. Highlights:

| Setting | Command | Why |
|---------|---------|-----|
| Faster key repeat | `defaults write NSGlobalDomain KeyRepeat -int 2` | Faster cursor movement in terminal |
| Show hidden files in Finder | `defaults write com.apple.finder AppleShowAllFiles true` | Reveal dotfiles |
| Full keyboard access | `defaults write NSGlobalDomain AppleKeyboardUIMode -int 3` | Navigate dialogs without mouse |
| Disable .DS_Store on network volumes | `defaults write com.apple.desktopservices DSDontWriteNetworkStores true` | Avoid polluting remote filesystems |
| Dock auto-hide | `defaults write com.apple.dock autohide -bool true` | More terminal screen space |

> These settings are idempotent — run them multiple times safely. Some require a logout/login to take effect.

---

## Shell Environment

The `manage.sh setup` command appends tool-specific environment variables to `~/.zshrc` if they are not already present:

- `STEPPATH` → `~/Library/Application Support/step`
- `TF_PLUGIN_CACHE_DIR` → `~/Library/Caches/io.terraform/plugin-cache`
- Homebrew `shellenv` init (for Apple Silicon PATH fix)

---

## Usage Examples

```zsh
# Bootstrap a brand-new Mac
cd macos-base/scripts && ./manage.sh setup

# Check that all tools from the Brewfile are installed
./manage.sh healthcheck

# Rollback / remove all devops-stack brew packages
REMOVE_CASKS=true ./manage.sh teardown
```

---

## macOS Notes

- On Apple Silicon, Homebrew installs to `/opt/homebrew/`. On Intel Macs it uses `/usr/local/`. The `manage.sh` script detects the architecture and adjusts paths accordingly using `$(brew --prefix)`.
- `defaults write` targets `~/Library/Preferences/*.plist` files. macOS caches these; `killall` restarts affected processes to pick up changes immediately.
- Never `sudo brew install` — Homebrew is explicitly designed to be run as your normal user.
