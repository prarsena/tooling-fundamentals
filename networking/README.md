# Networking

A complete local and remote networking toolkit: TLS certificate management (`step-ca`, `mkcert`), local HTTPS proxy (`caddy`), tunneling (`ngrok`, `cloudflared`), mesh VPN (`Tailscale`), DNS diagnostics (`doggo`), visual ping/traceroute (`gping`, `trippy`), bandwidth monitoring (`bandwhich`), and packet capture (`termshark`).

---

## Role in This Stack

Production services require valid TLS. `step-ca` provides a full local Certificate Authority; `mkcert` is the ergonomic quick-path for one-off dev certs. `caddy` acts as a zero-config local HTTPS reverse proxy in front of your Lima VMs and containers. When you need to expose a local port to the outside world (webhooks, demos, mobile testing), `ngrok` and `cloudflared` offer two complementary tunneling models. Tailscale provides a persistent mesh VPN across all your machines. `doggo`, `gping`, `trippy`, `bandwhich`, and `termshark` form a modern diagnostic suite that replaces `dig`, `ping`, `mtr`, `nethogs`, and Wireshark GUI respectively.

---

## Prerequisites

**TLS & Local Proxy**

| Requirement | Install | Notes |
|-------------|---------|-------|
| `step` CLI | `brew install step` | Certificate management (`step-ca` client) |
| `step-ca` | `brew install step-ca` | Full local Certificate Authority server |
| `mkcert` | `brew install mkcert` | Zero-config local TLS cert generation |
| `caddy` | `brew install caddy` | Local HTTPS reverse proxy with auto-certs |

**Tunneling & VPN**

| Requirement | Install | Notes |
|-------------|---------|-------|
| `ngrok` | `brew install ngrok/ngrok/ngrok` | Expose localhost via secure tunnels |
| `cloudflared` | `brew install cloudflared` | Cloudflare Tunnel + DNS-over-HTTPS proxy |
| `tailscale` | `brew install tailscale` | Mesh VPN with point-to-point encryption |

**Diagnostics**

| Requirement | Install | Notes |
|-------------|---------|-------|
| `doggo` | `brew install doggo` | Modern human-readable DNS client |
| `gping` | `brew install gping` | Graph-based visual ping |
| `trippy` | `brew install trippy` | Combined ping + traceroute TUI |
| `bandwhich` | `brew install bandwhich` | Real-time bandwidth by process/connection |
| `termshark` | `brew install termshark` | Terminal UI for Wireshark packet capture |

---

## Directory Structure

```
networking/
├── README.md
├── scripts/
│   └── manage.sh                  # Lifecycle: setup, healthcheck, teardown
└── configs/
    ├── step-ca-template.json      # Certificate template for step-ca
    ├── tailscale-acl.hujson       # Tailscale ACL policy
    ├── Caddyfile                  # Local HTTPS reverse proxy config
    └── cloudflared-config.yaml   # Cloudflare Tunnel config
```

---

## Common Recipes

**TLS & Certificates**

| Task | Command |
|------|---------|
| Initialise a local CA | `step ca init` |
| Start the CA server | `step-ca $(step path)/config/ca.json` |
| Issue a TLS cert (step-ca) | `step ca certificate myapp.local myapp.crt myapp.key` |
| Quick dev cert (mkcert) | `mkcert myapp.local localhost 127.0.0.1` |
| Inspect a certificate | `step certificate inspect myapp.crt` |
| Check cert expiry | `step certificate inspect --format json myapp.crt \| jq .validity` |
| Renew a cert | `step ca renew myapp.crt myapp.key` |
| Install mkcert root CA | `mkcert -install` |

**Local HTTPS Proxy (Caddy)**

| Task | Command |
|------|---------|
| Start Caddy with Caddyfile | `caddy run --config configs/Caddyfile` |
| Reload config live | `caddy reload --config configs/Caddyfile` |
| Reverse proxy one liner | `caddy reverse-proxy --from :443 --to localhost:8080` |
| Serve static files over HTTPS | `caddy file-server --listen :443 --root ./public` |
| Validate Caddyfile syntax | `caddy validate --config configs/Caddyfile` |

