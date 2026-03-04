#!/usr/bin/env bash
# =============================================================================
# vm.sh — Lima VM lifecycle management script
# =============================================================================
#
# A single script for managing Lima VMs: create, start, stop, shell, delete,
# backup, and more. Wraps `limactl` with helpful defaults and guardrails.
#
# Usage:
#   ./lima/scripts/vm.sh <command> [args...]
#
# Commands:
#   create  <distro> [name]     Create a new VM from a template
#   start   <name>              Start a stopped VM
#   stop    <name>              Gracefully shut down a VM
#   restart <name>              Stop then start
#   shell   <name> [cmd...]     Open a shell or run a command in the VM
#   ssh     <name>              Add/update VM to ~/.ssh/config and print info
#   list                        List all VMs and their status
#   status  <name>              Show detailed status for one VM
#   ip      <name>              Print the VM's IP address (shared/bridged networks)
#   delete  <name>              Delete a VM and all its data (IRREVERSIBLE)
#   backup  <name> [dest]       Copy VM disk image to a backup location
#   prune                       Delete all VMs in "stopped" state (interactive)
#   prereqs                     Check/install prerequisites (socket_vmnet, etc.)
#
# Examples:
#   ./lima/scripts/vm.sh prereqs
#   ./lima/scripts/vm.sh create debian mydebian
#   ./lima/scripts/vm.sh create ubuntu           # uses "ubuntu" as the name
#   ./lima/scripts/vm.sh start mydebian
#   ./lima/scripts/vm.sh shell mydebian
#   ./lima/scripts/vm.sh shell mydebian -- htop
#   ./lima/scripts/vm.sh ip mydebian
#   ./lima/scripts/vm.sh backup mydebian ~/Backups
#   ./lima/scripts/vm.sh delete mydebian
#
# =============================================================================

set -euo pipefail

# ---------------------------------------------------------------------------
# Configuration — edit these paths if you move the repo
# ---------------------------------------------------------------------------
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
TEMPLATES_DIR="$REPO_ROOT/lima/templates"

# Where Lima stores VM state. Rarely needs changing.
LIMA_HOME="${LIMA_HOME:-$HOME/.lima}"

# Default backup directory
DEFAULT_BACKUP_DIR="$HOME/lima-backups"

# ---------------------------------------------------------------------------
# Colors for output
# ---------------------------------------------------------------------------
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
BOLD='\033[1m'
RESET='\033[0m'

info()    { echo -e "${CYAN}[vm.sh]${RESET} $*"; }
success() { echo -e "${GREEN}[vm.sh] ✓${RESET} $*"; }
warn()    { echo -e "${YELLOW}[vm.sh] ⚠${RESET} $*"; }
error()   { echo -e "${RED}[vm.sh] ✗${RESET} $*" >&2; }
die()     { error "$*"; exit 1; }

# ---------------------------------------------------------------------------
# Guard: ensure limactl is installed
# ---------------------------------------------------------------------------
require_limactl() {
  if ! command -v limactl &>/dev/null; then
    die "limactl not found. Install Lima with: brew install lima"
  fi
}

# ---------------------------------------------------------------------------
# Helper: get VM status from plain `limactl list` output
# limactl list outputs: NAME  STATUS  SSH  ARCH  CPUS  MEMORY  DISK  DIR
# ---------------------------------------------------------------------------
vm_status() {
  local name="$1"
  limactl list 2>/dev/null | awk -v n="$name" '$1 == n {print $2}' | head -1
}

# Helper: check if a VM name exists
vm_exists() {
  local name="$1"
  limactl list 2>/dev/null | awk 'NR>1 {print $1}' | grep -qx "$name"
}

