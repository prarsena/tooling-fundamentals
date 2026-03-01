#!/usr/bin/env bash
# =============================================================================
# container.sh — Apple container lifecycle management script
# =============================================================================
#
# A single script for managing Apple container containers, images, networks,
# volumes, and the container system service. Wraps the `container` CLI with
# opinionated defaults, guardrails, and helpful output.
#
# Usage:
#   ./container/scripts/container.sh <command> [args...]
#
# System Commands:
#   start                       Start the container system service
#   stop                        Stop the container system service
#   restart                     Restart the container system service
#   status                      Show service health and version
#   logs [--follow] [--last Xm] Tail system service logs
#   df                          Show disk usage (images, containers, volumes)
#   prereqs                     Check macOS version and container installation
#
# Container Commands:
#   run    <image> [args...]    Run a container (foreground, interactive)
#   rund   <name> <image> [args...] Run a detached named container
#   stop-c <name>               Stop a container gracefully
#   kill-c <name>               Kill a container immediately
#   rm-c   <name>               Remove a stopped container
#   exec   <name> [cmd...]      Exec into a running container (defaults to shell)
#   logs-c <name> [--boot]      Fetch container stdout/stderr or boot logs
#   stats  [name...]            Show resource usage stats
#   list                        List all containers (running + stopped)
#   inspect <name>              Show detailed JSON for a container
#   ip <name>                   Print a container's IP address
#   prune-c                     Remove all stopped containers
#
# Image Commands:
#   pull   <image>              Pull an image from a registry
#   build  <tag> [dir] [file]   Build an image from a Dockerfile
#   push   <image>              Push an image to a registry
#   tag    <src> <dst>          Re-tag an image
#   images                      List local images
#   rmi    <image>              Remove an image
#   prune-i [--all]             Remove unused images
#   save   <image> <file.tar>   Export image to tar archive
#   load   <file.tar>           Load image from tar archive
#
# Network Commands:
#   net-list                    List networks
#   net-create <name> [subnet]  Create a user-defined network
#   net-rm     <name>           Delete a network
#   net-prune                   Remove unused networks
#
# Volume Commands:
#   vol-list                    List volumes
#   vol-create <name> [size]    Create a named volume
#   vol-rm     <name>           Delete a volume
#   vol-prune                   Remove unused volumes
#
# DNS Commands:
#   dns-create <domain>         Create a local DNS domain (needs sudo)
#   dns-list                    List configured DNS domains
#   dns-rm     <domain>         Remove a DNS domain (needs sudo)
#
# Registry Commands:
#   login  [registry]           Login to a registry
#   logout [registry]           Logout from a registry
#
# Examples:
#   ./container/scripts/container.sh prereqs
#   ./container/scripts/container.sh start
#   ./container/scripts/container.sh rund web nginx:latest
#   ./container/scripts/container.sh exec web
#   ./container/scripts/container.sh build myapp:latest ./myapp
#   ./container/scripts/container.sh ip web
#   ./container/scripts/container.sh dns-create test
#   ./container/scripts/container.sh prune-c && container/scripts/container.sh prune-i
#
# =============================================================================

set -euo pipefail

# ---------------------------------------------------------------------------
# Colors
# ---------------------------------------------------------------------------
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
BOLD='\033[1m'
RESET='\033[0m'

info()    { echo -e "${CYAN}[container.sh]${RESET} $*"; }
success() { echo -e "${GREEN}[container.sh] ✓${RESET} $*"; }
warn()    { echo -e "${YELLOW}[container.sh] ⚠${RESET} $*"; }
error()   { echo -e "${RED}[container.sh] ✗${RESET} $*" >&2; }
die()     { error "$*"; exit 1; }

# ---------------------------------------------------------------------------
# Guards
# ---------------------------------------------------------------------------
require_container() {
  if ! command -v container &>/dev/null; then
    die "'container' not found in PATH.\n  Download the installer from: https://github.com/apple/container/releases\n  Then run: container system start"
  fi
}

