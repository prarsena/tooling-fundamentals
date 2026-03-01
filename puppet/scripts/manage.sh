#!/usr/bin/env zsh
# =============================================================================
# puppet/scripts/manage.sh
# Lifecycle manager for Puppet Bolt on macOS.
# Covers: agentless manifest application, Bolt plans, PDK unit tests, linting.
#
# Usage:
#   ./manage.sh <command>
#   BOLT_TARGETS=localhost DRY_RUN=true ./manage.sh apply
#
# Commands: setup | apply | healthcheck | teardown
# =============================================================================

set -euo pipefail

# ---------------------------------------------------------------------------
# ENVIRONMENT VARIABLE TOGGLES
# ---------------------------------------------------------------------------

ENABLE_LOGGING="${ENABLE_LOGGING:-false}"

# When true, run Bolt apply with --noop (reports changes, makes none).
DRY_RUN="${DRY_RUN:-false}"

# Comma-separated list of Bolt targets. Use 'localhost' for local testing.
# For SSH targets: 'ssh://user@host:port' or names from bolt-project.yaml.
BOLT_TARGETS="${BOLT_TARGETS:-localhost}"

# The manifest to apply (relative to ROOT_DIR).
MANIFEST="${MANIFEST:-modules/baseline/manifests/init.pp}"

# SSH user for remote targets (ignored when BOLT_TARGETS=localhost).
BOLT_USER="${BOLT_USER:-${USER}}"

# SSH private key for remote targets.
BOLT_KEY="${BOLT_KEY:-${HOME}/.ssh/id_ed25519}"

# ---------------------------------------------------------------------------
# macOS-SPECIFIC PATHS
# Puppet Bolt installs to /opt/puppetlabs/bolt/ via Cask.
# PDK installs to /opt/puppetlabs/pdk/.
# Bolt's user-level config and module cache live in ~/.puppetlabs/bolt/ on
# Linux but on macOS the Cask installer redirects to the same location.
# We honour this and do NOT use /etc/puppetlabs/ which requires root.
# ---------------------------------------------------------------------------
BOLT_BIN="/opt/puppetlabs/bolt/bin/bolt"
PDK_BIN="/opt/puppetlabs/pdk/bin/pdk"
BOLT_PROJECT_CONFIG_DIR="${HOME}/.puppetlabs/bolt"

SCRIPT_DIR="${0:A:h}"
ROOT_DIR="${SCRIPT_DIR:h}"

# ---------------------------------------------------------------------------
# HELPERS
# ---------------------------------------------------------------------------

log()   { [[ "${ENABLE_LOGGING}" == "true" ]] && print -P "%F{cyan}[$(date '+%H:%M:%S')]%f $*" || true; }
info()  { print -P "%F{green}[INFO]%f $*"; }
warn()  { print -P "%F{yellow}[WARN]%f $*"; }
error() { print -P "%F{red}[ERROR]%f $*" >&2; exit 1; }

# ensure_bolt_in_path
# /opt/puppetlabs/bolt/bin is not added to PATH by the Cask installer
# for the current shell session. We add it here for the current process.
ensure_bolt_in_path() {
  local bolt_bin_dir="/opt/puppetlabs/bolt/bin"
  if [[ ":${PATH}:" != *":${bolt_bin_dir}:"* ]]; then
    export PATH="${bolt_bin_dir}:${PATH}"
    log "Prepended ${bolt_bin_dir} to PATH"
  fi
}

require_bolt() {
  if [[ ! -x "${BOLT_BIN}" ]]; then
    error "Puppet Bolt not found.\nInstall with: brew install --cask puppet-bolt"
  fi
}

# build_bolt_target_args
# Builds the --targets and SSH flags for a Bolt invocation.
build_bolt_target_args() {
  local args=()
  args+=(--targets "${BOLT_TARGETS}")

  # Only add SSH flags for non-localhost targets.
  if [[ "${BOLT_TARGETS}" != "localhost" ]]; then
    args+=(--user "${BOLT_USER}")
    if [[ -f "${BOLT_KEY}" ]]; then
      args+=(--private-key "${BOLT_KEY}")
    fi
    # --no-host-key-check: skip SSH host key verification.
    # ONLY appropriate for local dev VMs — never use in production.
    args+=(--no-host-key-check)
  fi

  echo "${args[@]}"
}

# ---------------------------------------------------------------------------
# COMMAND: setup
# Verify installations, install Forge modules declared in bolt-project.yaml.
# ---------------------------------------------------------------------------
cmd_setup() {
  info "Running Puppet Bolt setup..."
  ensure_bolt_in_path
  require_bolt

  info "Bolt version: $(${BOLT_BIN} --version)"

  # ---- Create user-level Bolt config dir ----
  # Bolt reads global config from ~/.puppetlabs/bolt/bolt-defaults.yaml.
  # This dir is separate from the project config (bolt-project.yaml).
  log "Creating Bolt config dir: ${BOLT_PROJECT_CONFIG_DIR}"
  mkdir -p "${BOLT_PROJECT_CONFIG_DIR}"

  # ---- Install Forge modules from bolt-project.yaml ----
  # `bolt module install` reads the 'modules' key of bolt-project.yaml and
  # resolves dependencies via the Puppet Forge. It writes them to .modules/.
  local project_config="${ROOT_DIR}/supporting_files/bolt-project.yaml"
  if [[ -f "${project_config}" ]]; then
    info "Installing Bolt modules from bolt-project.yaml..."
    cd "${ROOT_DIR}"
    "${BOLT_BIN}" module install --project "${ROOT_DIR}/supporting_files"
    info "Modules installed."
  else
    warn "bolt-project.yaml not found — skipping module install."
  fi

  info "Setup complete."
  info "Edit ${ROOT_DIR}/modules/baseline/manifests/init.pp, then:"
  info "  BOLT_TARGETS=localhost ./manage.sh apply"
}

