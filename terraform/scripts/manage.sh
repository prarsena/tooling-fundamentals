#!/usr/bin/env zsh
# =============================================================================
# terraform/scripts/manage.sh
# Lifecycle manager for Terraform / OpenTofu on macOS.
#
# Usage:
#   ./manage.sh <command>
#   ENABLE_LOGGING=true DRY_RUN=true ./manage.sh plan
#
# Commands: setup | plan | apply | healthcheck | teardown
# =============================================================================

set -euo pipefail

# ---------------------------------------------------------------------------
# ENVIRONMENT VARIABLE TOGGLES
# Override any of these before running to change behaviour without editing
# this file. Example: ENABLE_LOGGING=true ./manage.sh plan
# ---------------------------------------------------------------------------

# Print every terraform command and its output to stdout.
ENABLE_LOGGING="${ENABLE_LOGGING:-false}"

# When true, 'apply' runs 'plan' only — no real changes are made.
DRY_RUN="${DRY_RUN:-false}"

# Path to a .tfvars file to pass with -var-file. Leave empty to skip.
TF_VAR_FILE="${TF_VAR_FILE:-}"

# The Terraform/OpenTofu binary to use. Defaults to `tofu`; change to
# `terraform` if you are using the HashiCorp build.
TF_BIN="${TF_BIN:-tofu}"

# ---------------------------------------------------------------------------
# macOS-SPECIFIC PATHS
# On macOS, Homebrew places caches under ~/Library/Caches rather than
# ~/.cache (Linux). Setting TF_PLUGIN_CACHE_DIR avoids re-downloading
# provider binaries every time you run `init` in a new workspace.
# ---------------------------------------------------------------------------
TF_PLUGIN_CACHE_DIR="${TF_PLUGIN_CACHE_DIR:-${HOME}/Library/Caches/io.terraform/plugin-cache}"

# The root module directory (parent of this scripts/ folder).
SCRIPT_DIR="${0:A:h}"         # zsh idiom for the real path of this script's dir
ROOT_DIR="${SCRIPT_DIR:h}"     # one level up → terraform/

# ---------------------------------------------------------------------------
# HELPERS
# ---------------------------------------------------------------------------

# log <message>
# Print a timestamped message to stdout only when ENABLE_LOGGING=true.
log() {
  if [[ "${ENABLE_LOGGING}" == "true" ]]; then
    print -P "%F{cyan}[$(date '+%H:%M:%S')] %f$*"
  fi
}

# info <message>  — always printed
info() { print -P "%F{green}[INFO]%f $*"; }

# warn <message>  — always printed, in yellow
warn() { print -P "%F{yellow}[WARN]%f $*"; }

# error <message> — always printed, in red, then exits 1
error() { print -P "%F{red}[ERROR]%f $*" >&2; exit 1; }

# require <binary>
# Ensure a binary is available on PATH. Exits with a helpful message if not.
require() {
  if ! command -v "$1" &>/dev/null; then
    error "'$1' is not installed or not on PATH. Run: brew install $1"
  fi
}

# var_file_flag
# Returns the -var-file flag if TF_VAR_FILE is set, otherwise empty string.
var_file_flag() {
  if [[ -n "${TF_VAR_FILE}" ]]; then
    echo "-var-file=${TF_VAR_FILE}"
  fi
}

# ---------------------------------------------------------------------------
# COMMAND: setup
# Prepares the local environment and runs `tofu init`.
# ---------------------------------------------------------------------------
cmd_setup() {
  info "Running setup..."

  # Verify required binaries are present.
  require "${TF_BIN}"
  require jq     # used downstream for `tofu output -json | jq .`

  # Create the plugin cache directory if it does not exist.
  # mkdir -p is idempotent — safe to call on every setup.
  # NOTE: On macOS, ~/Library/Caches is managed by the OS and may be
  # purged under storage pressure; this is acceptable for a binary cache.
  log "Creating plugin cache dir: ${TF_PLUGIN_CACHE_DIR}"
  mkdir -p "${TF_PLUGIN_CACHE_DIR}"

  # Export the cache dir so Terraform picks it up automatically.
  export TF_PLUGIN_CACHE_DIR

  # Change into the root module directory so all `tofu` commands resolve
  # relative paths (modules/, .terraform.lock.hcl) correctly.
  cd "${ROOT_DIR}/supporting_files"

  info "Running: ${TF_BIN} init"
  log "Working directory: $(pwd)"

  # `tofu init` downloads providers, sets up backends, and initialises modules.
  # -upgrade refreshes providers to the latest allowed version per lock file.
  "${TF_BIN}" init -upgrade

  info "Setup complete. Run './manage.sh plan' to preview changes."
}

