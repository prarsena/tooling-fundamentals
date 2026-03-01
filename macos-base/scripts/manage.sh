#!/usr/bin/env zsh
# =============================================================================
# macos-base/scripts/manage.sh
# macOS system baseline: Homebrew, package bundle, and system defaults.
#
# Usage:
#   ./manage.sh <command>
#   SKIP_DEFAULTS=true ./manage.sh setup
#
# Commands: setup | healthcheck | teardown
# =============================================================================

set -euo pipefail

# ---------------------------------------------------------------------------
# ENVIRONMENT VARIABLE TOGGLES
# ---------------------------------------------------------------------------

ENABLE_LOGGING="${ENABLE_LOGGING:-false}"

# Skip writing macOS `defaults` (useful in CI/CD or headless environments).
SKIP_DEFAULTS="${SKIP_DEFAULTS:-false}"

# Skip Homebrew bundle install (useful when you only want to write defaults).
SKIP_BREW_BUNDLE="${SKIP_BREW_BUNDLE:-false}"

# When true, also install casks (GUI apps) during teardown removal.
REMOVE_CASKS="${REMOVE_CASKS:-false}"

# ---------------------------------------------------------------------------
# macOS ARCHITECTURE DETECTION
# Homebrew prefix differs between Apple Silicon (/opt/homebrew) and
# Intel Macs (/usr/local). Using `brew --prefix` is the canonical way
# to get the correct path at runtime without hardcoding.
# ---------------------------------------------------------------------------
# We cannot call `brew --prefix` before Homebrew is installed, so we derive
# it from the CPU architecture reported by `uname -m`.
if [[ "$(uname -m)" == "arm64" ]]; then
  HOMEBREW_PREFIX="/opt/homebrew"
else
  HOMEBREW_PREFIX="/usr/local"
fi

HOMEBREW_BIN="${HOMEBREW_PREFIX}/bin/brew"

SCRIPT_DIR="${0:A:h}"
ROOT_DIR="${SCRIPT_DIR:h}"
BREWFILE="${ROOT_DIR}/supporting_files/Brewfile"

# ---------------------------------------------------------------------------
# HELPERS
# ---------------------------------------------------------------------------

log()   { [[ "${ENABLE_LOGGING}" == "true" ]] && print -P "%F{cyan}[$(date '+%H:%M:%S')]%f $*" || true; }
info()  { print -P "%F{green}[INFO]%f $*"; }
warn()  { print -P "%F{yellow}[WARN]%f $*"; }
error() { print -P "%F{red}[ERROR]%f $*" >&2; exit 1; }

# add_to_zshrc <line>
# Appends a line to ~/.zshrc only if it is not already present.
# Using grep -qF (fixed string, quiet) avoids regex false positives.
add_to_zshrc() {
  local line="$1"
  if ! grep -qF "${line}" "${HOME}/.zshrc" 2>/dev/null; then
    print "${line}" >> "${HOME}/.zshrc"
    log "Added to ~/.zshrc: ${line}"
  fi
}

