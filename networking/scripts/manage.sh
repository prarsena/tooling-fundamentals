#!/usr/bin/env zsh
# =============================================================================
# networking/scripts/manage.sh
# Lifecycle manager for the full networking toolkit on macOS.
# Covers: step-ca (local CA), mkcert (quick TLS), caddy (local HTTPS proxy),
#         ngrok (tunnels), cloudflared (Cloudflare Tunnel + DoH),
#         tailscale (mesh VPN), doggo (DNS), gping, trippy, bandwhich, termshark.
#
# Usage:
#   ./manage.sh <command>
#   ENABLE_LOGGING=true STEP_DNS=myapp.local ./manage.sh setup
#
# Commands: setup | healthcheck | teardown
# =============================================================================

set -euo pipefail

# ---------------------------------------------------------------------------
# ENVIRONMENT VARIABLE TOGGLES
# ---------------------------------------------------------------------------

ENABLE_LOGGING="${ENABLE_LOGGING:-false}"

# The CA display name (used during `step ca init`).
STEP_CA_NAME="${STEP_CA_NAME:-Local Dev CA}"

# DNS names the CA certificate will be valid for.
STEP_DNS="${STEP_DNS:-localhost,127.0.0.1}"

# Address the step-ca server listens on.
STEP_CA_ADDRESS="${STEP_CA_ADDRESS:-127.0.0.1:9000}"

# step-ca provisioner name (typically an email address).
STEP_PROVISIONER="${STEP_PROVISIONER:-admin@local}"

# When true, skip the System Keychain trust step (requires sudo).
SKIP_KEYCHAIN_TRUST="${SKIP_KEYCHAIN_TRUST:-false}"

# When true, skip running mkcert -install (requires sudo on some systems).
SKIP_MKCERT_INSTALL="${SKIP_MKCERT_INSTALL:-false}"

# ngrok auth token. Retrieve from https://dashboard.ngrok.com/get-started/your-authtoken
# Set this before running setup to configure ngrok automatically.
NGROK_AUTHTOKEN="${NGROK_AUTHTOKEN:-}"

# Caddy config file to validate/start. Defaults to the project-local Caddyfile.
CADDY_CONFIG="${CADDY_CONFIG:-${0:A:h:h}/configs/Caddyfile}"

# ---------------------------------------------------------------------------
# macOS-SPECIFIC PATHS
# On macOS we override STEPPATH to ~/Library/Application Support/step/
# This keeps step-ca data in the OS-standard location rather than ~/.step/
# which is the default on Linux. Both work; the Library path is preferred
# on macOS because it is backed up by Time Machine by default.
#
# ngrok stores its config at ~/Library/Application Support/ngrok/ngrok.yml
# on macOS — NOT at ~/.ngrok2/ as on Linux.
#
# mkcert stores its CA root at ~/Library/Application Support/mkcert/ on macOS.
# ---------------------------------------------------------------------------
export STEPPATH="${STEPPATH:-${HOME}/Library/Application Support/step}"