# ---------------------------------------------------------------------------
# Command: prereqs
# Check and optionally install prerequisites for full networking support.
# ---------------------------------------------------------------------------
cmd_prereqs() {
  info "Checking prerequisites..."
  local ok=true

  # Lima itself
  if command -v limactl &>/dev/null; then
    success "lima $(limactl --version 2>&1 | head -1)"
  else
    error "lima not installed. Run: brew install lima"
    ok=false
  fi

  # socket_vmnet (required for 'shared' networking mode)
  if brew list socket_vmnet &>/dev/null 2>&1; then
    success "socket_vmnet installed"
  else
    warn "socket_vmnet not installed (required for 'shared' networking)"
    echo "  Install with: brew install socket_vmnet"
    ok=false
  fi

  # sudoers entry for lima (allows lima to manage vmnet without a password prompt)
  if [[ -f /etc/sudoers.d/lima ]]; then
    success "Lima sudoers file present (/etc/sudoers.d/lima)"
  else
    warn "Lima sudoers entry missing. Without it, you'll get sudo prompts at VM start."
    echo "  Fix with: limactl sudoers | sudo tee /etc/sudoers.d/lima"
    ok=false
  fi

  # QEMU (needed for vmType: qemu templates)
  if command -v qemu-system-x86_64 &>/dev/null || command -v qemu-system-aarch64 &>/dev/null; then
    success "QEMU installed"
  else
    warn "QEMU not installed (needed for arch/alpine/intel-cross templates)"
    echo "  Install with: brew install qemu"
  fi

  echo ""
  if $ok; then
    success "All required prerequisites satisfied."
  else
    warn "Some prerequisites are missing. Run the commands above to fix them."
    echo ""
    echo "  Quick setup:"
    echo "    brew install lima socket_vmnet qemu"
    echo "    limactl sudoers | sudo tee /etc/sudoers.d/lima"
    exit 1
  fi
}

