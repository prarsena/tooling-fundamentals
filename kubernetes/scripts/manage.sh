#!/usr/bin/env zsh
# =============================================================================
# kubernetes/scripts/manage.sh
# Lifecycle manager for Kubernetes tooling on macOS.
# Covers: kubectl context validation, Helm repo init, k9s skin install.
#
# Usage:
#   ./manage.sh <command>
#   ENABLE_LOGGING=true ./manage.sh setup
#
# Commands: setup | healthcheck | teardown
# =============================================================================

set -euo pipefail

# ---------------------------------------------------------------------------
# ENVIRONMENT VARIABLE TOGGLES
# ---------------------------------------------------------------------------

# Enable verbose logging for every sub-command.
ENABLE_LOGGING="${ENABLE_LOGGING:-false}"

# The kubectl context to target. Defaults to the currently active context.
KUBE_CONTEXT="${KUBE_CONTEXT:-}"

# Namespace to use for health checks and resource listing.
TARGET_NAMESPACE="${TARGET_NAMESPACE:-default}"

# When true, skip Helm repo additions that require internet access.
SKIP_HELM_REPOS="${SKIP_HELM_REPOS:-false}"

# ---------------------------------------------------------------------------
# macOS-SPECIFIC PATHS
# k9s on macOS stores config in ~/Library/Application Support/k9s/ — this
# is different from Linux (~/.k9s/) and must be set explicitly.
# Helm on macOS stores repos/cache in ~/Library/Preferences/helm/.
# ---------------------------------------------------------------------------
K9S_CONFIG_DIR="${HOME}/Library/Application Support/k9s"
HELM_DATA_HOME="${HOME}/Library/Preferences/helm"

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

# kubectl_args
# Returns --context flag if KUBE_CONTEXT is set, otherwise empty.
kubectl_args() {
  if [[ -n "${KUBE_CONTEXT}" ]]; then
    echo "--context=${KUBE_CONTEXT}"
  fi
}

# ---------------------------------------------------------------------------
# COMMAND: setup
# Install k9s skin, initialise Helm repos, validate kubectl access.
# ---------------------------------------------------------------------------
cmd_setup() {
  info "Running setup..."
  require kubectl
  require helm
  require k9s

  # ---- k9s skin installation ----
  # macOS stores k9s config under ~/Library/Application Support/k9s/
  # rather than ~/.k9s/ (Linux). We create the directory and copy the skin.
  local skin_src="${ROOT_DIR}/supporting_files/k9s-skin.yml"
  local skin_dst="${K9S_CONFIG_DIR}/skins/catppuccin.yml"

  log "Creating k9s config dir: ${K9S_CONFIG_DIR}/skins/"
  mkdir -p "${K9S_CONFIG_DIR}/skins"

  if [[ -f "${skin_src}" ]]; then
    cp "${skin_src}" "${skin_dst}"
    info "k9s skin installed at: ${skin_dst}"
  else
    warn "Skin file not found at ${skin_src} — skipping."
  fi

  # ---- Helm repo bootstrapping ----
  # `helm repo add` is idempotent — safe to run repeatedly.
  if [[ "${SKIP_HELM_REPOS}" != "true" ]]; then
    info "Adding common Helm repos..."

    # ingress-nginx: standard ingress controller for most clusters.
    helm repo add ingress-nginx https://kubernetes.github.io/ingress-nginx 2>/dev/null || true
    log "Added ingress-nginx"

    # cert-manager: automates TLS certificate lifecycle in-cluster.
    helm repo add jetstack https://charts.jetstack.io 2>/dev/null || true
    log "Added jetstack (cert-manager)"

    # metrics-server: required by HPA (Horizontal Pod Autoscaler).
    helm repo add metrics-server https://kubernetes-sigs.github.io/metrics-server 2>/dev/null || true
    log "Added metrics-server"

    # Update the local index of all added repos.
    helm repo update
    info "Helm repos updated."
  else
    warn "SKIP_HELM_REPOS=true — skipping Helm repo setup."
  fi

  # ---- Apply baseline manifests ----
  # kubectl apply -f is idempotent — creates or no-ops if already present.
  info "Applying baseline manifests..."
  kubectl apply -f "${ROOT_DIR}/manifests/" $(kubectl_args) || \
    warn "Could not apply manifests — check your KUBECONFIG and cluster access."

  info "Setup complete. Launch k9s with: k9s"
}

# ---------------------------------------------------------------------------
# COMMAND: healthcheck
# Verifies cluster connectivity, node health, and lists Helm releases.
# ---------------------------------------------------------------------------
cmd_healthcheck() {
  info "Running healthcheck..."
  require kubectl
  require helm

  # ---- Cluster connectivity ----
  info "Checking cluster connectivity..."
  # `kubectl cluster-info` outputs the API server URL and CoreDNS address.
  # It exits non-zero if the cluster is unreachable.
  kubectl cluster-info $(kubectl_args) || error "Cannot reach Kubernetes API server."

  # ---- Node status ----
  info "Node status:"
  # BSD `column` (macOS default) uses -t for table formatting.
  # GNU `column` (Linux) shares this flag, so this is safe on both.
  kubectl get nodes $(kubectl_args) -o wide

  # ---- Pod health in target namespace ----
  info "Pods in namespace '${TARGET_NAMESPACE}':"
  kubectl get pods -n "${TARGET_NAMESPACE}" $(kubectl_args)

  # ---- Helm releases ----
  info "Helm releases (all namespaces):"
  helm list --all-namespaces

  info "Healthcheck complete."
}

# ---------------------------------------------------------------------------
# COMMAND: teardown
# Removes Helm repos added during setup and optionally deletes manifests.
# Does NOT delete the cluster itself — manage that via the lima/ directory.
# ---------------------------------------------------------------------------
cmd_teardown() {
  warn "Teardown will remove Helm repos and uninstall tracked releases."

  if [[ "${AUTO_APPROVE:-false}" != "true" ]]; then
    read -r "confirm?Type 'yes' to confirm: "
    if [[ "${confirm}" != "yes" ]]; then
      info "Teardown cancelled."
      exit 0
    fi
  fi

  require helm
  require kubectl

  # Remove repos added during setup (helm repo remove is a no-op if absent).
  info "Removing Helm repos..."
  helm repo remove ingress-nginx 2>/dev/null || true
  helm repo remove jetstack       2>/dev/null || true
  helm repo remove metrics-server 2>/dev/null || true

  info "Teardown complete. Cluster resources (pods, services) were NOT deleted."
  info "To delete namespace resources, run: kubectl delete -f ${ROOT_DIR}/manifests/"
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
      print "  setup       Install k9s skin, init Helm repos, apply manifests"
      print "  healthcheck Verify cluster health and list releases"
      print "  teardown    Remove Helm repos (cluster NOT deleted)"
      print ""
      print "Toggles:"
      print "  ENABLE_LOGGING=true        Verbose output"
      print "  KUBE_CONTEXT=<ctx>         Target a specific kubectl context"
      print "  TARGET_NAMESPACE=<ns>      Namespace for health checks (default: default)"
      print "  SKIP_HELM_REPOS=true       Skip Helm repo additions"
      print "  AUTO_APPROVE=true          Skip teardown confirmation"
      exit 1
      ;;
  esac
}

main "$@"
