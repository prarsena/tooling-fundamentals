# Puppet

Declarative configuration management using a client-server model (Puppet Agent + Puppet Server) or agentless execution via Bolt. Infrastructure intent is expressed in **Manifests** (`.pp` files) using the Puppet DSL, organised into **Modules**. **Puppet Bolt** is the agentless runner for ad-hoc tasks and plans over SSH, ideal for local macOS development.

---

## Role in This Stack

Puppet is an enterprise-grade option for large fleets requiring an auditable, convergent configuration model. For local development, **Bolt** provides agentless task execution (similar to Ansible playbooks) without the complexity of standing up a Puppet Server. Manifests tested locally with Bolt can be applied to a full Puppet-managed fleet unchanged.

---

## Prerequisites

| Requirement | Install | Notes |
|-------------|---------|-------|
| Puppet Bolt | `brew install --cask puppet-bolt` | Agentless runner; no server required |
| `puppet-lint` | `gem install puppet-lint` | Lint Puppet manifests |
| `pdk` (Puppet Dev Kit) | `brew install --cask pdk` | Scaffolds modules, runs unit tests |
| Ruby (system) | Included with Bolt | Bolt bundles its own Ruby |

Verify:

```zsh
bolt --version
# Bolt 3.x.x
pdk --version
# pdk 3.x.x
```

> Bolt and PDK each bundle their own Ruby runtime under `/opt/puppetlabs/`. Do not mix with Homebrew or rbenv Ruby.

---

## Directory Structure

```
puppet/
├── README.md
├── scripts/
│   └── manage.sh              # Lifecycle: setup, healthcheck, teardown
├── supporting_files/
│   └── bolt-project.yaml      # Bolt project config (name, modules, transport)
└── modules/
    └── baseline/              # Starter module: baseline OS configuration
        ├── metadata.json
        ├── manifests/
        │   └── init.pp        # Main class: baseline::init
        ├── tasks/
        │   └── check.sh       # Bolt task: ad-hoc health check
        └── plans/
            └── deploy.pp      # Bolt plan: orchestrated multi-step deployment
```

---

## Common Recipes

| Task | Command |
|------|---------|
| Run a Bolt task on a host | `bolt task run facts --targets <host>` |
| Apply a manifest | `bolt apply modules/baseline/manifests/init.pp --targets <host>` |
| Run a Bolt plan | `bolt plan run baseline::deploy targets=<host>` |
| Run task locally | `bolt task run package action=status name=curl --targets localhost` |
| Lint all manifests | `puppet-lint modules/baseline/manifests/` |
| Generate a module (PDK) | `pdk new module my_module` |
| Generate a class (PDK) | `pdk new class my_module::my_class` |
| Run unit tests (PDK) | `pdk test unit` |
| Validate metadata | `pdk validate metadata` |
| Check Puppet syntax | `puppet parser validate modules/baseline/manifests/init.pp` |
| Install module from Forge | `bolt module add puppetlabs-apache` |

---

## Bolt Quick Start

```zsh
# Apply the baseline manifest to a Lima VM over SSH
bolt apply modules/baseline/manifests/init.pp \
  --targets ssh://127.0.0.1:60022 \
  --user pete \
  --private-key ~/.ssh/id_ed25519 \
  --no-host-key-check

# Run the built-in 'facts' task to inspect a remote node
bolt task run facts \
  --targets ssh://127.0.0.1:60022 \
  --user pete \
  --private-key ~/.ssh/id_ed25519

# Run a plan (multi-step orchestration)
bolt plan run baseline::deploy \
  targets=ssh://127.0.0.1:60022 \
  --project .
```

---

## Usage Examples

```zsh
# Setup: install Bolt, PDK, validate environment
./scripts/manage.sh setup

# Apply baseline manifest locally (dry-run: noop mode)
DRY_RUN=true BOLT_TARGETS=localhost ./scripts/manage.sh apply

# Health check: lint modules + run PDK unit tests
./scripts/manage.sh healthcheck

# Teardown: remove Bolt cache and temp files
./scripts/manage.sh teardown
```

---

## macOS Notes

- Puppet Bolt installs a `.pkg` via Cask to `/opt/puppetlabs/bolt/`. On Apple Silicon, Bolt 3.27+ ships arm64 binaries — check with `file /opt/puppetlabs/bolt/bin/bolt`.
- PDK also installs to `/opt/puppetlabs/pdk/`. Both are isolated Ruby environments — do **not** `sudo gem install` into them; use `bolt module add` for Forge modules instead.
- Bolt's project config (`bolt-project.yaml`) and module cache live in `~/.puppetlabs/bolt/` on macOS. This directory is used instead of `/etc/puppetlabs/` which requires root.
- `puppet-lint` via `gem install` uses the system Ruby (Homebrew-managed). Keep it separate from Bolt/PDK's bundled Ruby to avoid version conflicts.
