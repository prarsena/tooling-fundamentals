#!/usr/bin/env zsh
# =============================================================================
# salt/scripts/manage.sh
# Lifecycle manager for SaltStack on macOS.
# Covers: masterless salt-call, salt-ssh agentless execution, and state linting.
#
# Usage:
#   ./manage.sh <command>
#   DRY_RUN=true ./manage.sh apply
#
# Commands: setup | apply | healthcheck | teardown
# =============================================================================

set -euo pipefail

# ---------------------------------------------------------------------------
# ENVIRONMENT VARIABLE TOGGLES
# ---------------------------------------------------------------------------

ENABLE_LOGGING="${ENABLE_LOGGING:-false}"

# When true, run states in test=True mode (reports changes, makes none).
DRY_RUN="${DRY_RUN:-false}"

# The state to apply. 'highstate' applies everything in top.sls.
TARGET_STATE="${TARGET_STATE:-highstate}"

# salt-ssh roster file for agentless remote execution.
ROSTER_FILE="${ROSTER_FILE:-${0:A:h:h}/supporting_files/roster}"

# Use salt-ssh instead of local salt-call.
USE_SALT_SSH="${USE_SALT_SSH:-false}"

# Target pattern for salt-ssh (glob matched against roster).
SALT_SSH_TARGET="${SALT_SSH_TARGET:-*}"

# ---------------------------------------------------------------------------
# macOS-SPECIFIC PATHS
# salt-call writes cache, PKI keys, and running state to /var/cache/salt/
# and /etc/salt/ by default — both require root on macOS. We override with
# user-writable paths under ~/Library/ using the minion config file.
#
# IMPORTANT: salt-call --local must be run with the --config-dir flag
# pointing to our supporting_files/ directory, NOT /etc/salt/. This way
# no system-level files are touched without sudo.
# ---------------------------------------------------------------------------
SALT_CACHE_DIR="${HOME}/Library/Caches/salt"
SALT_LOG_DIR="${HOME}/Library/Logs/salt"
SALT_CONFIG_DIR="${0:A:h:h}/supporting_files"

SCRIPT_DIR="${0:A:h}"
ROOT_DIR="${SCRIPT_DIR:h}"

# ---------------------------------------------------------------------------
# HELPERS
# ---------------------------------------------------------------------------

log()   { [[ "${ENABLE_LOGGING}" == "true" ]] && print -P "%F{cyan}[$(date '+%H:%M:%S')]%f $*" || true; }
info()  { print -P "%F{green}[INFO]%f $*"; }
warn()  { print -P "%F{yellow}[WARN]%f $*"; }
error() { print -P "%F{red}[ERROR]%f $*" >&2; exit 1; }

require() {
  if ! command -v "$1" &>/dev/null; then
    error "'$1' is not installed. Run: brew install salt"
  fi
}

# ---------------------------------------------------------------------------
# COMMAND: setup
# Create macOS-appropriate directories and configure the minion config file.
# ---------------------------------------------------------------------------
cmd_setup() {
  info "Running Salt setup..."
  require salt-call

  # ---- Create user-writable Salt directory structure ----
  # On macOS, /var/cache/salt/ and /var/log/salt/ require sudo to create.
  # We redirect all Salt output to ~/Library/ which is per-user and writable.
  log "Creating Salt cache dir: ${SALT_CACHE_DIR}"
  mkdir -p "${SALT_CACHE_DIR}/minion"

  log "Creating Salt log dir: ${SALT_LOG_DIR}"
  mkdir -p "${SALT_LOG_DIR}"

  # ---- Validate minion config ----
  # The minion config in supporting_files/ overrides the default /etc/salt/minion
  # paths. Verify it exists and contains the correct cachedir setting.
  local minion_cfg="${SALT_CONFIG_DIR}/minion"
  if [[ ! -f "${minion_cfg}" ]]; then
    error "Minion config not found at ${minion_cfg}. Create it from the supporting_files template."
  fi

  log "Minion config: ${minion_cfg}"

  # ---- Set file_roots so salt-call can find our states ----
  # salt-call --local reads states from the path set in file_roots in minion config.
  # Our supporting_files/minion config sets this to the states/ directory.
  info "Checking file_roots configuration..."
  if grep -q "file_roots" "${minion_cfg}"; then
    info "file_roots is configured in minion config."
  else
    warn "file_roots not found in ${minion_cfg}. Salt cannot find states — check configuration."
  fi

  # ---- Verify salt-ssh availability ----
  if command -v salt-ssh &>/dev/null; then
    info "salt-ssh: available (agentless remote execution enabled)"
  else
    warn "salt-ssh not found — remote agentless execution unavailable."
  fi

  info "Salt version: $(salt-call --version)"
  info "Setup complete."
  info "Run: ./manage.sh apply  (or USE_SALT_SSH=true ./manage.sh apply for remote)"
}

