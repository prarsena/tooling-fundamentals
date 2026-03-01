#!/usr/bin/env zsh
# =============================================================================
# ansible/scripts/manage.sh
# Lifecycle manager for Ansible on macOS.
# Covers: installation verification, inventory setup, playbook execution,
# Ansible Vault, Galaxy roles, and ansible-lint.
#
# Usage:
#   ./manage.sh <command>
#   ENABLE_LOGGING=true DRY_RUN=true ./manage.sh apply
#
# Commands: setup | apply | healthcheck | teardown
# =============================================================================

set -euo pipefail

# ---------------------------------------------------------------------------
# ENVIRONMENT VARIABLE TOGGLES
# ---------------------------------------------------------------------------

ENABLE_LOGGING="${ENABLE_LOGGING:-false}"

# When true, run playbooks in --check mode (no changes applied to targets).
DRY_RUN="${DRY_RUN:-false}"

# When true, add --diff to show line-level changes in managed files.
SHOW_DIFF="${SHOW_DIFF:-false}"

# Inventory file to use. Defaults to the starter inventory in this repo.
INVENTORY="${INVENTORY:-${0:A:h:h}/supporting_files/inventory.ini}"

# Top-level playbook to run with the 'apply' command.
PLAYBOOK="${PLAYBOOK:-${0:A:h:h}/supporting_files/site.yml}"

# Limit playbook run to a specific host or group pattern.
LIMIT="${LIMIT:-}"

# Tags to run (comma-separated). Empty = run all tasks.
TAGS="${TAGS:-}"

# Path to an Ansible Vault password file. Avoids interactive prompts in CI.
VAULT_PASSWORD_FILE="${VAULT_PASSWORD_FILE:-}"

# Number of parallel forks (concurrent SSH connections).
# macOS has a default open-file limit of 256; keep forks below that.
FORKS="${FORKS:-10}"

# ---------------------------------------------------------------------------
# macOS-SPECIFIC PATHS
# Ansible on macOS (via Homebrew) stores its SSH ControlMaster sockets in
# /tmp/ rather than ~/.ansible/cp/. This avoids the 104-byte Unix socket
# path limit that can be hit when $HOME is a long path (common on macOS).
# The ansible.cfg in supporting_files/ sets this path accordingly.
# ---------------------------------------------------------------------------
ANSIBLE_HOME="${HOME}/Library/Application Support/ansible"

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
    error "'$1' is not installed. Run: brew install $1"
  fi
}

# ---------------------------------------------------------------------------
# COMMAND: setup
# Install tools, configure environment, install Galaxy roles.
# ---------------------------------------------------------------------------
cmd_setup() {
  info "Running Ansible setup..."
  require ansible
  require ansible-playbook
  require ansible-lint

  # ---- Create macOS-appropriate working directories ----
  # ~/Library/Application Support/ is the correct per-user data location on
  # macOS. On Linux, Ansible uses ~/.ansible/ instead.
  log "Creating Ansible home: ${ANSIBLE_HOME}"
  mkdir -p "${ANSIBLE_HOME}/roles"
  mkdir -p "${ANSIBLE_HOME}/collections"

  # ---- Configure ANSIBLE_HOME environment variable ----
  # This tells Ansible where to look for roles and collections installed via
  # ansible-galaxy. We set it here and persist it to ~/.zshrc.
  export ANSIBLE_HOME

  local zshrc_line="export ANSIBLE_HOME=\"\${HOME}/Library/Application Support/ansible\""
  if ! grep -qF "ANSIBLE_HOME" "${HOME}/.zshrc" 2>/dev/null; then
    print "${zshrc_line}" >> "${HOME}/.zshrc"
    log "Added ANSIBLE_HOME to ~/.zshrc"
  fi

  # ---- Install Galaxy requirements if file exists ----
  local requirements="${ROOT_DIR}/supporting_files/requirements.yml"
  if [[ -f "${requirements}" ]]; then
    info "Installing Galaxy roles and collections..."
    # -p installs to our macOS-standard roles path instead of /etc/ansible/roles
    ansible-galaxy install -r "${requirements}" -p "${ANSIBLE_HOME}/roles"
    ansible-galaxy collection install -r "${requirements}" -p "${ANSIBLE_HOME}/collections"
    info "Galaxy requirements installed."
  else
    warn "No requirements.yml found — skipping Galaxy install."
  fi

  info "Setup complete."
  info "Edit ${ROOT_DIR}/supporting_files/inventory.ini to add your hosts."
  info "Then run: ./manage.sh apply"
}