NGROK_CONFIG_DIR="${HOME}/Library/Application Support/ngrok"
MKCERT_CAROOT="${HOME}/Library/Application Support/mkcert"

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
# Initialises step-ca and optionally trusts the root cert on macOS.
# ---------------------------------------------------------------------------
cmd_setup() {
  info "Running networking setup..."
  require step
  require "step-ca"

  # ---- Create STEPPATH directory ----
  # ~/Library/Application Support/ is standard on macOS for per-user data.
  # It is created by the OS on first login; we create the sub-directory.
  log "Creating STEPPATH: ${STEPPATH}"
  mkdir -p "${STEPPATH}"

  # ---- Initialise CA (idempotent: skip if config already exists) ----
  local ca_config="${STEPPATH}/config/ca.json"

  if [[ -f "${ca_config}" ]]; then
    info "CA already initialised at ${ca_config} — skipping init."
  else
    info "Initialising step-ca..."
    log "CA name: ${STEP_CA_NAME}"
    log "DNS:     ${STEP_DNS}"
    log "Address: ${STEP_CA_ADDRESS}"

    # `step ca init` creates the CA key pair, root certificate, and config.
    # --name:        Human-readable name embedded in the root cert CN.
    # --dns:         SANs for the intermediate CA's own TLS certificate.
    # --address:     The host:port step-ca will listen on.
    # --provisioner: Email used for the initial JWK provisioner.
    # --password-file: Omitted here so the user is prompted interactively.
    step ca init \
      --name="${STEP_CA_NAME}" \
      --dns="${STEP_DNS}" \
      --address="${STEP_CA_ADDRESS}" \
      --provisioner="${STEP_PROVISIONER}" \
      --deployment-type="standalone"

    info "CA initialised."
  fi

  # ---- Copy custom certificate template if provided ----
  local template_src="${ROOT_DIR}/configs/step-ca-template.json"
  local template_dst="${STEPPATH}/templates/cert-template.json"

  if [[ -f "${template_src}" ]]; then
    mkdir -p "${STEPPATH}/templates"
    cp "${template_src}" "${template_dst}"
    info "Certificate template installed at: ${template_dst}"
  fi

  # ---- Trust the root CA on macOS ----
  # On macOS, `security add-trusted-cert` adds the cert to the System Keychain
  # so all macOS apps (Safari, curl, Node.js via SecureTransport) trust it.
  # This is fundamentally different from Linux's `update-ca-certificates`.
  # Requires sudo because it modifies the system-wide trust store.
  if [[ "${SKIP_KEYCHAIN_TRUST}" != "true" ]]; then
    local root_cert="${STEPPATH}/certs/root_ca.crt"
    if [[ -f "${root_cert}" ]]; then
      info "Trusting root CA in macOS System Keychain (requires sudo)..."
      # `step certificate install` wraps `security add-trusted-cert -d -r trustRoot`
      step certificate install "${root_cert}" || \
        warn "Could not install CA cert. Run manually: sudo security add-trusted-cert -d -r trustRoot -k /Library/Keychains/System.keychain ${root_cert}"
    else
      warn "Root cert not found at ${root_cert}"
    fi
  fi

  info "Setup complete."
  info "Start the CA with: step-ca \"\${STEPPATH}/config/ca.json\""
  info "Issue a cert with:  step ca certificate <domain> cert.pem key.pem --ca-url https://${STEP_CA_ADDRESS}"

  # ---- mkcert: install root CA ----
  # mkcert -install registers its self-generated root CA in:
  #   macOS System Keychain  (via security add-trusted-cert)
  #   Firefox NSS db         (if Firefox is installed)
  # This is a one-time operation; subsequent `mkcert <domain>` calls are instant.
  if command -v mkcert &>/dev/null; then
    if [[ "${SKIP_MKCERT_INSTALL}" != "true" ]]; then
      info "Installing mkcert root CA into System Keychain..."
      mkcert -install || warn "mkcert -install failed — may require sudo or Firefox NSS tools."
      info "mkcert CA root: $(mkcert -CAROOT)"
    else
      warn "SKIP_MKCERT_INSTALL=true — skipping mkcert -install."
    fi
  else
    warn "mkcert not installed. Run: brew install mkcert"
  fi

  # ---- Caddy: validate config ----
  # `caddy validate` parses the Caddyfile and reports any syntax or module
  # errors without starting the server. Safe to run at any time.
  if command -v caddy &>/dev/null; then
    if [[ -f "${CADDY_CONFIG}" ]]; then
      info "Validating Caddyfile: ${CADDY_CONFIG}"
      caddy validate --config "${CADDY_CONFIG}" && \
        info "Caddyfile is valid." || \
        warn "Caddyfile has errors — review above."
    else
      warn "Caddyfile not found at ${CADDY_CONFIG} — skipping validation."
    fi
  else
    warn "caddy not installed. Run: brew install caddy"
  fi

  # ---- ngrok: configure auth token ----
  # ngrok stores its config at ~/Library/Application Support/ngrok/ngrok.yml
  # on macOS. Running `ngrok config add-authtoken` writes the token there.
  if command -v ngrok &>/dev/null; then
    if [[ -n "${NGROK_AUTHTOKEN}" ]]; then
      info "Configuring ngrok auth token..."
      ngrok config add-authtoken "${NGROK_AUTHTOKEN}"
      info "ngrok configured at: ${NGROK_CONFIG_DIR}/ngrok.yml"
    else
      local ngrok_cfg="${NGROK_CONFIG_DIR}/ngrok.yml"
      if [[ -f "${ngrok_cfg}" ]]; then
        info "ngrok already configured at: ${ngrok_cfg}"
      else
        warn "ngrok not configured. Set NGROK_AUTHTOKEN=<token> and re-run setup,"
        warn "or run: ngrok config add-authtoken <token>"
        warn "Get your token at: https://dashboard.ngrok.com/get-started/your-authtoken"
      fi
    fi
  else
    warn "ngrok not installed. Run: brew install ngrok/ngrok/ngrok"
  fi

  # ---- cloudflared: check login ----
  if command -v cloudflared &>/dev/null; then
    info "cloudflared version: $(cloudflared --version 2>&1 | head -1)"
    info "For named tunnels, run: cloudflared tunnel login"
    info "For a quick ephemeral tunnel (no login): cloudflared tunnel --url http://localhost:8080"
  else
    warn "cloudflared not installed. Run: brew install cloudflared"
  fi
}