# ---------------------------------------------------------------------------
# COMMAND: plan
# Generates an execution plan showing what Terraform will change.
# ---------------------------------------------------------------------------
cmd_plan() {
  info "Running plan..."
  require "${TF_BIN}"

  export TF_PLUGIN_CACHE_DIR
  cd "${ROOT_DIR}/supporting_files"

  # Build the argument list dynamically so flags are only added when set.
  local args=()
  args+=(-out=tfplan)           # Save plan to file for use by `apply`.
  [[ -n "$(var_file_flag)" ]] && args+=("$(var_file_flag)")

  log "Args: ${args[*]}"

  # `tofu plan` compares desired state (*.tf) against current state (tfstate).
  # It never makes changes; it only reports what *would* change.
  "${TF_BIN}" plan "${args[@]}"
}

# ---------------------------------------------------------------------------
# COMMAND: apply
# Applies the saved plan (or generates a new one) to make real changes.
# When DRY_RUN=true this is identical to `plan` — no changes are made.
# ---------------------------------------------------------------------------
cmd_apply() {
  if [[ "${DRY_RUN}" == "true" ]]; then
    warn "DRY_RUN=true — running plan only, no changes will be applied."
    cmd_plan
    return
  fi

  info "Running apply..."
  require "${TF_BIN}"

  export TF_PLUGIN_CACHE_DIR
  cd "${ROOT_DIR}/supporting_files"

  local args=()
  # Use the saved plan file if it exists (produced by cmd_plan).
  # This ensures apply only executes what was reviewed in plan.
  if [[ -f tfplan ]]; then
    info "Using saved plan file: tfplan"
    args+=(tfplan)
  else
    warn "No saved plan found. Running plan+apply in one step."
    args+=(-auto-approve)
    [[ -n "$(var_file_flag)" ]] && args+=("$(var_file_flag)")
  fi

  "${TF_BIN}" apply "${args[@]}"
  info "Apply complete. Run './manage.sh healthcheck' to verify outputs."
}

# ---------------------------------------------------------------------------
# COMMAND: healthcheck
# Validates configuration and prints all output values.
# ---------------------------------------------------------------------------
cmd_healthcheck() {
  info "Running healthcheck..."
  require "${TF_BIN}"
  require jq

  export TF_PLUGIN_CACHE_DIR
  cd "${ROOT_DIR}/supporting_files"

  # `tofu validate` checks syntax and internal consistency of *.tf files.
  # It does NOT contact any provider APIs — safe to run offline.
  info "Validating configuration..."
  "${TF_BIN}" validate

  # `tofu fmt -check` exits non-zero if any files are not canonically formatted.
  # We use `|| true` so a formatting issue is a warning, not a hard failure.
  info "Checking formatting..."
  "${TF_BIN}" fmt -check -recursive . || warn "Some .tf files need formatting. Run: tofu fmt -recursive ."

  # Print all output values in human-readable form via jq.
  # `tofu output -json` emits a JSON object even when state is empty.
  info "Current outputs:"
  "${TF_BIN}" output -json | jq .

  info "Healthcheck passed."
}

# ---------------------------------------------------------------------------
# COMMAND: teardown
# Destroys ALL resources managed by this Terraform configuration.
# This is destructive and irreversible — a confirmation prompt is shown
# unless AUTO_APPROVE=true is set.
# ---------------------------------------------------------------------------
cmd_teardown() {
  warn "TEARDOWN will DESTROY all managed resources. This cannot be undone."

  if [[ "${AUTO_APPROVE:-false}" != "true" ]]; then
    # Use zsh's `read` built-in. Note: macOS ships with BSD `read` in sh,
    # but we are running under zsh so this is safe.
    read -r "confirm?Type 'yes' to confirm: "
    if [[ "${confirm}" != "yes" ]]; then
      info "Teardown cancelled."
      exit 0
    fi
  fi

  require "${TF_BIN}"
  export TF_PLUGIN_CACHE_DIR
  cd "${ROOT_DIR}/supporting_files"

  local args=(-destroy -auto-approve)
  [[ -n "$(var_file_flag)" ]] && args+=("$(var_file_flag)")

  "${TF_BIN}" apply "${args[@]}"
  info "Teardown complete."
}

# ---------------------------------------------------------------------------
# ENTRY POINT
# ---------------------------------------------------------------------------
main() {
  local command="${1:-}"

  case "${command}" in
    setup)       cmd_setup ;;
    plan)        cmd_plan ;;
    apply)       cmd_apply ;;
    healthcheck) cmd_healthcheck ;;
    teardown)    cmd_teardown ;;
    *)
      print "Usage: $0 <command>"
      print ""
      print "Commands:"
      print "  setup       Initialise Terraform and download providers"
      print "  plan        Preview changes (non-destructive)"
      print "  apply       Apply changes (use DRY_RUN=true to skip)"
      print "  healthcheck Validate config and print outputs"
      print "  teardown    Destroy all managed resources"
      print ""
      print "Toggles (set as environment variables):"
      print "  ENABLE_LOGGING=true   Verbose command output"
      print "  DRY_RUN=true          Skip real changes in apply"
      print "  AUTO_APPROVE=true     Skip confirmation in teardown"
      print "  TF_VAR_FILE=<path>    Pass a .tfvars file"
      print "  TF_BIN=terraform      Use HashiCorp Terraform instead of OpenTofu"
      exit 1
      ;;
  esac
}

main "$@"