require_running() {
  # Quick health check: does the API server respond?
  if ! container system status &>/dev/null 2>&1; then
    die "Container system service is not running. Start it with: container system start"
  fi
}

check_apple_silicon() {
  local arch
  arch=$(uname -m)
  if [[ "$arch" != "arm64" ]]; then
    die "apple/container requires Apple silicon (arm64). This machine is: $arch"
  fi
}

check_macos_version() {
  local version
  version=$(sw_vers -productVersion)
  local major minor
  major=$(echo "$version" | cut -d. -f1)
  if (( major < 26 )); then
    warn "apple/container is fully supported on macOS 26+. Detected: $version"
    warn "Some features (container-to-container networking, multiple networks) won't work."
  else
    success "macOS $version — full feature support."
  fi
}

# ---------------------------------------------------------------------------
# Command: prereqs
# Check system requirements and installation status.
# ---------------------------------------------------------------------------
cmd_prereqs() {
  echo ""
  info "Checking prerequisites for apple/container..."
  echo ""

  check_apple_silicon && success "Apple silicon (arm64)"

  check_macos_version

  if command -v container &>/dev/null; then
    local ver
    ver=$(container system version --format json 2>/dev/null | python3 -c "import sys,json; d=json.load(sys.stdin); print(d.get('version','unknown'))" 2>/dev/null || echo "unknown")
    success "container CLI installed ($ver)"
  else
    error "container CLI not found."
    echo "  Install from: https://github.com/apple/container/releases"
    echo ""
    exit 1
  fi

  # Check service status
  if container system status &>/dev/null 2>&1; then
    success "Container system service is running"
  else
    warn "Container system service is NOT running."
    echo "  Start it with: container system start"
  fi

  echo ""
  success "Prerequisites satisfied. You're good to go."
  echo ""
}

# ---------------------------------------------------------------------------
# System Commands
# ---------------------------------------------------------------------------

cmd_start() {
  require_container
  info "Starting container system service..."
  container system start
  echo ""
  success "Container system service started."
  container system status
}

cmd_stop() {
  require_container
  # Warn if containers are running
  local running
  running=$(container ls --format json 2>/dev/null | python3 -c "import sys,json; d=json.load(sys.stdin); print(len([c for c in d if c.get('status')=='running']))" 2>/dev/null || echo "0")
  if (( running > 0 )); then
    warn "$running container(s) are still running. They will be stopped."
    container ls
    echo ""
    read -r -p "Continue? [y/N] " answer
    [[ "${answer,,}" == "y" ]] || { info "Aborted."; exit 0; }
  fi
  info "Stopping container system service..."
  container system stop
  success "Container system service stopped."
}

cmd_restart() {
  cmd_stop
  sleep 1
  cmd_start
}

cmd_status() {
  require_container
  echo ""
  container system status
  echo ""
  container system version
  echo ""
  container system df
}

cmd_service_logs() {
  require_container
  # Pass remaining flags directly to container system logs
  container system logs "$@"
}

cmd_df() {
  require_container
  container system df
}

# ---------------------------------------------------------------------------
# Container Commands
# ---------------------------------------------------------------------------

# cmd_run: run a container interactively (foreground). Extra args go to container run.
# Usage: container.sh run <image> [args...]
cmd_run() {
  require_container
  require_running
  local image="${1:-}"
  [[ -z "$image" ]] && die "Usage: container.sh run <image> [command args...]"
  shift
  info "Running container from image: $image"
  container run -it --rm "$image" "$@"
}

# cmd_rund: run a named container detached.
# Usage: container.sh rund <name> <image> [extra container run flags...]
cmd_rund() {
  require_container
  require_running
  local name="${1:-}"
  local image="${2:-}"
  [[ -z "$name" || -z "$image" ]] && die "Usage: container.sh rund <name> <image> [extra-flags...]"
  shift 2
  info "Starting detached container '$name' from image '$image'..."
  container run -d --name "$name" --rm "$image" "$@"
  success "Container '$name' started."
  echo ""
  # Wait briefly for it to get an IP
  sleep 1
  cmd_ip "$name" 2>/dev/null || true
}

