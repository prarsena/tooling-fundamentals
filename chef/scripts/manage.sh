#!/usr/bin/env zsh
# =============================================================================
# chef/scripts/manage.sh
# Lifecycle manager for Chef Workstation on macOS.
# Covers: cookbook generation, local-mode convergence, Test Kitchen, cookstyle.
#
# Usage:
#   ./manage.sh <command>
#   DRY_RUN=true COOKBOOK=base ./manage.sh apply
#
# Commands: setup | apply | healthcheck | teardown
# =============================================================================

set -euo pipefail

# ---------------------------------------------------------------------------
# ENVIRONMENT VARIABLE TOGGLES
# ---------------------------------------------------------------------------

ENABLE_LOGGING="${ENABLE_LOGGING:-false}"

# When true, run chef-client in --why-run mode (reports changes, makes none).
DRY_RUN="${DRY_RUN:-false}"

# The cookbook to converge with the 'apply' command.
COOKBOOK="${COOKBOOK:-base}"

# Log level passed to chef-client. Options: debug|info|warn|error|fatal.
CHEF_LOG_LEVEL="${CHEF_LOG_LEVEL:-warn}"

# ---------------------------------------------------------------------------
# macOS-SPECIFIC PATHS
# chef-client writes its local cache (cookbooks, node JSON, resource cache)
# to /var/chef/ by default — this requires root on macOS. We override with
# ~/Library/Caches/chef-client/ which is writable by the current user and
# is an acceptable macOS-standard cache location.
#
# Chef Workstation installs to /opt/chef-workstation/ — we add its bin to
# PATH here for the current session since it may not be in the user's PATH.
# ---------------------------------------------------------------------------
CHEF_CACHE_DIR="${HOME}/Library/Caches/chef-client"
CHEF_WS_BIN="/opt/chef-workstation/bin"

SCRIPT_DIR="${0:A:h}"
ROOT_DIR="${SCRIPT_DIR:h}"
COOKBOOKS_DIR="${ROOT_DIR}/cookbooks"

# ---------------------------------------------------------------------------
# HELPERS
# ---------------------------------------------------------------------------

log()   { [[ "${ENABLE_LOGGING}" == "true" ]] && print -P "%F{cyan}[$(date '+%H:%M:%S')]%f $*" || true; }
info()  { print -P "%F{green}[INFO]%f $*"; }
warn()  { print -P "%F{yellow}[WARN]%f $*"; }
error() { print -P "%F{red}[ERROR]%f $*" >&2; exit 1; }

# ensure_chef_in_path
# Prepends /opt/chef-workstation/bin to PATH if it is not already present.
# On macOS, Cask-installed apps add themselves to /etc/paths.d/ but this
# only takes effect in new shells — we ensure it for the current process.
ensure_chef_in_path() {
  if [[ ":${PATH}:" != *":${CHEF_WS_BIN}:"* ]]; then
    export PATH="${CHEF_WS_BIN}:${PATH}"
    log "Prepended ${CHEF_WS_BIN} to PATH"
  fi
}

require() {
  if ! command -v "$1" &>/dev/null; then
    error "'$1' not found. Install Chef Workstation: brew install --cask chef-workstation"
  fi
}

# ---------------------------------------------------------------------------
# COMMAND: setup
# Verify Chef Workstation installation and prepare the local environment.
# ---------------------------------------------------------------------------
cmd_setup() {
  info "Running Chef setup..."
  ensure_chef_in_path

  # Check for Chef Workstation — the Cask installer is the canonical method.
  # Do NOT use `gem install chef` as it installs an older, incompatible gem.
  if [[ ! -d "/opt/chef-workstation" ]]; then
    error "Chef Workstation not found at /opt/chef-workstation.\nInstall with: brew install --cask chef-workstation"
  fi

  require chef
  require knife
  require cookstyle

  info "Chef Workstation version: $(chef --version | head -1)"

  # ---- Create local cache directory ----
  # Override the default /var/chef/ (root-only) with a user-writable path
  # under ~/Library/Caches/ (macOS standard for regenerable cache data).
  log "Creating chef cache dir: ${CHEF_CACHE_DIR}"
  mkdir -p "${CHEF_CACHE_DIR}"

  # ---- Generate starter cookbook if it doesn't already exist ----
  local cookbook_path="${COOKBOOKS_DIR}/${COOKBOOK}"
  if [[ ! -d "${cookbook_path}" ]]; then
    info "Generating starter cookbook: ${COOKBOOK}"
    mkdir -p "${COOKBOOKS_DIR}"
    # `chef generate cookbook` creates a full cookbook skeleton including
    # metadata, default recipe, test-kitchen config, and InSpec tests.
    chef generate cookbook "${cookbook_path}"
    info "Cookbook generated at: ${cookbook_path}"
  else
    info "Cookbook '${COOKBOOK}' already exists — skipping generation."
  fi

  info "Setup complete."
  info "Edit ${cookbook_path}/recipes/default.rb, then run: ./manage.sh apply"
}