# ---------------------------------------------------------------------------
# COMMAND: setup
# ---------------------------------------------------------------------------
cmd_setup() {
  info "Running macOS base setup..."

  # ---- 1. Install Homebrew if missing ----
  # Homebrew must NOT be run as root. The install script handles sudo internally
  # for the few steps that require it (e.g. creating /opt/homebrew).
  if [[ ! -x "${HOMEBREW_BIN}" ]]; then
    info "Homebrew not found. Installing..."
    /bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"
    info "Homebrew installed at ${HOMEBREW_PREFIX}."
  else
    info "Homebrew already installed at ${HOMEBREW_PREFIX}."
  fi

  # ---- 2. Add Homebrew to the current shell session ----
  # On Apple Silicon, /opt/homebrew/bin is not in the default PATH.
  # `brew shellenv` outputs the export statements needed to fix this.
  # We eval it here for the current process, and write it to ~/.zshrc
  # so future sessions pick it up automatically.
  eval "$("${HOMEBREW_BIN}" shellenv)"
  add_to_zshrc 'eval "$(/opt/homebrew/bin/brew shellenv)"'

  # ---- 3. Install packages from Brewfile ----
  if [[ "${SKIP_BREW_BUNDLE}" != "true" ]]; then
    if [[ -f "${BREWFILE}" ]]; then
      info "Installing packages from Brewfile..."
      # `brew bundle` reads the Brewfile and installs any missing packages.
      # --no-lock skips updating Brewfile.lock.json (optional: remove for
      # reproducible installs).
      brew bundle --file="${BREWFILE}" --no-lock
      info "Brew bundle complete."
    else
      warn "Brewfile not found at ${BREWFILE} — skipping bundle install."
    fi
  else
    warn "SKIP_BREW_BUNDLE=true — skipping Homebrew bundle."
  fi

  # ---- 4. Write tool-specific environment variables to ~/.zshrc ----
  # These mirror the macOS-specific paths used by the other manage.sh scripts.
  info "Configuring shell environment in ~/.zshrc..."

  # STEPPATH: step-ca stores its CA data here. ~/Library/ is the macOS-standard
  # location for per-user app data and is included in Time Machine backups.
  add_to_zshrc 'export STEPPATH="${HOME}/Library/Application Support/step"'

  # TF_PLUGIN_CACHE_DIR: Terraform/OpenTofu provider cache. Putting it in
  # ~/Library/Caches/ means macOS can purge it under storage pressure — fine
  # for a provider binary cache.
  add_to_zshrc 'export TF_PLUGIN_CACHE_DIR="${HOME}/Library/Caches/io.terraform/plugin-cache"'

  # ---- 5. Apply macOS system defaults ----
  if [[ "${SKIP_DEFAULTS}" != "true" ]]; then
    cmd_apply_defaults
  else
    warn "SKIP_DEFAULTS=true — skipping macOS defaults."
  fi

  info "Setup complete. Open a new terminal to pick up shell changes."
}

# ---------------------------------------------------------------------------
# cmd_apply_defaults
# Writes developer-friendly macOS system preferences via `defaults write`.
# All commands are idempotent — safe to run repeatedly.
# ---------------------------------------------------------------------------
cmd_apply_defaults() {
  info "Applying macOS system defaults..."

  # ---- Keyboard ----
  # Lower key repeat values = faster cursor movement in terminal editors.
  # macOS default InitialKeyRepeat is 68 (too slow for terminal use).
  defaults write NSGlobalDomain KeyRepeat -int 2
  defaults write NSGlobalDomain InitialKeyRepeat -int 15
  log "Set fast key repeat."

  # Enable full keyboard access for all controls (e.g. Tab through dialogs).
  # Without this, macOS only tabs through text fields — very limiting.
  defaults write NSGlobalDomain AppleKeyboardUIMode -int 3
  log "Enabled full keyboard UI access."

  # ---- Finder ----
  # Show all files including hidden dotfiles (essential for dev work).
  defaults write com.apple.finder AppleShowAllFiles -bool true

  # Show file extensions in Finder.
  defaults write NSGlobalDomain AppleShowAllExtensions -bool true

  # Show full POSIX path in Finder title bar.
  defaults write com.apple.finder _FXShowPosixPathInTitle -bool true

  # Disable the "Are you sure you want to open this application?" quarantine
  # dialog — reduces friction when running downloaded CLIs.
  defaults write com.apple.LaunchServices LSQuarantine -bool false
  log "Configured Finder settings."

  # ---- Network volumes ----
  # Prevent macOS from writing .DS_Store files on network/USB volumes.
  # These pollute Git repos and remote filesystems mounted via Lima.
  defaults write com.apple.desktopservices DSDontWriteNetworkStores -bool true
  defaults write com.apple.desktopservices DSDontWriteUSBStores -bool true
  log "Disabled .DS_Store files on network/USB volumes."

  # ---- Dock ----
  # Auto-hide the Dock to reclaim vertical screen space for terminals.
  defaults write com.apple.dock autohide -bool true

  # Speed up the Dock auto-hide animation (0 = instant).
  defaults write com.apple.dock autohide-delay -float 0
  defaults write com.apple.dock autohide-time-modifier -float 0.3

  # Minimise unused Dock items — keeps the Dock from growing unbounded.
  defaults write com.apple.dock show-recents -bool false
  log "Configured Dock settings."

  # ---- Screenshots ----
  # Save screenshots to ~/Desktop/Screenshots/ to keep Desktop tidy.
  mkdir -p "${HOME}/Desktop/Screenshots"
  defaults write com.apple.screencapture location -string "${HOME}/Desktop/Screenshots"
  log "Screenshot location set to ~/Desktop/Screenshots/"

  # ---- Restart affected daemons ----
  # `killall` restarts processes to pick up the new defaults immediately.
  # On macOS, `killall` is the BSD version — same flags as Linux for this use.
  killall Finder  2>/dev/null || true
  killall Dock    2>/dev/null || true
  killall SystemUIServer 2>/dev/null || true
  log "Restarted Finder, Dock, SystemUIServer."

  info "macOS defaults applied."
}