# cmd_stop_container: gracefully stop a container.
cmd_stop_container() {
  require_container
  local name="${1:-}"
  [[ -z "$name" ]] && die "Usage: container.sh stop-c <name>"
  local grace="${2:-5}"
  info "Stopping container '$name' (${grace}s grace)..."
  container stop --time "$grace" "$name"
  success "Container '$name' stopped."
}

# cmd_kill_container: immediately kill a container.
cmd_kill_container() {
  require_container
  local name="${1:-}"
  [[ -z "$name" ]] && die "Usage: container.sh kill-c <name>"
  info "Killing container '$name'..."
  container kill "$name"
  success "Container '$name' killed."
}

# cmd_rm_container: remove a stopped container.
cmd_rm_container() {
  require_container
  local name="${1:-}"
  [[ -z "$name" ]] && die "Usage: container.sh rm-c <name>"
  info "Removing container '$name'..."
  container rm "$name"
  success "Container '$name' removed."
}

# cmd_exec: exec a command in a running container.
# Usage: container.sh exec <name> [cmd...]
cmd_exec() {
  require_container
  require_running
  local name="${1:-}"
  [[ -z "$name" ]] && die "Usage: container.sh exec <name> [command...]"
  shift
  local cmd_args=("$@")
  if (( ${#cmd_args[@]} == 0 )); then
    # Default to a shell — try sh since containers may not have bash
    info "Opening shell in container '$name'..."
    container exec -it "$name" /bin/sh
  else
    container exec -it "$name" "${cmd_args[@]}"
  fi
}

# cmd_logs_container: fetch container logs.
# Usage: container.sh logs-c <name> [--boot] [--follow] [-n N]
cmd_logs_container() {
  require_container
  local name="${1:-}"
  [[ -z "$name" ]] && die "Usage: container.sh logs-c <name> [--boot] [--follow] [-n N]"
  shift
  container logs "$@" "$name"
}

# cmd_stats: show resource usage.
cmd_stats() {
  require_container
  require_running
  if (( $# == 0 )); then
    container stats
  else
    container stats "$@"
  fi
}

# cmd_list: list containers.
cmd_list() {
  require_container
  echo ""
  container ls -a
  echo ""
}

# cmd_inspect: inspect a container.
cmd_inspect_container() {
  require_container
  local name="${1:-}"
  [[ -z "$name" ]] && die "Usage: container.sh inspect <name>"
  container inspect "$name" | python3 -m json.tool
}

# cmd_ip: get the IP address of a running container.
cmd_ip() {
  require_container
  local name="${1:-}"
  [[ -z "$name" ]] && die "Usage: container.sh ip <name>"
  local ip
  ip=$(container inspect "$name" 2>/dev/null \
    | python3 -c "import sys,json; d=json.load(sys.stdin); nets=d[0].get('networks',[]); print(nets[0]['address'].split('/')[0] if nets else 'no-ip')" 2>/dev/null \
    || echo "")
  if [[ -z "$ip" || "$ip" == "no-ip" ]]; then
    warn "Could not determine IP for '$name'. Is it running?"
    return 1
  fi
  echo "$ip"
  info "Container '$name' IP: $ip"
}

# cmd_prune_containers: remove all stopped containers.
cmd_prune_containers() {
  require_container
  info "Removing all stopped containers..."
  container prune
  success "Stopped containers removed."
}

# ---------------------------------------------------------------------------
# Image Commands
# ---------------------------------------------------------------------------

cmd_pull() {
  require_container
  require_running
  local image="${1:-}"
  [[ -z "$image" ]] && die "Usage: container.sh pull <image>"
  info "Pulling image: $image"
  container image pull "$image"
  success "Pulled: $image"
}

# cmd_build: build an image.
# Usage: container.sh build <tag> [build-dir] [dockerfile]
cmd_build() {
  require_container
  require_running
  local tag="${1:-}"
  [[ -z "$tag" ]] && die "Usage: container.sh build <tag> [build-dir] [dockerfile]"
  local dir="${2:-.}"
  local file="${3:-Dockerfile}"

  # Resolve dockerfile path if it's not absolute
  if [[ ! -f "$file" && -f "$dir/$file" ]]; then
    file="$dir/$file"
  fi

  info "Building image '$tag' from '$dir' using '$file'..."
  container build -t "$tag" -f "$file" "$dir"
  success "Image built: $tag"
}

cmd_push() {
  require_container
  local image="${1:-}"
  [[ -z "$image" ]] && die "Usage: container.sh push <image>"
  info "Pushing image: $image"
  container image push "$image"
  success "Pushed: $image"
}

cmd_tag() {
  require_container
  local src="${1:-}"
  local dst="${2:-}"
  [[ -z "$src" || -z "$dst" ]] && die "Usage: container.sh tag <source> <target>"
  container image tag "$src" "$dst"
  success "Tagged: $src → $dst"
}

cmd_images() {
  require_container
  echo ""
  container image list --verbose
  echo ""
}

cmd_rmi() {
  require_container
  local image="${1:-}"
  [[ -z "$image" ]] && die "Usage: container.sh rmi <image>"
  info "Removing image: $image"
  container image delete "$image"
  success "Removed: $image"
}

cmd_prune_images() {
  require_container
  local all=false
  [[ "${1:-}" == "--all" ]] && all=true
  if $all; then
    info "Removing all unused images (including tagged)..."
    container image prune --all
  else
    info "Removing dangling (untagged) images..."
    container image prune
  fi
  success "Done."
}

cmd_save() {
  require_container
  local image="${1:-}"
  local file="${2:-}"
  [[ -z "$image" || -z "$file" ]] && die "Usage: container.sh save <image> <output.tar>"
  info "Saving '$image' to '$file'..."
  container image save -o "$file" "$image"
  success "Saved: $file ($(du -sh "$file" | cut -f1))"
}

cmd_load() {
  require_container
  local file="${1:-}"
  [[ -z "$file" ]] && die "Usage: container.sh load <input.tar>"
  [[ -f "$file" ]] || die "File not found: $file"
  info "Loading image from '$file'..."
  container image load -i "$file"
  success "Loaded."
}

# ---------------------------------------------------------------------------
# Network Commands
# ---------------------------------------------------------------------------

cmd_net_list() {
  require_container
  echo ""
  container network list
  echo ""
}

cmd_net_create() {
  require_container
  local name="${1:-}"
  [[ -z "$name" ]] && die "Usage: container.sh net-create <name> [subnet-cidr]"
  local subnet="${2:-}"
  if [[ -n "$subnet" ]]; then
    info "Creating network '$name' with subnet $subnet..."
    container network create "$name" --subnet "$subnet"
  else
    info "Creating network '$name'..."
    container network create "$name"
  fi
  success "Network '$name' created."
  container network inspect "$name"
}

cmd_net_rm() {
  require_container
  local name="${1:-}"
  [[ -z "$name" ]] && die "Usage: container.sh net-rm <name>"
  info "Deleting network '$name'..."
  container network delete "$name"
  success "Network '$name' deleted."
}

cmd_net_prune() {
  require_container
  info "Removing unused networks..."
  container network prune
  success "Done."
}

# ---------------------------------------------------------------------------
# Volume Commands
# ---------------------------------------------------------------------------

cmd_vol_list() {
  require_container
  echo ""
  container volume list
  echo ""
}

cmd_vol_create() {
  require_container
  local name="${1:-}"
  [[ -z "$name" ]] && die "Usage: container.sh vol-create <name> [size]"
  local size="${2:-}"
  if [[ -n "$size" ]]; then
    info "Creating volume '$name' (size: $size)..."
    container volume create "$name" -s "$size"
  else
    info "Creating volume '$name'..."
    container volume create "$name"
  fi
  success "Volume '$name' created."
}

cmd_vol_rm() {
  require_container
  local name="${1:-}"
  [[ -z "$name" ]] && die "Usage: container.sh vol-rm <name>"
  info "Deleting volume '$name'..."
  container volume delete "$name"
  success "Volume '$name' deleted."
}

cmd_vol_prune() {
  require_container
  info "Removing unreferenced volumes..."
  container volume prune
  success "Done."
}

# ---------------------------------------------------------------------------
# DNS Commands
# ---------------------------------------------------------------------------

cmd_dns_create() {
  local domain="${1:-}"
  [[ -z "$domain" ]] && die "Usage: container.sh dns-create <domain>"
  info "Creating DNS domain '$domain' (requires sudo)..."
  sudo container system dns create "$domain"
  container system property set dns.domain "$domain"
  success "DNS domain '$domain' configured. Containers reachable as <name>.$domain"
}

cmd_dns_list() {
  container system dns list
}

cmd_dns_rm() {
  local domain="${1:-}"
  [[ -z "$domain" ]] && die "Usage: container.sh dns-rm <domain>"
  info "Removing DNS domain '$domain' (requires sudo)..."
  sudo container system dns delete "$domain"
  success "DNS domain '$domain' removed."
}

# ---------------------------------------------------------------------------
# Registry Commands
# ---------------------------------------------------------------------------

cmd_login() {
  local registry="${1:-}"
  if [[ -n "$registry" ]]; then
    info "Logging in to $registry..."
    container registry login "$registry"
  else
    info "Logging in to default registry (Docker Hub)..."
    container registry login
  fi
  success "Logged in."
}

cmd_logout() {
  local registry="${1:-}"
  if [[ -n "$registry" ]]; then
    container registry logout "$registry"
    success "Logged out of $registry."
  else
    warn "Specify a registry to log out of: container.sh logout <registry>"
  fi
}

# ---------------------------------------------------------------------------
# Help
# ---------------------------------------------------------------------------
cmd_help() {
  cat <<'EOF'

  container.sh — Apple container lifecycle management

  SYSTEM:
    prereqs                         Check system requirements
    start                           Start the container system service
    stop                            Stop the container system service (warns if containers running)
    restart                         stop + start
    status                          Health, version, and disk usage
    logs [--follow] [--last 10m]    System service logs
    df                              Disk usage summary

  CONTAINERS:
    run    <image> [cmd]            Run interactively (--rm, -it)
    rund   <name> <image> [flags]   Run detached and named
    stop-c <name> [grace-secs]      Graceful stop
    kill-c <name>                   Immediate SIGKILL
    rm-c   <name>                   Remove stopped container
    exec   <name> [cmd...]          Exec into running container (default: shell)
    logs-c <name> [--boot]          Container stdout/stderr or boot logs
    stats  [name...]                Live resource stats
    list                            List all containers
    inspect <name>                  Detailed JSON
    ip     <name>                   Print container IP
    prune-c                         Remove all stopped containers

  IMAGES:
    pull   <image>                  Pull from registry
    build  <tag> [dir] [file]       Build from Dockerfile
    push   <image>                  Push to registry
    tag    <src> <dst>              Re-tag
    images                          List local images
    rmi    <image>                  Remove image
    prune-i [--all]                 Remove unused images
    save   <image> <file.tar>       Export to tar
    load   <file.tar>               Import from tar

  NETWORKS (macOS 26+):
    net-list                        List networks
    net-create <name> [subnet]      Create network
    net-rm     <name>               Delete network
    net-prune                       Remove unused networks

  VOLUMES:
    vol-list                        List volumes
    vol-create <name> [size]        Create volume (e.g. 10G)
    vol-rm     <name>               Delete volume
    vol-prune                       Remove unreferenced volumes

  DNS:
    dns-create <domain>             Create local DNS domain (sudo)
    dns-list                        List domains
    dns-rm     <domain>             Remove domain (sudo)

  REGISTRY:
    login  [registry]               Login
    logout [registry]               Logout

  EXAMPLES:
    # First-time setup
    ./container/scripts/container.sh prereqs
    ./container/scripts/container.sh start
    ./container/scripts/container.sh dns-create test

    # Run a web server
    ./container/scripts/container.sh rund web -p 8080:80 nginx:latest
    ./container/scripts/container.sh ip web
    ./container/scripts/container.sh logs-c web

    # Build and push an image
    ./container/scripts/container.sh build myapp:latest ./myapp
    ./container/scripts/container.sh login ghcr.io
    ./container/scripts/container.sh tag myapp:latest ghcr.io/myorg/myapp:latest
    ./container/scripts/container.sh push ghcr.io/myorg/myapp:latest

    # Cleanup
    ./container/scripts/container.sh prune-c
    ./container/scripts/container.sh prune-i
    ./container/scripts/container.sh vol-prune

EOF
}

# ---------------------------------------------------------------------------
# Dispatch
# ---------------------------------------------------------------------------
main() {
  local cmd="${1:-help}"
  [[ $# -gt 0 ]] && shift

  case "$cmd" in
    # System
    prereqs)                cmd_prereqs "$@" ;;
    start)                  cmd_start "$@" ;;
    stop)                   cmd_stop "$@" ;;
    restart)                cmd_restart "$@" ;;
    status)                 cmd_status "$@" ;;
    logs)                   cmd_service_logs "$@" ;;
    df)                     cmd_df "$@" ;;

    # Containers
    run)                    cmd_run "$@" ;;
    rund)                   cmd_rund "$@" ;;
    stop-c)                 cmd_stop_container "$@" ;;
    kill-c)                 cmd_kill_container "$@" ;;
    rm-c)                   cmd_rm_container "$@" ;;
    exec)                   cmd_exec "$@" ;;
    logs-c)                 cmd_logs_container "$@" ;;
    stats)                  cmd_stats "$@" ;;
    list|ls)                cmd_list "$@" ;;
    inspect)                cmd_inspect_container "$@" ;;
    ip)                     cmd_ip "$@" ;;
    prune-c)                cmd_prune_containers "$@" ;;

    # Images
    pull)                   cmd_pull "$@" ;;
    build)                  cmd_build "$@" ;;
    push)                   cmd_push "$@" ;;
    tag)                    cmd_tag "$@" ;;
    images)                 cmd_images "$@" ;;
    rmi)                    cmd_rmi "$@" ;;
    prune-i)                cmd_prune_images "$@" ;;
    save)                   cmd_save "$@" ;;
    load)                   cmd_load "$@" ;;

    # Networks
    net-list)               cmd_net_list "$@" ;;
    net-create)             cmd_net_create "$@" ;;
    net-rm)                 cmd_net_rm "$@" ;;
    net-prune)              cmd_net_prune "$@" ;;

    # Volumes
    vol-list)               cmd_vol_list "$@" ;;
    vol-create)             cmd_vol_create "$@" ;;
    vol-rm)                 cmd_vol_rm "$@" ;;
    vol-prune)              cmd_vol_prune "$@" ;;

    # DNS
    dns-create)             cmd_dns_create "$@" ;;
    dns-list)               cmd_dns_list "$@" ;;
    dns-rm)                 cmd_dns_rm "$@" ;;

    # Registry
    login)                  cmd_login "$@" ;;
    logout)                 cmd_logout "$@" ;;

    # Help
    help|-h|--help)         cmd_help ;;
    *)
      error "Unknown command: $cmd"
      echo ""
      cmd_help
      exit 1
      ;;
  esac
}

main "$@"