# ---------------------------------------------------------------------------
# COMMAND: apply
# Apply a Puppet manifest to target nodes via Bolt (agentless).
# ---------------------------------------------------------------------------
cmd_apply() {
  info "Running Puppet Bolt apply..."
  ensure_bolt_in_path
  require_bolt

  local manifest="${ROOT_DIR}/${MANIFEST}"
  if [[ ! -f "${manifest}" ]]; then
    error "Manifest not found: ${manifest}"
  fi

  local target_args
  target_args=($(build_bolt_target_args))

  local args=()
  args+=(apply "${manifest}")
  args+=("${target_args[@]}")
  args+=(--modulepath "${ROOT_DIR}/modules")
  args+=(--project "${ROOT_DIR}/supporting_files")

  # --noop: apply in no-operation mode — Puppet reports what would change
  # (adds, modifications, removals) without executing any resource converge.
  if [[ "${DRY_RUN}" == "true" ]]; then
    warn "DRY_RUN=true — running with --noop. No changes will be applied."
    args+=(--noop)
  fi

  log "Running: bolt ${args[*]}"
  "${BOLT_BIN}" "${args[@]}"
}

# ---------------------------------------------------------------------------
# COMMAND: healthcheck
# Verify Bolt, PDK, and puppet-lint. Run PDK unit tests if available.
# ---------------------------------------------------------------------------
cmd_healthcheck() {
  info "Running Puppet healthcheck..."
  ensure_bolt_in_path
  require_bolt

  info "Bolt version: $(${BOLT_BIN} --version)"

  # ---- Run built-in Bolt facts task ----
  # `bolt task run facts` collects OS/network facts from the target.
  # On localhost this runs locally and verifies Bolt's Ruby environment.
  info "Collecting facts from target: ${BOLT_TARGETS}..."
  local target_args
  target_args=($(build_bolt_target_args))
  "${BOLT_BIN}" task run facts "${target_args[@]}" || \
    warn "Facts task failed — check target connectivity."

  # ---- puppet-lint ----
  if command -v puppet-lint &>/dev/null; then
    info "Running puppet-lint on all manifests..."
    # --no-140chars-check: disable the 140-character line-length rule
    # (overly strict for modern editors).
    find "${ROOT_DIR}/modules" -name "*.pp" -exec puppet-lint \
      --no-140chars-check \
      --fail-on-warnings \
      {} \; || warn "puppet-lint reported issues."
  else
    warn "puppet-lint not installed. Install with: gem install puppet-lint"
  fi

  # ---- PDK unit tests ----
  if [[ -x "${PDK_BIN}" ]]; then
    info "Running PDK unit tests..."
    # PDK runs RSpec tests in spec/classes/ — generated by `pdk new module`.
    # We iterate over each module directory.
    for mod_dir in "${ROOT_DIR}/modules"/*/; do
      if [[ -f "${mod_dir}/metadata.json" ]]; then
        info "  Testing module: ${mod_dir:t}"
        cd "${mod_dir}"
        "${PDK_BIN}" test unit --parallel || warn "  Unit tests failed for ${mod_dir:t}"
        cd "${ROOT_DIR}"
      fi
    done
  else
    warn "PDK not installed. Install with: brew install --cask pdk"
  fi

  info "Healthcheck complete."
}

# ---------------------------------------------------------------------------
# COMMAND: teardown
# Remove Bolt module cache and temporary files.
# Bolt and PDK themselves are NOT removed (managed by Homebrew Cask).
# ---------------------------------------------------------------------------
cmd_teardown() {
  warn "Teardown will remove Bolt's module cache (.modules/) and temp files."

  if [[ "${AUTO_APPROVE:-false}" != "true" ]]; then
    read -r "confirm?Type 'yes' to confirm: "
    if [[ "${confirm}" != "yes" ]]; then
      info "Teardown cancelled."
      exit 0
    fi
  fi

  # Remove the Bolt module cache (installed Forge modules).
  rm -rf "${ROOT_DIR}/supporting_files/.modules"
  rm -rf "${ROOT_DIR}/supporting_files/.resource_types"

  info "Teardown complete."
  info "To remove Bolt:  brew uninstall --cask puppet-bolt"
  info "To remove PDK:   brew uninstall --cask pdk"
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
      print "  setup       Install Bolt modules, prepare environment"
      print "  apply       Apply manifest to targets via Bolt"
      print "  healthcheck Collect facts, lint manifests, run PDK tests"
      print "  teardown    Remove Bolt module cache"
      print ""
      print "Toggles:"
      print "  ENABLE_LOGGING=true            Verbose output"
      print "  DRY_RUN=true                   Run with --noop (no changes)"
      print "  BOLT_TARGETS=<target>          Bolt target(s) (default: localhost)"
      print "  MANIFEST=<path>                Manifest to apply"
      print "  BOLT_USER=<user>               SSH user for remote targets"
      print "  BOLT_KEY=<path>                SSH key for remote targets"
      print "  AUTO_APPROVE=true              Skip teardown confirmation"
      exit 1
      ;;
  esac
}

main "$@"
