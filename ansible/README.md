# Ansible

Agentless configuration management and remote execution over SSH. Ansible pushes desired state to your targets (Lima VMs, cloud instances, bare-metal servers) without installing any agent — the only requirement on the remote side is Python and an SSH daemon.

---

## Role in This Stack

Ansible fills the gap between Terraform (provisioning infra) and running services. Once Terraform creates a VM, Ansible configures it: installs packages, writes config files, creates users, and starts services. Pairing Lima VMs with Ansible lets you test playbooks locally before running them in the cloud.

---

## Prerequisites

| Requirement | Install | Notes |
|-------------|---------|-------|
| `ansible` ≥ 9 | `brew install ansible` | Includes `ansible-playbook`, `ansible-galaxy`, `ansible-vault` |
| `ansible-lint` | `brew install ansible-lint` | Lints playbooks for best-practice violations |
| Python ≥ 3.11 on targets | — | Ansible's default interpreter; must be present on managed nodes |
| SSH key pair | `ssh-keygen -t ed25519` | Passwordless SSH is strongly recommended |
| `sshpass` (optional) | `brew install sshpass` | Only needed for password-based SSH fallback |

Verify:

```zsh
ansible --version
# ansible [core 2.x.x]
# python version = 3.x.x
```

---

## Directory Structure

```
ansible/
├── README.md
├── scripts/
│   └── manage.sh              # Lifecycle: setup, healthcheck, teardown
├── supporting_files/
│   ├── ansible.cfg            # Project-level Ansible config
│   ├── inventory.ini          # Starter static inventory
│   └── site.yml               # Top-level playbook (calls child roles)
└── roles/
    └── common/                # Starter role: baseline packages + SSH hardening
        ├── tasks/
        │   └── main.yml
        ├── handlers/
        │   └── main.yml
        └── defaults/
            └── main.yml
```

---

## Common Recipes

| Task | Command |
|------|---------|
| Ping all hosts | `ansible all -i supporting_files/inventory.ini -m ping` |
| Run site playbook | `ansible-playbook supporting_files/site.yml -i supporting_files/inventory.ini` |
| Dry-run (check mode) | `ansible-playbook site.yml -i inventory.ini --check` |
| Diff changes | `ansible-playbook site.yml -i inventory.ini --diff` |
| Run on one host | `ansible-playbook site.yml -i inventory.ini --limit webserver1` |
| Run a single role | `ansible-playbook site.yml -i inventory.ini --tags common` |
| Encrypt a secret | `ansible-vault encrypt_string 'mysecret' --name 'db_password'` |
| Edit vault file | `ansible-vault edit group_vars/all/vault.yml` |
| Install a Galaxy role | `ansible-galaxy install -r requirements.yml` |
| List installed roles | `ansible-galaxy list` |
| Lint all playbooks | `ansible-lint supporting_files/site.yml` |

---

## Vault (Secrets Management)

Ansible Vault encrypts sensitive variables so they can be committed to Git:

```zsh
# Create an encrypted variables file
ansible-vault create group_vars/all/vault.yml

# Reference vault vars in a playbook
# vars_files:
#   - group_vars/all/vault.yml

# Pass vault password at runtime (or use --vault-password-file)
ansible-playbook site.yml --ask-vault-pass
```

---

## Lima VM Quickstart

```zsh
# 1. Start a Lima VM (see lima/ directory)
limactl start --name=dev template://ubuntu

# 2. Get the VM's SSH config
limactl show-ssh --format=config dev >> ~/.ssh/config

# 3. Add it to inventory
echo "[local_vms]" >> supporting_files/inventory.ini
echo "lima-dev ansible_host=127.0.0.1 ansible_port=60022 ansible_user=pete" >> supporting_files/inventory.ini

# 4. Run the common role against it
ansible-playbook supporting_files/site.yml -i supporting_files/inventory.ini --limit lima-dev
```

---

## Usage Examples

```zsh
# Setup: install ansible, lint, configure environment
./scripts/manage.sh setup

# Dry-run site playbook with verbose logging
ENABLE_LOGGING=true DRY_RUN=true ./scripts/manage.sh apply

# Health check: ping all hosts + lint all playbooks
./scripts/manage.sh healthcheck

# Teardown: uninstall ansible tooling
./scripts/manage.sh teardown
```

---

## macOS Notes

- Ansible is installed via Homebrew as a Python package. On macOS, Homebrew manages the Python interpreter used by Ansible — do not use `pip install ansible` as it can conflict with the system Python.
- macOS ships with BSD `ssh` which is fully compatible with Ansible's connection plugin. However, `ControlMaster` multiplexing (configured in `ansible.cfg`) can behave slightly differently under macOS's launchd — the control socket path is set to `/tmp/ansible-%%h-%%p-%%r` to avoid `~/Library/` path-length issues.
- `ansible-vault` uses `python-cryptography` under the hood; Homebrew's Ansible bundle includes it. If you see `cryptography` import errors, run `brew reinstall ansible`.