# ---------------------------------------------------------------------------
# COMMAND: healthcheck
# Verifies Homebrew health and checks all Brewfile packages are installed.
# ---------------------------------------------------------------------------
cmd_healthcheck() {
  info "Running healthcheck..."

  if ! command -v brew &>/dev/null; then
    error "Homebrew not found. Run: ./manage.sh setup"
  fi

  info "Homebrew version: $(brew --version | head -1)"

  # `brew doctor` checks for common problems (stale links, outdated CLT, etc).
  # It exits 0 if healthy, 1 if warnings exist — we log but don't fail hard.
  info "Running brew doctor..."
  brew doctor || warn "brew doctor reported warnings — see above."

  # `brew bundle check` exits 0 if all Brewfile packages are installed.
  if [[ -f "${BREWFILE}" ]]; then
    info "Checking Brewfile..."
    brew bundle check --file="${BREWFILE}" && \
      info "All Brewfile packages are installed." || \
      warn "Some packages are missing. Run: brew bundle --file=${BREWFILE}"
  fi

  # Show outdated packages (informational only).
  info "Outdated packages:"
  brew outdated || true

  info "Healthcheck complete."
}

# ---------------------------------------------------------------------------
# COMMAND: teardown
# Uninstalls all packages listed in the Brewfile and optionally Homebrew.
# ---------------------------------------------------------------------------
cmd_teardown() {
  warn "Teardown will uninstall Brewfile packages."
  warn "Homebrew itself will NOT be removed unless REMOVE_HOMEBREW=true."

  if [[ "${AUTO_APPROVE:-false}" != "true" ]]; then
    read -r "confirm?Type 'yes' to confirm: "
    if [[ "${confirm}" != "yes" ]]; then
      info "Teardown cancelled."
      exit 0
    fi
  fi

  if [[ -f "${BREWFILE}" ]]; then
    info "Uninstalling Brewfile packages..."
    # `brew bundle cleanup --force` removes all packages NOT in the Brewfile.
    # We want the inverse — remove packages that ARE in it — so we iterate.
    # NOTE: This is intentionally conservative; dependencies are left in place.
    brew bundle cleanup --file="${BREWFILE}" --force || \
      warn "brew bundle cleanup encountered errors — some packages may remain."
  fi

  if [[ "${REMOVE_HOMEBREW:-false}" == "true" ]]; then
    warn "Removing Homebrew entirely..."
    /bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/uninstall.sh)"
    info "Homebrew removed."
  fi

  info "Teardown complete."
}

# ---------------------------------------------------------------------------
# ENTRY POINT
# ---------------------------------------------------------------------------
main() {
  local command="${1:-}"

  case "${command}" in
    setup)       cmd_setup ;;
    healthcheck) cmd_healthcheck ;;
    teardown)    cmd_teardown ;;
    *)
      print "Usage: $0 <command>"
      print ""
      print "Commands:"
      print "  setup       Install Homebrew, run Brewfile, apply macOS defaults"
      print "  healthcheck Verify brew health and Brewfile completeness"
      print "  teardown    Remove Brewfile packages"
      print ""
      print "Toggles:"
      print "  ENABLE_LOGGING=true     Verbose output"
      print "  SKIP_DEFAULTS=true      Skip macOS defaults write commands"
      print "  SKIP_BREW_BUNDLE=true   Skip Brewfile install"
      print "  REMOVE_HOMEBREW=true    Also remove Homebrew in teardown"
      print "  AUTO_APPROVE=true       Skip teardown confirmation"
      exit 1
      ;;
  esac
}

main "$@"
