# Salt (SaltStack)

Event-driven configuration management and remote execution. Salt uses a **master/minion** model where the Salt Master pushes state to Minions, or a **masterless** (`salt-call --local`) mode for standalone execution — ideal for local macOS development with Lima VMs. Configuration is expressed in **States** (YAML + Jinja2) organised into **Formulas**.

---

## Role in This Stack

Salt's standout feature over Ansible is its **event bus** (the Salt Reactor and Beacon system) — nodes can respond to real-time events (file changes, process deaths, custom metrics) and self-heal. For local development, masterless `salt-call` lets you test states against Lima VMs without any Salt Master. The same state files run identically in a full master/minion deployment.

---

## Prerequisites

| Requirement | Install | Notes |
|-------------|---------|-------|
| Salt | `brew install salt` | Installs `salt`, `salt-call`, `salt-ssh` |
| `salt-ssh` | Included with salt | Agentless execution (no minion needed) |
| Python ≥ 3.11 | `brew install python` | Salt's runtime; Homebrew manages it |

Verify:

```zsh
salt --version
# salt 3007.x (Chlorine)
salt-call --version
# salt-call 3007.x
```

---

## Directory Structure

```
salt/
├── README.md
├── scripts/
│   └── manage.sh              # Lifecycle: setup, healthcheck, teardown
├── supporting_files/
│   ├── minion               # Masterless minion config (for salt-call --local)
│   └── roster               # salt-ssh target inventory
└── states/
    ├── top.sls              # Top file: maps minions to states
    └── baseline/
        ├── init.sls         # Baseline state: packages, users, SSH config
        └── files/
            └── sshd_config  # Managed SSH daemon config file
```

---

## Common Recipes

| Task | Command |
|------|---------|
| Apply all states (local) | `salt-call --local state.apply` |
| Apply one state (local) | `salt-call --local state.apply baseline` |
| Dry-run (test mode) | `salt-call --local state.apply test=True` |
| Show state diff | `salt-call --local state.apply baseline --state-output=changes` |
| Run a remote command | `salt '*' cmd.run 'uname -a'` |
| Apply via salt-ssh | `salt-ssh '*' state.apply` |
| Check minion connectivity | `salt '*' test.ping` |
| List active minions | `salt-run manage.up` |
| Install a package | `salt-call --local pkg.install curl` |
| Refresh package index | `salt-call --local pkg.refresh_db` |
| Show grains (node facts) | `salt-call --local grains.items` |
| Show a specific grain | `salt-call --local grains.get os` |
| Encrypt a pillar secret | See Pillar + GPG section below |

---

## Masterless Quick Start

```zsh
# Apply states locally (no Salt Master required)
# Uses supporting_files/minion as the config file
sudo salt-call --local \
  --config-dir=supporting_files \
  state.apply \
  test=True    # Remove test=True to apply for real
```

---

## salt-ssh Quick Start (Agentless, no Minion installation)

```zsh
# Apply states to a Lima VM via SSH — no minion daemon required
salt-ssh \
  --roster-file=supporting_files/roster \
  '*' \
  state.apply baseline \
  -i    # -i: accept new host keys (dev only)
```

---

## Pillar (Secrets)

Pillar data is the Salt equivalent of Ansible Vault — encrypted, per-minion variables:

```zsh
# Create pillar directory structure
mkdir -p pillar/base
cat > pillar/top.sls <<'EOF'
base:
  '*':
    - secrets
EOF

# Encrypt a value with GPG (requires a GPG key)
cat > pillar/base/secrets.sls <<'EOF'
db_password: |
  -----BEGIN PGP MESSAGE-----
  ... (encrypted with `gpg --encrypt`)
  -----END PGP MESSAGE-----
EOF
```

---

## Usage Examples

```zsh
# Setup: install salt, configure masterless minion
./scripts/manage.sh setup

# Apply states with test mode (dry-run)
DRY_RUN=true ./scripts/manage.sh apply

# Health check: test.ping + state.show_top
./scripts/manage.sh healthcheck

# Teardown: remove salt cache and PKI state
./scripts/manage.sh teardown
```

---

## macOS Notes

- Salt installed via Homebrew runs as your normal user. On macOS, `salt-call --local` writes its cache and PKI keys to `/var/cache/salt/` by default — this requires `sudo`. Set `cachedir` and `pki_dir` in the minion config to `~/Library/Caches/salt/` instead (configured in `supporting_files/minion`).
- `salt-call` uses Python's `ctypes` to interface with macOS APIs for certain execution modules. Always use Homebrew Python (not the system `/usr/bin/python3`) to avoid SIP (System Integrity Protection) restrictions.
- The macOS firewall may block the default Salt Master ports (4505/4506) for the ZeroMQ transport. For local-only development, masterless mode (`--local`) avoids all port requirements.
- `salt-ssh` uses `~/.ssh/` key management and respects `~/.ssh/config` — the same config used by Lima VMs.