# ---------------------------------------------------------------------------
# COMMAND: apply
# Apply Salt states. Supports local (salt-call --local) and agentless
# remote execution (salt-ssh) via the USE_SALT_SSH toggle.
# ---------------------------------------------------------------------------
cmd_apply() {
  info "Running Salt apply..."

  if [[ "${USE_SALT_SSH}" == "true" ]]; then
    # ---- Remote execution via salt-ssh ----
    # salt-ssh is fully agentless — no minion daemon required on targets.
    # It pushes a thin Salt shim over SSH, executes, then cleans up.
    require salt-ssh

    if [[ ! -f "${ROSTER_FILE}" ]]; then
      error "Roster file not found: ${ROSTER_FILE}"
    fi

    info "Applying via salt-ssh to targets: ${SALT_SSH_TARGET}"

    local args=()
    args+=("${SALT_SSH_TARGET}")
    args+=(--roster-file "${ROSTER_FILE}")

    # -i: accept new host keys automatically (dev only — remove in production).
    # In macOS, SSH host key checking uses ~/.ssh/known_hosts by default; -i
    # bypasses this. Only use for trusted local dev VMs.
    args+=(-i)

    if [[ "${TARGET_STATE}" == "highstate" ]]; then
      args+=(state.highstate)
    else
      args+=(state.apply "${TARGET_STATE}")
    fi

    if [[ "${DRY_RUN}" == "true" ]]; then
      warn "DRY_RUN=true — running with test=True (no changes will be applied)."
      args+=(test=True)
    fi

    log "Running: salt-ssh ${args[*]}"
    salt-ssh "${args[@]}"

  else
    # ---- Local execution via salt-call --local ----
    # salt-call --local starts an in-process Salt minion with no master.
    # It reads states from the file_roots path defined in the minion config.
    require salt-call

    local args=()

    # --local: run without connecting to a Salt Master.
    args+=(--local)

    # --config-dir: use our project-level minion config instead of /etc/salt/.
    # This avoids needing sudo and keeps all Salt data in user-writable paths.
    args+=(--config-dir "${SALT_CONFIG_DIR}")

    # --log-file: write log to ~/Library/Logs/salt/ (macOS-standard log location).
    args+=(--log-file "${SALT_LOG_DIR}/minion")

    if [[ "${TARGET_STATE}" == "highstate" ]]; then
      args+=(state.highstate)
    else
      args+=(state.apply "${TARGET_STATE}")
    fi

    # test=True: report-only mode. Salt evaluates all states and shows what
    # would change (green additions, red removals) without converging.
    if [[ "${DRY_RUN}" == "true" ]]; then
      warn "DRY_RUN=true — running with test=True (no changes will be applied)."
      args+=(test=True)
    fi

    log "Running: salt-call ${args[*]}"
    salt-call "${args[@]}"
  fi
}

# ---------------------------------------------------------------------------
# COMMAND: healthcheck
# Check Salt installation, display grains (node facts), and verify states.
# ---------------------------------------------------------------------------
cmd_healthcheck() {
  info "Running Salt healthcheck..."
  require salt-call

  info "Salt version:"
  salt-call --version

  info "System grains (node facts):"
  # `grains.items` returns all gathered facts about the local system
  # (OS, CPU arch, memory, network interfaces, etc.).
  # Use `grains.get <key>` to retrieve a single fact.
  salt-call --local --config-dir "${SALT_CONFIG_DIR}" grains.items \
    --log-level quiet || warn "Could not retrieve grains."

  info "Checking that states are parseable (test=True on highstate)..."
  # Running highstate with test=True validates all state files for syntax and
  # module availability without making any changes.
  salt-call --local \
    --config-dir "${SALT_CONFIG_DIR}" \
    --log-file "${SALT_LOG_DIR}/minion" \
    state.highstate test=True \
    --state-output=changes \
    --log-level warning || warn "State check reported issues — review above."

  info "Healthcheck complete."
}

# ---------------------------------------------------------------------------
# COMMAND: teardown
# Remove Salt cache, PKI state, and log files.
# Salt itself is NOT removed (managed by Homebrew).
# ---------------------------------------------------------------------------
cmd_teardown() {
  warn "Teardown will remove Salt cache (${SALT_CACHE_DIR}) and logs (${SALT_LOG_DIR})."

  if [[ "${AUTO_APPROVE:-false}" != "true" ]]; then
    read -r "confirm?Type 'yes' to confirm: "
    if [[ "${confirm}" != "yes" ]]; then
      info "Teardown cancelled."
      exit 0
    fi
  fi

  info "Removing Salt cache..."
  rm -rf "${SALT_CACHE_DIR}"

  info "Removing Salt logs..."
  rm -rf "${SALT_LOG_DIR}"

  # Remove the salt-ssh thin tarball cache if it exists.
  # salt-ssh unpacks a Python bundle on each target — it caches the tarball
  # locally at ~/.salt-ssh/ to avoid re-downloading it every run.
  if [[ -d "${HOME}/.salt-ssh" ]]; then
    info "Removing salt-ssh thin cache..."
    rm -rf "${HOME}/.salt-ssh"
  fi

  info "Teardown complete."
  info "To remove Salt: brew uninstall salt"
}

# ---------------------------------------------------------------------------
# ENTRY POINT
# ---------------------------------------------------------------------------
main() {
  local command="${1:-}"

  case "${command}" in
    setup)       cmd_setup ;;
    apply)       cmd_apply ;;
    healthcheck) cmd_healthcheck ;;
    teardown)    cmd_teardown ;;
    *)
      print "Usage: $0 <command>"
      print ""
      print "Commands:"
      print "  setup       Prepare macOS directories, validate minion config"
      print "  apply       Apply states (local or via salt-ssh)"
      print "  healthcheck Show grains, validate state files"
      print "  teardown    Remove cache and log files"
      print ""
      print "Toggles:"
      print "  ENABLE_LOGGING=true            Verbose output"
      print "  DRY_RUN=true                   Apply with test=True (no changes)"
      print "  TARGET_STATE=<state>           State to apply (default: highstate)"
      print "  USE_SALT_SSH=true              Use salt-ssh instead of salt-call"
      print "  ROSTER_FILE=<path>             salt-ssh roster file"
      print "  SALT_SSH_TARGET='<pattern>'    salt-ssh target glob (default: *)"
      print "  AUTO_APPROVE=true              Skip teardown confirmation"
      exit 1
      ;;
  esac
}

main "$@"