**Tunneling**

| Task | Command |
|------|---------|
| Tunnel port 8080 (ngrok) | `ngrok http 8080` |
| Named ngrok tunnel | `ngrok http --domain=myapp.ngrok-free.app 8080` |
| TCP tunnel (ngrok) | `ngrok tcp 5432` |
| Inspect ngrok traffic | `open http://127.0.0.1:4040` (ngrok dashboard) |
| Cloudflare quick tunnel | `cloudflared tunnel --url http://localhost:8080` |
| Start named CF tunnel | `cloudflared tunnel run <tunnel-name>` |
| Tailscale up | `sudo tailscale up` |
| Tailscale funnel (HTTPS) | `tailscale funnel 443` |
| Check Tailscale status | `tailscale status` |

**Diagnostics**

| Task | Command |
|------|---------|
| DNS lookup (doggo) | `doggo example.com` |
| DNS over HTTPS | `doggo example.com @https://1.1.1.1/dns-query` |
| Reverse DNS | `doggo -t PTR 8.8.8.8` |
| Visual ping (gping) | `gping 1.1.1.1 8.8.8.8` |
| Visual traceroute (trippy) | `sudo trip example.com` |
| Bandwidth by process | `sudo bandwhich` |
| Packet capture TUI | `sudo termshark -i en0` |
| Capture to file (tcpdump) | `sudo tcpdump -i en0 -w capture.pcap` |

---

## Tool Guides

### step-ca Quick Start

```zsh
# 1. Initialise a new CA (run once — stores state in $(step path)/)
step ca init \
  --name="Local Dev CA" \
  --dns="localhost,127.0.0.1" \
  --address="127.0.0.1:9000" \
  --provisioner="admin@local"

# 2. Start the CA (background process)
step-ca $(step path)/config/ca.json &

# 3. Trust the CA root on macOS (adds to System Keychain)
step certificate install $(step path)/certs/root_ca.crt

# 4. Issue a cert valid for 'myapp.local'
step ca certificate myapp.local myapp.crt myapp.key \
  --ca-url https://localhost:9000 \
  --root $(step path)/certs/root_ca.crt
```

The `manage.sh setup` command automates steps 1–3.

---

### mkcert — Quick Local TLS

`mkcert` is the ergonomic fast path when you need a local cert in under 10 seconds and don't need the full CA management that `step-ca` provides.

```zsh
# Install the mkcert root CA into the macOS System Keychain + NSS stores
# This is the equivalent of step certificate install but fully automated.
mkcert -install

# Generate a cert valid for multiple names in one command
# Creates myapp.local+2.pem and myapp.local+2-key.pem in the current directory
mkcert myapp.local localhost 127.0.0.1 ::1

# Find where mkcert stores its CA root (macOS: ~/Library/Application Support/mkcert/)
mkcert -CAROOT
```

> Choose **step-ca** when you need certificate lifecycle management (issuance, renewal, revocation) across multiple services. Choose **mkcert** when you just need a quick `.pem` pair for a single local project.

---

### Caddy — Local HTTPS Reverse Proxy

Caddy eliminates the boilerplate of nginx/HAProxy configs for local development. It automatically handles TLS negotiation using the certs you supply (or via ACME for public domains).

```zsh
# Reverse proxy myapp.local → localhost:8080 using a step-ca or mkcert cert
caddy run --config configs/Caddyfile

# One-liner: instant TLS reverse proxy (Caddy auto-provisions a self-signed cert)
caddy reverse-proxy --from https://myapp.local:443 --to http://localhost:8080

# Reload without downtime after editing the Caddyfile
caddy reload --config configs/Caddyfile
```

---

### ngrok — Secure Local Tunnels

