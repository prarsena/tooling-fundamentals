# Chef

Ruby-based configuration management using a client-server model (Chef Infra) or standalone execution (Chef Solo / `chef-client --local-mode`). Infrastructure is described as code in **Cookbooks** containing **Recipes** and **Resources**. The `knife` CLI manages nodes, data bags, and cookbook uploads.

---

## Role in This Stack

Chef shines for large fleets where nodes pull their configuration from a central Chef Infra Server. For local development, Chef Workstation + `chef-client --local-mode` (also called ChefZero) lets you test cookbooks against Lima VMs without any server. Once validated locally, the same cookbook runs identically in staging and production.

---

## Prerequisites

| Requirement | Install | Notes |
|-------------|---------|-------|
| Chef Workstation | `brew install --cask chef-workstation` | Bundles chef, knife, cookstyle, test-kitchen |
| `chef` CLI | Included in Workstation | Runs `chef generate`, `chef exec` |
| `knife` | Included in Workstation | Manages nodes + Chef Infra Server |
| `test-kitchen` | Included in Workstation | Integration test framework |
| `cookstyle` | Included in Workstation | RuboCop-based Chef linter |

Verify:

```zsh
chef --version
# Chef Workstation version: 24.x.x
knife --version
# Chef Infra Client: 18.x.x
```

> Chef Workstation ships its own Ruby and gem environment under `/opt/chef-workstation/`. Never mix it with system Ruby or `rbenv` managed Ruby.

---

## Directory Structure

```
chef/
├── README.md
├── scripts/
│   └── manage.sh              # Lifecycle: setup, healthcheck, teardown
├── supporting_files/
│   └── .chef/
│       └── knife.rb           # knife configuration (org, server URL, keys)
└── cookbooks/
    └── base/                  # Starter cookbook: baseline node configuration
        ├── metadata.rb
        ├── README.md
        ├── recipes/
        │   └── default.rb
        ├── attributes/
        │   └── default.rb
        └── test/
            └── integration/
                └── default/
                    └── default_test.rb
```

---

## Common Recipes

| Task | Command |
|------|---------|
| Generate a new cookbook | `chef generate cookbook cookbooks/my_cookbook` |
| Generate a new recipe | `chef generate recipe cookbooks/base my_recipe` |
| Run cookbook locally | `chef-client --local-mode --runlist 'recipe[base::default]'` |
| Lint a cookbook | `cookstyle cookbooks/base` |
| Run unit tests | `chef exec rspec cookbooks/base` |
| Run integration tests | `kitchen test` |
| Upload cookbook to server | `knife cookbook upload base` |
| Bootstrap a new node | `knife bootstrap <IP> -U <user> --sudo -N <node-name>` |
| List nodes | `knife node list` |
| Show node attributes | `knife node show <node-name>` |
| Encrypt a data bag | `knife data bag create secrets --secret-file .chef/encrypted_data_bag_secret` |
| Converge kitchen instance | `kitchen converge` |

---

## Local Development with ChefZero

```zsh
# Run the base cookbook locally (no server required)
cd cookbooks/base
chef-client --local-mode --runlist 'recipe[base::default]' --log_level info

# Or use test-kitchen to spin up a VM and converge
cd cookbooks/base
kitchen create    # Create the VM (uses Vagrant or Docker driver)
kitchen converge  # Apply the cookbook
kitchen verify    # Run InSpec tests
kitchen destroy   # Clean up
```

---

## Usage Examples

```zsh
# Setup: install Chef Workstation, generate starter cookbook
./scripts/manage.sh setup

# Converge base cookbook locally with dry-run (why-run mode)
DRY_RUN=true ./scripts/manage.sh apply

# Health check: lint + unit test all cookbooks
./scripts/manage.sh healthcheck

# Teardown: remove local chef-client cache and node state
./scripts/manage.sh teardown
```

---

## macOS Notes

- Chef Workstation is distributed as a macOS `.pkg` (via Cask). It installs to `/opt/chef-workstation/` — a self-contained directory with its own Ruby runtime. This avoids conflicts with Homebrew Ruby.
- On Apple Silicon, Chef Workstation 24+ ships universal binaries. Earlier versions required Rosetta 2 — verify with `file /opt/chef-workstation/bin/chef` which should show `arm64`.
- The `knife.rb` config path is `~/.chef/knife.rb` on Linux but the Workstation installer also checks `<repo>/.chef/knife.rb` — the latter is used in this directory for per-project isolation.
- `chef-client` stores its local cache in `/var/chef/` by default. On macOS this directory requires `sudo` to create. For local-mode development, override with `--file-cache-path ~/Library/Caches/chef-client/` (handled in `manage.sh`).
