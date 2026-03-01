# Kubernetes

Tools and configuration for managing Kubernetes clusters from macOS. This directory uses [Helm](https://helm.sh) for package management and [k9s](https://k9scli.io) as a keyboard-driven terminal dashboard.

---

## Role in This Stack

Kubernetes is the container orchestration layer for workloads that outgrow simple Docker Compose or Lima VMs. Helm packages those workloads into versioned, parameterisable charts. k9s provides a real-time terminal UI so you never have to chain `kubectl get/describe/logs` commands manually.

---

## Prerequisites

| Requirement | Install | Notes |
|-------------|---------|-------|
| `kubectl` | `brew install kubectl` | Kubernetes CLI; reads `~/.kube/config` |
| `helm` ≥ 3.14 | `brew install helm` | Package manager for Kubernetes |
| `k9s` | `brew install k9s` | Terminal dashboard |
| A cluster | Docker Desktop, Lima+k3s, or cloud | See below |

### Quickest local cluster (Lima + k3s)

```zsh
# Start a k3s VM via Lima (see lima/ directory)
limactl start --name=k3s template://k3s
export KUBECONFIG="${HOME}/.lima/k3s/copied-from-guest/etc/rancher/k3s/k3s.yaml"
kubectl get nodes
```

---

## Directory Structure

```
kubernetes/
├── README.md
├── scripts/
│   └── manage.sh              # Lifecycle: setup, healthcheck, teardown
├── manifests/
│   ├── namespace.yaml          # Baseline namespaces
│   └── ingress-nginx.yaml      # Placeholder ingress controller manifest
└── supporting_files/
    └── k9s-skin.yml            # k9s colour theme (Catppuccin-inspired)
```

---

## Common Recipes

| Task | Command |
|------|---------|
| Launch k9s dashboard | `k9s --context <ctx>` |
| List all Helm releases | `helm list -A` |
| Add a Helm repo | `helm repo add <name> <url> && helm repo update` |
| Install a chart | `helm install <release> <repo/chart> -f values.yaml` |
| Upgrade a release | `helm upgrade <release> <repo/chart> -f values.yaml` |
| Rollback a release | `helm rollback <release> <revision>` |
| Apply all manifests | `kubectl apply -f manifests/` |
| Watch all pods | `kubectl get pods -A -w` |
| Stream pod logs | `kubectl logs -f <pod> -n <ns>` |
| Port-forward a service | `kubectl port-forward svc/<name> 8080:80 -n <ns>` |
| Switch context | `kubectl config use-context <name>` |
| Show all contexts | `kubectl config get-contexts` |

---

## k9s Configuration

k9s stores its config and skins in `~/Library/Application Support/k9s/` on macOS (not `~/.k9s/` as on Linux). The `manage.sh setup` command installs the skin from `supporting_files/k9s-skin.yml` to the correct macOS path.

To launch k9s with the skin:

```zsh
k9s --skin catppuccin
```

Or set it as the default in `~/Library/Application Support/k9s/config.yaml`:

```yaml
k9s:
  ui:
    skin: catppuccin
```

---

## Helm Usage Examples

```zsh
# Add the ingress-nginx repo and install
helm repo add ingress-nginx https://kubernetes.github.io/ingress-nginx
helm repo update
helm install ingress-nginx ingress-nginx/ingress-nginx \
  --namespace ingress-nginx \
  --create-namespace \
  --set controller.service.type=NodePort

# Preview what a chart will render (no install)
helm template my-release ingress-nginx/ingress-nginx -f values.yaml

# Diff an upgrade before applying (requires helm-diff plugin)
helm diff upgrade ingress-nginx ingress-nginx/ingress-nginx -f values.yaml
```

---

## macOS Notes

- `kubectl` on macOS uses the system keychain for credential storage via the `gke-gcloud-auth-plugin` or similar. Run `brew install google-cloud-sdk` if using GKE.
- k9s config is under `~/Library/Application Support/k9s/` — **not** `~/.k9s/`. The `manage.sh` script handles this path automatically.
- Helm data is stored in `~/Library/Preferences/helm/` on macOS rather than `~/.config/helm/` on Linux.
