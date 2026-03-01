# Container Recipes & Cookbooks

Sample `Dockerfile`s and usage patterns for common workloads with `apple/container`.
Each recipe is in its own subdirectory with a `Dockerfile` and run instructions.

---

## Recipes

| Recipe | What it shows |
|---|---|
| [`python-webserver/`](python-webserver/) | Static file server in Python (beginner — mirrors the official tutorial) |
| [`node-api/`](node-api/) | Node.js Express REST API with volume mount for live reload |
| [`go-service/`](go-service/) | Multi-stage Go build producing a minimal scratch image |
| [`postgres/`](postgres/) | PostgreSQL with a named volume for data persistence |
| [`custom-init/`](custom-init/) | Custom `vminitd` wrapper for boot-time VM-level logic |
| [`multiplatform/`](multiplatform/) | arm64 + amd64 fat-manifest image via Rosetta |

---

## Quick Common Patterns

### Pull and run a published image

```bash
# Run something from Docker Hub
container run --rm docker.io/alpine:latest echo hello

# Run a specific architecture
container run --arch amd64 --rm ubuntu:latest uname -m
```

### Build, tag, push workflow

```bash
cd container/recipes/python-webserver
container build -t web-test:latest .
container run -d --name web --rm web-test:latest

# Tag and push to a registry
container registry login ghcr.io
container image tag web-test:latest ghcr.io/myorg/web-test:latest
container image push ghcr.io/myorg/web-test:latest
```

### Detach, exec, stop pattern

```bash
container run -d --name myapp --rm myimage:latest
container exec -it myapp /bin/sh         # poke around
container logs -f myapp                  # stream logs
container stop myapp                     # graceful stop (removes because of --rm)
```

### Persist data with a named volume

```bash
container volume create appdata --size 20G
container run -d --name app -v appdata:/var/lib/app --rm myapp:latest
container stop app
# Data survives the container — restart and data is still there:
container run -d --name app -v appdata:/var/lib/app --rm myapp:latest
```

### Multiplatform build

```bash
# Builds both arm64 and amd64 (amd64 uses Rosetta — fast on Apple Silicon)
container build --arch arm64 --arch amd64 \
    -t ghcr.io/myorg/myapp:latest .
container image push ghcr.io/myorg/myapp:latest
```

### Container-to-container networking (macOS 26+)

```bash
# Start a backend
container run -d --name backend --rm myapi:latest

# Get its IP
BACKEND_IP=$(container inspect backend | python3 -c \
    "import sys,json; d=json.load(sys.stdin); print(d[0]['networks'][0]['address'].split('/')[0])")

# Hit it from a second container
container run --rm alpine/curl curl http://$BACKEND_IP:3000/health

# Or set up DNS and use names:
sudo container system dns create test
container system property set dns.domain test
container run --rm alpine/curl curl http://backend.test:3000/health
```

### Port-forward a service to localhost

```bash
container run -d --name web -p 8080:80 --rm nginx:latest
curl http://127.0.0.1:8080
```

### Share your SSH agent

```bash
container run -it --rm --ssh alpine:latest sh
# Inside:
# apk add openssh-client git
# git clone git@github.com:org/private-repo.git
```

### Export and import an image

```bash
# Save for use on another machine or archive
container image save -o myapp-v1.tar myapp:v1
# On another machine:
container image load -i myapp-v1.tar
```

### Comprehensive cleanup

```bash
container prune                   # remove stopped containers
container image prune --all       # remove all images not used by a running container
container volume prune            # remove volumes not referenced by any container
container network prune           # remove unused user networks
container system df               # verify disk usage went down
```