# ---------------------------------------------------------------------------
# COMMAND: healthcheck
# Checks tool availability, CA status, and runs diagnostic tools.
# ---------------------------------------------------------------------------
cmd_healthcheck() {
  info "Running networking healthcheck..."

  # ---- Tool inventory ----
  # Iterate over all tools in the stack and report install status + version.
  # `2>/dev/null` suppresses stderr from version flags that print to stderr.
  info "Tool inventory:"
  local tools=(
    "step"         "step version"
    "step-ca"      "step-ca version"
    "mkcert"       "mkcert --version"
    "caddy"        "caddy version"
    "ngrok"        "ngrok version"
    "cloudflared"  "cloudflared --version"
    "tailscale"    "tailscale version"
    "doggo"        "doggo version"
    "gping"        "gping --version"
    "trippy"       "trip --version"
    "bandwhich"    "bandwhich --version"
    "termshark"    "termshark --version"
  )

  # Iterate pairwise: tool name + version command
  for (( i=1; i<${#tools[@]}; i+=2 )); do
    local tool="${tools[$i]}"
    local ver_cmd="${tools[$((i+1))]}"
    if command -v "${tool}" &>/dev/null; then
      local ver
      ver=$(eval "${ver_cmd}" 2>/dev/null | head -1 || echo 'installed')
      info "  ${tool}: ${ver}"
    else
      warn "  ${tool}: NOT installed"
    fi
  done

  # ---- step-ca server check ----
  local ca_url="https://${STEP_CA_ADDRESS}"
  info "Checking step-ca at ${ca_url}..."
  # `step ca health` hits the /health endpoint; exits non-zero if unreachable.
  if step ca health --ca-url "${ca_url}" --root "${STEPPATH}/certs/root_ca.crt" 2>/dev/null; then
    info "step-ca is running and healthy."
  else
    warn "step-ca is not running. Start with: step-ca \"\${STEPPATH}/config/ca.json\""
  fi

  # ---- mkcert CA root check ----
  if command -v mkcert &>/dev/null; then
    local caroot
    caroot=$(mkcert -CAROOT 2>/dev/null)
    if [[ -f "${caroot}/rootCA.pem" ]]; then
      info "mkcert CA root: ${caroot}/rootCA.pem"
    else
      warn "mkcert CA not initialised. Run: mkcert -install"
    fi
  fi

  # ---- Caddy config validation ----
  if command -v caddy &>/dev/null && [[ -f "${CADDY_CONFIG}" ]]; then
    info "Validating Caddyfile..."
    caddy validate --config "${CADDY_CONFIG}" && \
      info "Caddyfile is valid." || warn "Caddyfile errors found."
  fi

  # ---- ngrok connectivity check ----
  if command -v ngrok &>/dev/null; then
    # `ngrok diagnose` tests connectivity to the ngrok API and tunnel servers.
    # --log=false suppresses the JSON log output for cleaner terminal output.
    info "Running ngrok connectivity diagnosis..."
    ngrok diagnose --log=false 2>/dev/null || \
      warn "ngrok diagnose failed — check authtoken and internet connectivity."
  fi

  # ---- cloudflared tunnel list ----
  if command -v cloudflared &>/dev/null; then
    info "Cloudflare tunnels:"
    cloudflared tunnel list 2>/dev/null || \
      warn "cloudflared tunnel list failed — run 'cloudflared tunnel login' first."
  fi

  # ---- DNS check via doggo ----
  if command -v doggo &>/dev/null; then
    info "DNS check (doggo) for example.com:"
    # doggo uses human-readable coloured output by default.
    # On macOS, `dig` is the BSD version; doggo is a modern alternative.
    doggo example.com || warn "doggo DNS check failed."
  fi

  # ---- Tailscale status ----
  if command -v tailscale &>/dev/null; then
    info "Tailscale status:"
    tailscale status || warn "Tailscale is not running."
  fi

  info "Healthcheck complete."
}

# ---------------------------------------------------------------------------
# COMMAND: teardown
# Stops the CA server and optionally removes the trusted root from Keychain.
# The CA data directory (STEPPATH) is NOT deleted to preserve key material.
# ---------------------------------------------------------------------------
cmd_teardown() {
  warn "Teardown will remove the CA root from the System Keychain."
  warn "CA data at ${STEPPATH} will NOT be deleted."

  if [[ "${AUTO_APPROVE:-false}" != "true" ]]; then
    read -r "confirm?Type 'yes' to confirm: "
    if [[ "${confirm}" != "yes" ]]; then
      info "Teardown cancelled."
      exit 0
    fi
  fi

  # Remove the root CA from the macOS System Keychain.
  # `step certificate uninstall` wraps `security remove-trusted-cert`.
  local root_cert="${STEPPATH}/certs/root_ca.crt"
  if [[ -f "${root_cert}" ]]; then
    info "Removing step-ca trust from macOS System Keychain (requires sudo)..."
    step certificate uninstall "${root_cert}" || \
      warn "Could not remove CA trust — may already be removed."
  else
    warn "Root cert not found at ${root_cert} — skipping keychain removal."
  fi

  # Remove mkcert root CA from the System Keychain.
  # `mkcert -uninstall` removes the root cert from System Keychain and NSS stores.
  if command -v mkcert &>/dev/null; then
    info "Removing mkcert root CA from System Keychain..."
    mkcert -uninstall || warn "mkcert -uninstall failed — may already be removed."
  fi

  # Stop any running Caddy instance started from this project's Caddyfile.
  # `pkill` on macOS uses BSD semantics — `-f` matches the full argument list.
  if pgrep -f "caddy run" &>/dev/null; then
    info "Stopping Caddy..."
    pkill -f "caddy run" || warn "Could not stop Caddy."
  fi

  # Kill any running step-ca process.
  if pgrep -f "step-ca" &>/dev/null; then
    info "Stopping step-ca process..."
    pkill -f "step-ca" || warn "Could not stop step-ca."
  else
    info "No running step-ca process found."
  fi

  info "Teardown complete."
  info "ngrok and cloudflared configs were NOT removed (no credentials to revoke locally)."
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
      print "  setup       Init step-ca, install mkcert/ngrok, validate Caddyfile"
      print "  healthcheck Check all tools, CA status, DNS, tunnels, VPN"
      print "  teardown    Remove CA trust, stop step-ca and Caddy"
      print ""
      print "Toggles:"
      print "  ENABLE_LOGGING=true               Verbose output"
      print "  STEP_CA_NAME='My CA'              CA display name"
      print "  STEP_DNS='localhost,myapp.local'  DNS names for the CA"
      print "  STEP_CA_ADDRESS='127.0.0.1:9000'  CA listening address"
      print "  STEP_PROVISIONER='me@local'       Provisioner email"
      print "  SKIP_KEYCHAIN_TRUST=true          Skip System Keychain trust step"
      print "  SKIP_MKCERT_INSTALL=true          Skip mkcert -install"
      print "  NGROK_AUTHTOKEN=<token>           Configure ngrok auth token"
      print "  CADDY_CONFIG=<path>               Caddyfile path"
      print "  AUTO_APPROVE=true                 Skip teardown confirmation"
      exit 1
      ;;
  esac
}

main "$@"