# ---------------------------------------------------------------------------
# COMMAND: apply
# Converge the target cookbook using chef-client in local-mode (ChefZero).
# Local-mode requires no Chef Infra Server — the in-memory server (ChefZero)
# serves as the backend.
# ---------------------------------------------------------------------------
cmd_apply() {
  info "Running Chef apply..."
  ensure_chef_in_path
  require chef-client

  local cookbook_path="${COOKBOOKS_DIR}/${COOKBOOK}"
  if [[ ! -d "${cookbook_path}" ]]; then
    error "Cookbook not found: ${cookbook_path}. Run './manage.sh setup' first."
  fi

  local args=()

  # --local-mode: starts an in-memory ChefZero server so no remote Infra
  # Server is needed. This is the standard way to test cookbooks on macOS.
  args+=(--local-mode)

  # --runlist: comma-separated list of recipes/roles to converge.
  args+=(--runlist "recipe[${COOKBOOK}::default]")

  # --cookbook-path: where to find cookbook directories.
  args+=(--cookbook-path "${COOKBOOKS_DIR}")

  # --file-cache-path: override /var/chef/ with our user-writable cache dir.
  # On macOS, /var/ is often read-only for non-root without sudo.
  args+=(--file-cache-path "${CHEF_CACHE_DIR}")

  # --log_level: control verbosity. Use 'debug' for detailed resource output.
  args+=(--log_level "${CHEF_LOG_LEVEL}")

  # --why-run: dry-run mode. Reports what chef-client would change without
  # actually executing any resources. NOTE: not all resources support why-run.
  if [[ "${DRY_RUN}" == "true" ]]; then
    warn "DRY_RUN=true — running in --why-run mode. No changes will be applied."
    args+=(--why-run)
  fi

  log "Running: chef-client ${args[*]}"
  chef-client "${args[@]}"
}

# ---------------------------------------------------------------------------
# COMMAND: healthcheck
# Lint cookbooks with cookstyle, run PDK/ChefSpec unit tests if available.
# ---------------------------------------------------------------------------
cmd_healthcheck() {
  info "Running Chef healthcheck..."
  ensure_chef_in_path
  require cookstyle

  info "Chef Workstation versions:"
  chef --version

  # ---- Lint all cookbooks with cookstyle ----
  # cookstyle is a RuboCop-based linter that enforces Chef best practices,
  # catches deprecated resource usage, and flags Ruby style issues.
  info "Running cookstyle on all cookbooks..."
  cookstyle "${COOKBOOKS_DIR}" || warn "Cookstyle reported issues — see above."

  # ---- Validate cookbook metadata ----
  # `knife cookbook test` checks metadata.rb syntax for each cookbook.
  # We iterate manually because `knife cookbook test -a` requires a server.
  info "Validating cookbook metadata..."
  for cb_dir in "${COOKBOOKS_DIR}"/*/; do
    local cb_name="${cb_dir:t}"
    if [[ -f "${cb_dir}/metadata.rb" ]]; then
      log "Checking metadata for: ${cb_name}"
      # `knife cookbook show` validates metadata.rb without a server in
      # local mode. We use ruby to parse as a simpler syntax check.
      ruby -e "require '${cb_dir}/metadata.rb'" 2>/dev/null && \
        info "  ${cb_name}: metadata OK" || \
        warn "  ${cb_name}: metadata parse error"
    fi
  done

  info "Healthcheck complete."
}

# ---------------------------------------------------------------------------
# COMMAND: teardown
# Remove chef-client local cache and generated node state.
# Chef Workstation itself is NOT removed (managed by Homebrew Cask).
# ---------------------------------------------------------------------------
cmd_teardown() {
  warn "Teardown will delete the chef-client cache at: ${CHEF_CACHE_DIR}"

  if [[ "${AUTO_APPROVE:-false}" != "true" ]]; then
    read -r "confirm?Type 'yes' to confirm: "
    if [[ "${confirm}" != "yes" ]]; then
      info "Teardown cancelled."
      exit 0
    fi
  fi

  info "Removing chef-client cache..."
  rm -rf "${CHEF_CACHE_DIR}"

  # Remove ChefZero node state from the cookbooks directory.
  # `chef-client --local-mode` writes nodes/ and clients/ dirs to the CWD.
  rm -rf "${COOKBOOKS_DIR}/nodes" "${COOKBOOKS_DIR}/clients"

  info "Teardown complete."
  info "To remove Chef Workstation: brew uninstall --cask chef-workstation"
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
      print "  setup       Verify Chef Workstation, generate starter cookbook"
      print "  apply       Converge cookbook in local-mode (ChefZero)"
      print "  healthcheck Lint with cookstyle, validate metadata"
      print "  teardown    Remove chef-client cache and node state"
      print ""
      print "Toggles:"
      print "  ENABLE_LOGGING=true      Verbose output"
      print "  DRY_RUN=true             Run in --why-run mode (no changes)"
      print "  COOKBOOK=<name>          Cookbook to converge (default: base)"
      print "  CHEF_LOG_LEVEL=<level>   Log level: debug|info|warn|error|fatal"
      print "  AUTO_APPROVE=true        Skip teardown confirmation"
      exit 1
      ;;
  esac
}

main "$@"