# ---------------------------------------------------------------------------
# COMMAND: apply
# Run the site playbook against the configured inventory.
# ---------------------------------------------------------------------------
cmd_apply() {
  info "Running Ansible apply..."
  require ansible-playbook

  if [[ ! -f "${PLAYBOOK}" ]]; then
    error "Playbook not found: ${PLAYBOOK}"
  fi

  # Build argument array dynamically — only add flags when their toggle is set.
  local args=()
  args+=(-i "${INVENTORY}")
  args+=(-f "${FORKS}")    # Number of parallel forks

  # --check: dry-run mode — Ansible reports what would change without doing it.
  # NOTE: some modules do not support check mode and will be skipped.
  if [[ "${DRY_RUN}" == "true" ]]; then
    warn "DRY_RUN=true — running in --check mode. No changes will be made."
    args+=(--check)
  fi

  # --diff: show line-level before/after for file and template changes.
  if [[ "${SHOW_DIFF}" == "true" ]]; then
    args+=(--diff)
  fi

  # --limit: restrict run to a subset of hosts or groups.
  if [[ -n "${LIMIT}" ]]; then
    args+=(--limit "${LIMIT}")
    log "Limiting to: ${LIMIT}"
  fi

  # --tags: only run tasks with matching tags.
  if [[ -n "${TAGS}" ]]; then
    args+=(--tags "${TAGS}")
    log "Tags: ${TAGS}"
  fi

  # --vault-password-file: read vault password from a file instead of prompting.
  # Useful in CI; on a developer Mac you may prefer --ask-vault-pass instead.
  if [[ -n "${VAULT_PASSWORD_FILE}" ]]; then
    args+=(--vault-password-file "${VAULT_PASSWORD_FILE}")
    log "Using vault password file: ${VAULT_PASSWORD_FILE}"
  fi

  log "Running: ansible-playbook ${PLAYBOOK} ${args[*]}"
  ansible-playbook "${PLAYBOOK}" "${args[@]}"
}

# ---------------------------------------------------------------------------
# COMMAND: healthcheck
# Ping all hosts, show Ansible version info, and lint playbooks.
# ---------------------------------------------------------------------------
cmd_healthcheck() {
  info "Running Ansible healthcheck..."
  require ansible
  require ansible-lint

  info "Ansible version:"
  # `ansible --version` also prints the Python interpreter path and config file
  # location — useful diagnostic information for macOS environment issues.
  ansible --version

  info "Pinging all hosts in inventory..."
  # `ansible all -m ping` uses the `ping` module which tests SSH connectivity
  # and Python availability on each target — it is NOT an ICMP ping.
  ansible all -i "${INVENTORY}" -m ping || \
    warn "Some hosts unreachable — check inventory and SSH keys."

  info "Linting playbooks..."
  # ansible-lint checks for deprecations, best-practice violations, and
  # common mistakes. Configuration is read from .ansible-lint if present.
  ansible-lint "${PLAYBOOK}" || warn "Lint warnings found — review above."

  info "Healthcheck complete."
}

# ---------------------------------------------------------------------------
# COMMAND: teardown
# Remove Galaxy roles, collections, and cached facts.
# Does NOT remove Ansible itself (managed by Homebrew).
# ---------------------------------------------------------------------------
cmd_teardown() {
  warn "Teardown will remove installed Galaxy roles, collections, and fact cache."

  if [[ "${AUTO_APPROVE:-false}" != "true" ]]; then
    read -r "confirm?Type 'yes' to confirm: "
    if [[ "${confirm}" != "yes" ]]; then
      info "Teardown cancelled."
      exit 0
    fi
  fi

  info "Removing Galaxy roles and collections from ${ANSIBLE_HOME}..."
  rm -rf "${ANSIBLE_HOME}/roles"
  rm -rf "${ANSIBLE_HOME}/collections"

  # Remove the fact cache. On macOS, Ansible stores cached facts in
  # ~/Library/Application Support/ansible/facts/ when `fact_caching` is
  # enabled in ansible.cfg. Clear it to force fresh fact gathering.
  rm -rf "${ANSIBLE_HOME}/facts"

  info "Teardown complete. Ansible binary was NOT removed (use: brew uninstall ansible)."
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
      print "  setup       Install Galaxy requirements, configure ANSIBLE_HOME"
      print "  apply       Run site.yml playbook against inventory"
      print "  healthcheck Ping hosts, show version, lint playbooks"
      print "  teardown    Remove Galaxy roles and fact cache"
      print ""
      print "Toggles:"
      print "  ENABLE_LOGGING=true               Verbose output"
      print "  DRY_RUN=true                      Run in --check mode (no changes)"
      print "  SHOW_DIFF=true                    Show file diffs (--diff)"
      print "  INVENTORY=<path>                  Inventory file path"
      print "  PLAYBOOK=<path>                   Playbook file path"
      print "  LIMIT=<host/group>                Restrict to subset of hosts"
      print "  TAGS=<tag1,tag2>                  Run only tagged tasks"
      print "  VAULT_PASSWORD_FILE=<path>        Vault password file"
      print "  FORKS=<n>                         Parallel connections (default: 10)"
      print "  AUTO_APPROVE=true                 Skip teardown confirmation"
      exit 1
      ;;
  esac
}

main "$@"
