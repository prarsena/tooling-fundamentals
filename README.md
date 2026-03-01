# DevOps Stack — macOS Development Environment

A modular, opinionated repository for managing infrastructure, containers, virtual machines, Kubernetes clusters, networking, and macOS system configuration. Each technology lives in its own root directory with a consistent structure: a `README.md`, a `scripts/` directory, and a `supporting_files/` or equivalent directory for boilerplate.

---

## Repository Structure

```
/
├── README.md               # This file — master guide and global setup
├── container/              # OCI container recipes and tooling (Docker, Podman)
├── lima/                   # Linux VM management via Lima
├── terraform/              # Infrastructure as Code (Terraform / OpenTofu)
├── kubernetes/             # K8s cluster management (Helm, k9s)
├── networking/             # Local TLS, DNS, VPN (step-ca, Tailscale, doggo)
├── macos-base/             # macOS system baseline (Homebrew, dotfiles, defaults)
├── ansible/                # Agentless config management over SSH
├── chef/                   # Ruby-based config management (Chef Workstation)
├── puppet/                 # Declarative config management (Puppet Bolt)
└── salt/                   # Event-driven config management (salt-call / salt-ssh)
```

---

## Prerequisites

All tools are managed via [Homebrew](https://brew.sh). Install it first:

```zsh
/bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"
```

Then run the one-shot installer from `macos-base/`:

```zsh
cd macos-base/scripts && ./manage.sh setup
```

---

## Global Tool Inventory

| Tool          | Category            | Install                         | Purpose                                  |
|---------------|---------------------|---------------------------------|------------------------------------------|
| `lima`        | Virtualisation      | `brew install lima`             | Linux VMs on macOS via QEMU              |
| `docker`      | Containers          | `brew install docker`           | OCI container runtime                    |
| `terraform`   | IaC                 | `brew install opentofu`         | Declarative infrastructure provisioning  |
| `helm`        | Kubernetes          | `brew install helm`             | Kubernetes package manager               |
| `k9s`         | Kubernetes          | `brew install k9s`              | Terminal-based Kubernetes dashboard      |
| `ansible`     | Config Management   | `brew install ansible`          | Agentless VM configuration via SSH       |
| `chef`        | Config Management   | `brew install --cask chef-workstation` | Ruby-based config management (ChefZero) |
| `bolt`        | Config Management   | `brew install --cask puppet-bolt`     | Agentless Puppet runner                 |
| `salt`        | Config Management   | `brew install salt`             | Event-driven config management           |
| `step`        | Networking/TLS      | `brew install step`             | Local Certificate Authority CLI          |
| `tailscale`   | Networking/VPN      | `brew install tailscale`        | Mesh VPN and secure tunnels              |
| `doggo`       | Networking/DNS      | `brew install doggo`            | Modern human-readable DNS client         |
| `gping`       | Networking          | `brew install gping`            | Graph-based visual ping                  |
| `sops`        | Secrets             | `brew install sops`             | Encrypted secrets in Git                 |
| `age`         | Secrets             | `brew install age`              | Modern encryption tool (pairs with SOPS) |
| `jq`          | Data               | `brew install jq`               | JSON parsing and transformation          |
| `yq`          | Data               | `brew install yq`               | YAML parsing and transformation          |

---

## Workflow Philosophy

1. **Each directory is self-contained.** You can `cd` into any root directory and follow its `README.md` without reading others.
2. **Scripts use environment variable toggles.** Set `ENABLE_LOGGING=true` or `DRY_RUN=true` before running any `manage.sh` to control behaviour without editing files.
3. **Scripts are heavily commented** with macOS-specific rationale (BSD vs GNU differences, `~/Library/` paths, etc.).
4. **Secrets are never committed.** Use `networking/` for TLS, `sops`/`age` for secrets, and `.gitignore` everywhere.

---

## Quick Start

```zsh
# 1. Install all Homebrew dependencies
cd macos-base/scripts && ./manage.sh setup

# 2. Start a Lima VM
cd lima/scripts && ./vm.sh

# 3. Set up local TLS with step-ca
cd networking/scripts && ./manage.sh setup

# 4. Initialise Terraform
cd terraform/scripts && ./manage.sh setup

# 5. Connect to a Kubernetes cluster
cd kubernetes/scripts && ./manage.sh setup

# 6. Configure a Lima VM with Ansible
cd ansible/scripts && ./manage.sh setup && ./manage.sh apply

# 7. Converge a cookbook locally with Chef
cd chef/scripts && ./manage.sh setup && ./manage.sh apply

# 8. Apply a Bolt manifest with Puppet
cd puppet/scripts && BOLT_TARGETS=localhost ./manage.sh apply

# 9. Apply Salt states locally
cd salt/scripts && ./manage.sh setup && ./manage.sh apply
```

---

## Contributing

- Keep scripts idempotent (safe to run more than once).
- Add new technologies as new root-level directories following the same pattern.
- Update the table above when adding new tools.
