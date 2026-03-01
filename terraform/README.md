# Terraform / OpenTofu

Infrastructure as Code (IaC) for provisioning cloud and local resources declaratively. This directory uses [OpenTofu](https://opentofu.org) — the open-source Terraform fork — but is fully compatible with Terraform CLI.

---

## Role in This Stack

Terraform defines **what** infrastructure should exist. It provisions cloud VMs, networking rules, DNS records, and managed services. Lima VMs and containers are for local development; Terraform is for staging/production parity and anything cloud-facing.

---

## Prerequisites

| Requirement | Install | Notes |
|-------------|---------|-------|
| OpenTofu ≥ 1.7 | `brew install opentofu` | Or `brew install terraform` for HashiCorp build |
| AWS / GCP / Azure CLI | Provider-specific | Only needed for the target provider |
| `jq` | `brew install jq` | Used to parse `terraform output -json` |
| `sops` + `age` | `brew install sops age` | Encrypting `terraform.tfvars` secrets |

Verify your installation:

```zsh
tofu version
# OpenTofu v1.x.x
# on darwin_arm64
```

---

## Directory Structure

```
terraform/
├── README.md
├── scripts/
│   └── manage.sh          # Lifecycle script: setup, plan, apply, teardown
├── modules/               # Reusable resource definitions
│   └── example-vm/        # Example: provision a Lima-compatible VM
│       ├── main.tf
│       ├── variables.tf
│       └── outputs.tf
└── supporting_files/
    ├── main.tf            # Root module boilerplate
    ├── variables.tf       # Input variable declarations
    ├── outputs.tf         # Output value declarations
    └── .terraform.lock.hcl.gitkeep
```

---

## Common Recipes

| Task | Command |
|------|---------|
| Initialise working directory | `./scripts/manage.sh setup` |
| Preview changes | `./scripts/manage.sh plan` |
| Apply changes | `./scripts/manage.sh apply` |
| Destroy all resources | `./scripts/manage.sh teardown` |
| Format all `.tf` files | `tofu fmt -recursive .` |
| Validate configuration | `tofu validate` |
| Show current state | `tofu state list` |
| Unlock a stuck state | `tofu force-unlock <LOCK_ID>` |
| Parse JSON output | `tofu output -json \| jq .` |
| Encrypt tfvars with SOPS | `sops -e terraform.tfvars > terraform.tfvars.enc` |

---

## State Management

By default, Terraform state is stored locally in `terraform.tfstate`. For team use, configure a remote backend. Example S3 backend (add to `supporting_files/main.tf`):

```hcl
terraform {
  backend "s3" {
    bucket = "my-tfstate-bucket"
    key    = "global/s3/terraform.tfstate"
    region = "us-east-1"
  }
}
```

> **Never commit `terraform.tfstate` or `*.tfvars` files to Git.** The `.gitignore` in this directory excludes them.

---

## Usage Examples

```zsh
# Run a dry-run plan with verbose logging enabled
ENABLE_LOGGING=true DRY_RUN=true ./scripts/manage.sh plan

# Apply using a specific var file
TF_VAR_FILE=staging.tfvars ./scripts/manage.sh apply

# Health check: verify provider authentication
./scripts/manage.sh healthcheck
```

---

## macOS Notes

- Terraform's plugin cache lives at `~/Library/Caches/io.terraform/` (macOS) rather than `~/.terraform.d/plugin-cache/` (Linux default). The `manage.sh` script sets `TF_PLUGIN_CACHE_DIR` accordingly.
- On Apple Silicon, always verify provider binaries are `darwin_arm64` — most major providers now ship universal or ARM binaries.