# ---------------------------------------------------------------------------
# Command: list
# List all VMs with status.
# ---------------------------------------------------------------------------
cmd_list() {
  require_limactl
  echo ""
  limactl list
  echo ""
  info "VM state files: $LIMA_HOME/"
  info "Available templates: $TEMPLATES_DIR/"
  ls "$TEMPLATES_DIR"/*.yaml 2>/dev/null | xargs -I{} basename {} .yaml | \
    awk '{printf "  - %s\n", $0}'
}

# ---------------------------------------------------------------------------
# Command: create
# Create a VM from a distro template with an optional custom name.
#
# Why separate create from start?
#   - Lets you inspect the resolved config before first boot
#   - First boot runs cloud-init which is slow; you may want to batch creates
#   - Failed creates (bad image URL, no disk space) don't leave a broken running VM
#
# Usage: vm.sh create <distro> [name]
# ---------------------------------------------------------------------------
cmd_create() {
  require_limactl
  local distro="${1:-}"
  local name="${2:-$distro}"

  [[ -z "$distro" ]] && die "Usage: vm.sh create <distro> [name]\n  Available: $(ls "$TEMPLATES_DIR"/*.yaml | xargs -I{} basename {} .yaml | tr '\n' ' ')"

  local template="$TEMPLATES_DIR/${distro}.yaml"
  [[ -f "$template" ]] || die "Template not found: $template\nAvailable: $(ls "$TEMPLATES_DIR"/*.yaml | xargs -I{} basename {} .yaml | tr '\n' ' ')"

  # Check if a VM with this name already exists
  if vm_exists "$name"; then
    die "A VM named '$name' already exists. Use a different name or delete it first:\n  vm.sh delete $name"
  fi

  info "Creating VM '$name' from template: $distro"
  info "Template path: $template"
  echo ""

  # --tty=false suppresses the interactive "override" prompt.
  # Remove it if you want Lima to ask you about configuration before creating.
  limactl create --name="$name" --tty=false "$template"

  echo ""
  success "VM '$name' created (not yet started)"
  echo ""
  echo "  To start:        ./lima/scripts/vm.sh start $name"
  echo "  To start + shell: limactl start $name && limactl shell $name"
  echo ""
  echo "  State files: $LIMA_HOME/$name/"
  echo "  Edit config (before first start only): $LIMA_HOME/$name/lima.yaml"
}

# ---------------------------------------------------------------------------
# Command: start
# Start a VM (creates + starts if given a template file, starts if it exists).
# ---------------------------------------------------------------------------
cmd_start() {
  require_limactl
  local name="${1:-}"
  [[ -z "$name" ]] && die "Usage: vm.sh start <name>"

  if ! vm_exists "$name"; then
    die "VM '$name' not found. Create it first: vm.sh create <distro> $name"
  fi

  local status
  status=$(vm_status "$name")

  if [[ "$status" == "Running" ]]; then
    warn "VM '$name' is already running"
    return 0
  fi

  info "Starting VM '$name'..."
  limactl start "$name"
  success "VM '$name' is running"
  echo ""
  echo "  Open shell:  ./lima/scripts/vm.sh shell $name"
  echo "  Get IP:      ./lima/scripts/vm.sh ip $name"
}

# ---------------------------------------------------------------------------
# Command: stop
# Gracefully stop a running VM.
# Data is preserved — the disk image remains in ~/.lima/<name>/.
# ---------------------------------------------------------------------------
cmd_stop() {
  require_limactl
  local name="${1:-}"
  local force="${2:-}"
  [[ -z "$name" ]] && die "Usage: vm.sh stop <name> [--force]"

  local status
  status=$(vm_status "$name")

  if [[ "$status" != "Running" ]]; then
    warn "VM '$name' is not running (status: $status)"
    return 0
  fi

  if [[ "$force" == "--force" ]]; then
    warn "Force-stopping VM '$name' (like pulling the power — may corrupt data)"
    limactl stop --force "$name"
  else
    info "Stopping VM '$name' gracefully..."
    limactl stop "$name"
  fi

  success "VM '$name' stopped. Disk preserved at: $LIMA_HOME/$name/"
}

# ---------------------------------------------------------------------------
# Command: restart
# ---------------------------------------------------------------------------
cmd_restart() {
  require_limactl
  local name="${1:-}"
  [[ -z "$name" ]] && die "Usage: vm.sh restart <name>"
  cmd_stop "$name"
  sleep 1
  cmd_start "$name"
}

# ---------------------------------------------------------------------------
# Command: shell
# Open an interactive shell or run a command inside the VM.
# ---------------------------------------------------------------------------
cmd_shell() {
  require_limactl
  local name="${1:-}"
  [[ -z "$name" ]] && die "Usage: vm.sh shell <name> [-- command args...]"
  shift

  local status
  status=$(vm_status "$name")

  if [[ "$status" != "Running" ]]; then
    warn "VM '$name' is not running (status: $status). Starting it first..."
    limactl start "$name"
  fi

  if [[ $# -gt 0 ]]; then
    # Run a specific command: vm.sh shell myvm -- htop
    limactl shell "$name" -- "$@"
  else
    # Interactive shell
    limactl shell "$name"
  fi
}

# ---------------------------------------------------------------------------
# Command: ip
# Get the guest IP address (only works with shared/bridged networking).
# With user-v2 NAT, the guest does not get a host-reachable IP.
# ---------------------------------------------------------------------------
cmd_ip() {
  require_limactl
  local name="${1:-}"
  [[ -z "$name" ]] && die "Usage: vm.sh ip <name>"

  local status
  status=$(vm_status "$name")
  [[ "$status" != "Running" ]] && die "VM '$name' is not running"

  info "IP addresses for VM '$name':"
  echo ""

  # Try lima's JSON output for the IP field
  local ips
  ips=$(limactl list --json 2>/dev/null | python3 -c \
    "import sys,json; vms=[v for v in [json.loads(l) for l in sys.stdin] if v.get('name')=='$name']; print(vms[0].get('ip','') if vms else '')" 2>/dev/null || true)
  if [[ -n "$ips" && "$ips" != "<nil>" ]]; then
    echo "  Lima reported: $ips"
  fi

  # Also query inside the guest for all interfaces
  echo "  Guest interfaces:"
  limactl shell "$name" -- ip -4 addr show | \
    grep -E 'inet ' | \
    awk '{print "    " $2, "(" $NF ")"}' || true

  echo ""
  info "SSH via: ssh $(limactl show-ssh --format config "$name" 2>/dev/null | grep '^Host ' | awk '{print $2}')"
}

# ---------------------------------------------------------------------------
# Command: ssh
# Write (or update) an SSH config entry for this VM so plain `ssh lima-<name>`
# works. Run this after starting a VM.
# ---------------------------------------------------------------------------
cmd_ssh() {
  require_limactl
  local name="${1:-}"
  [[ -z "$name" ]] && die "Usage: vm.sh ssh <name>"

  local status
  status=$(vm_status "$name")
  [[ "$status" != "Running" ]] && die "VM '$name' is not running"

  local ssh_config_file="$HOME/.ssh/config"
  local host_alias="lima-$name"

  # Remove any existing entry for this alias to avoid duplicates
  if grep -q "^Host $host_alias" "$ssh_config_file" 2>/dev/null; then
    warn "Removing existing SSH config entry for $host_alias"
    # Remove the Host block (from "Host lima-<name>" to the next blank line or Host line)
    sed -i.bak "/^Host $host_alias$/,/^Host /{ /^Host $host_alias$/d; /^Host /!d }" \
      "$ssh_config_file" 2>/dev/null || true
  fi

  # Append the new config
  echo "" >> "$ssh_config_file"
  limactl show-ssh --format=config "$name" >> "$ssh_config_file"

  success "SSH config written for '$name'"
  echo ""
  echo "  Connect with: ssh $host_alias"
  echo ""
  limactl show-ssh --format=config "$name"
}

# ---------------------------------------------------------------------------
# Command: status
# Show detailed info about a single VM.
# ---------------------------------------------------------------------------
cmd_status() {
  require_limactl
  local name="${1:-}"
  [[ -z "$name" ]] && die "Usage: vm.sh status <name>"

  echo ""
  limactl list "$name" 2>/dev/null || die "VM '$name' not found"
  echo ""

  local disk_path
  disk_path=$(find "$LIMA_HOME/$name" -name "*.qcow2" -o -name "diffdisk" 2>/dev/null | head -1)
  if [[ -n "$disk_path" ]]; then
    info "Disk: $disk_path"
    du -sh "$disk_path" 2>/dev/null | awk '{print "  Used on host: " $1}'
    if command -v qemu-img &>/dev/null; then
      qemu-img info "$disk_path" 2>/dev/null | grep -E 'virtual size|disk size' | \
        awk '{print "  " $0}' || true
    fi
  fi
  echo ""
  info "Config: $LIMA_HOME/$name/lima.yaml"
  info "Logs:   $LIMA_HOME/$name/serial*.log (if exists)"
}

# ---------------------------------------------------------------------------
# Command: delete
# Delete a VM and ALL its data including the disk image. IRREVERSIBLE.
# The VM is stopped first if running.
# ---------------------------------------------------------------------------
cmd_delete() {
  require_limactl
  local name="${1:-}"
  [[ -z "$name" ]] && die "Usage: vm.sh delete <name>"

  if ! vm_exists "$name"; then
    die "VM '$name' not found"
  fi

  # Show what will be deleted
  echo ""
  warn "This will permanently delete VM '$name' and ALL its data."
  local disk_path
  disk_path=$(find "$LIMA_HOME/$name" -name "*.qcow2" -o -name "diffdisk" 2>/dev/null | head -1)
  if [[ -n "$disk_path" ]]; then
    echo "  Disk to be removed: $disk_path ($(du -sh "$disk_path" 2>/dev/null | cut -f1))"
  fi
  echo ""

  # Confirm deletion
  read -r -p "  Type the VM name to confirm deletion: " confirm
  if [[ "$confirm" != "$name" ]]; then
    echo "Aborted. You typed '$confirm', expected '$name'."
    exit 0
  fi

  echo ""
  info "Deleting VM '$name'..."
  limactl delete --force "$name"
  success "VM '$name' deleted."
}

# ---------------------------------------------------------------------------
# Command: backup
# Copy the VM disk image to a backup location.
# The VM should be stopped before backing up to ensure consistency.
# ---------------------------------------------------------------------------
cmd_backup() {
  require_limactl
  local name="${1:-}"
  local dest="${2:-$DEFAULT_BACKUP_DIR}"
  [[ -z "$name" ]] && die "Usage: vm.sh backup <name> [destination-dir]"

  local status
  status=$(vm_status "$name")

  if [[ "$status" == "Running" ]]; then
    warn "VM '$name' is running. Backing up a live disk may produce an inconsistent image."
    warn "Recommend: stop the VM first with: vm.sh stop $name"
    read -r -p "  Continue anyway? [y/N] " yn
    [[ "$yn" =~ ^[Yy]$ ]] || { echo "Aborted."; exit 0; }
  fi

  mkdir -p "$dest"
  local timestamp
  timestamp=$(date +%Y%m%d-%H%M%S)
  local backup_dir="$dest/${name}-${timestamp}"
  mkdir -p "$backup_dir"

  info "Backing up VM '$name' to: $backup_dir"

  # Copy all significant files (disk images, config)
  # basedisk = the downloaded cloud image (read-only base layer)
  # diffdisk  = your changes on top of the base layer (the important one)
  # lima.yaml = the config used to create this VM
  while IFS= read -r -d '' f; do
    info "  Copying: $(basename "$f")"
    cp "$f" "$backup_dir/"
  done < <(find "$LIMA_HOME/$name" \
    \( -name "*.yaml" -o -name "*disk*" -o -name "*.img" -o -name "*.qcow2" \) \
    -maxdepth 1 -type f -print0 2>/dev/null)

  success "Backup complete: $backup_dir"
  du -sh "$backup_dir"
}

# ---------------------------------------------------------------------------
# Command: prune
# Interactively delete all stopped/broken VMs.
# ---------------------------------------------------------------------------
cmd_prune() {
  require_limactl
  echo ""
  info "Stopped/broken VMs:"
  # limactl list outputs: NAME  STATUS  SSH  ARCH  CPUS  MEMORY  DISK  DIR
  # Select rows where STATUS (column 2) is not "Running"
  local stopped
  stopped=$(limactl list 2>/dev/null | awk 'NR>1 && $2 != "Running" {print $1 " (" $2 ")"}') || true

  if [[ -z "$stopped" ]]; then
    success "No stopped VMs found."
    return 0
  fi

  echo "$stopped" | awk '{print "  - " $0}'
  echo ""
  read -r -p "Delete ALL of the above? [y/N] " yn
  if [[ "$yn" =~ ^[Yy]$ ]]; then
    echo "$stopped" | awk '{print $1}' | while read -r vm; do
      info "Deleting $vm..."
      limactl delete --force "$vm"
    done
    success "Done."
  else
    echo "Aborted."
  fi
}

# ---------------------------------------------------------------------------
# Main dispatch
# ---------------------------------------------------------------------------
usage() {
  echo ""
  echo "${BOLD}vm.sh — Lima VM management${RESET}"
  echo ""
  echo "Usage: $0 <command> [args...]"
  echo ""
  echo "Commands:"
  echo "  prereqs               Check/install prerequisites"
  echo "  list                  List all VMs"
  echo "  create  <distro> [name]   Create VM from template (does not start)"
  echo "  start   <name>        Start a VM"
  echo "  stop    <name> [--force]  Stop a VM"
  echo "  restart <name>        Restart a VM"
  echo "  shell   <name> [-- cmd]   Shell into VM or run a command"
  echo "  ssh     <name>        Update ~/.ssh/config for this VM"
  echo "  ip      <name>        Show guest IP addresses"
  echo "  status  <name>        Show detailed VM status"
  echo "  backup  <name> [dir]  Backup VM disk to a directory"
  echo "  delete  <name>        Delete VM and all data (irreversible)"
  echo "  prune                 Delete all stopped VMs (interactive)"
  echo ""
  echo "Available templates:"
  ls "$TEMPLATES_DIR"/*.yaml 2>/dev/null | xargs -I{} basename {} .yaml | \
    awk '{printf "  %s\n", $0}'
  echo ""
  echo "Examples:"
  echo "  $0 prereqs"
  echo "  $0 create debian mydebian"
  echo "  $0 start mydebian"
  echo "  $0 shell mydebian"
  echo "  $0 shell mydebian -- sudo apt install -y neovim"
  echo "  $0 ip mydebian"
  echo "  $0 backup mydebian ~/Backups"
  echo "  $0 delete mydebian"
  echo ""
}

main() {
  local cmd="${1:-}"
  shift || true

  case "$cmd" in
    prereqs)             cmd_prereqs "$@" ;;
    list|ls)             cmd_list "$@" ;;
    create|new)          cmd_create "$@" ;;
    start|up)            cmd_start "$@" ;;
    stop|down)           cmd_stop "$@" ;;
    restart|reboot)      cmd_restart "$@" ;;
    shell|sh|exec)       cmd_shell "$@" ;;
    ssh|config)          cmd_ssh "$@" ;;
    ip|addr)             cmd_ip "$@" ;;
    status|info)         cmd_status "$@" ;;
    backup|snapshot)     cmd_backup "$@" ;;
    delete|rm|destroy)   cmd_delete "$@" ;;
    prune|clean)         cmd_prune "$@" ;;
    help|--help|-h|"")   usage ;;
    *)
      error "Unknown command: $cmd"
      usage
      exit 1
      ;;
  esac
}

main "$@"