```zsh
# Authenticate (one-time; token stored in ~/Library/Application Support/ngrok/)
ngrok config add-authtoken <YOUR_TOKEN>

# Expose a local HTTP server to the internet with a random ngrok URL
ngrok http 8080

# Use a persistent custom domain (requires ngrok paid plan)
ngrok http --domain=myapp.ngrok-free.app 8080

# Open the local inspector dashboard to view/replay requests
open http://127.0.0.1:4040

# TCP tunnel (e.g. PostgreSQL, SSH)
ngrok tcp 5432
```

---

### cloudflared — Cloudflare Tunnel

`cloudflared` complements ngrok: free persistent subdomains under `*.trycloudflare.com`, Cloudflare ACL/WAF on top, and a DNS-over-HTTPS (DoH) proxy for your local resolver.

```zsh
# Quick tunnel — no account needed, ephemeral URL
cloudflared tunnel --url http://localhost:8080

# Named persistent tunnel (requires a Cloudflare account + domain)
cloudflared tunnel login
cloudflared tunnel create myapp
cloudflared tunnel route dns myapp myapp.example.com
cloudflared tunnel run myapp

# Run as a local DNS-over-HTTPS proxy on port 5053
# Then point your macOS resolver at 127.0.0.1:5053
cloudflared proxy-dns --port 5053 --upstream https://1.1.1.1/dns-query
```

---

### Diagnostics Quick Reference

```zsh
# trippy: interactive ping + traceroute TUI (replaces mtr)
# Requires sudo on macOS to open raw sockets
sudo trip example.com
sudo trip --protocol tcp --port 443 example.com   # TCP ping

# bandwhich: real-time bandwidth breakdown by process and remote address
# Requires sudo for packet capture on macOS
sudo bandwhich

# termshark: terminal Wireshark UI
# -i en0: WiFi interface. Use `networksetup -listallhardwareports` to list interfaces.
sudo termshark -i en0
sudo termshark -i en0 'tcp port 443'              # BPF filter
```

---

## macOS Notes

- **step-ca**: data directory is `$(step path)` — defaults to `~/.step/` but the `manage.sh` script overrides it to `~/Library/Application Support/step/` (Time Machine-backed, macOS-standard location).
- **step / mkcert**: both use `security add-trusted-cert` to install their root CA into the macOS System Keychain. This is fundamentally different from Linux's `update-ca-certificates` and requires `sudo` because it modifies the system-wide trust store.
- **mkcert**: stores its CA root at `$(mkcert -CAROOT)` — on macOS this resolves to `~/Library/Application Support/mkcert/`. It also installs into the Firefox NSS database if Firefox is present, which `step certificate install` does not.
- **Caddy**: on macOS, `caddy run` does not install a launchd plist automatically. For a persistent background service use `sudo caddy run --config /path/to/Caddyfile` or `brew services start caddy` (for the Homebrew-managed Caddyfile at `/opt/homebrew/etc/Caddyfile`). The `manage.sh` uses the project-local Caddyfile to avoid touching system paths.
- **ngrok**: config and auth token are stored at `~/Library/Application Support/ngrok/ngrok.yml` on macOS (not `~/.ngrok2/` as on Linux). The `manage.sh setup` checks this path when verifying configuration.
- **cloudflared**: named tunnel credentials are stored at `~/.cloudflared/`. There is no difference between macOS and Linux for this path. `cloudflared` also integrates with macOS launchd via `cloudflared service install` for persistent tunnel daemons.
- **bandwhich / termshark / trippy**: all three require raw socket access. On macOS this means `sudo` — unlike Linux where you can grant `CAP_NET_RAW` to a binary. This is a kernel-level restriction and cannot be bypassed without disabling SIP. Use `networksetup -listallhardwareports` to identify the correct interface name (`en0` = WiFi, `en1` = Ethernet, `utun0` = Tailscale).
- **Tailscale**: requires a System Extension on macOS. The CLI (`brew install tailscale`) installs the daemon only; the full menubar app is available on the App Store. Both share the same `tailscale` socket.
