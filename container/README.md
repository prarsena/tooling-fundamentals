````markdown
# Apple `container` on macOS

`container` is Apple's tool for creating and running Linux containers as lightweight virtual
machines on Apple silicon Macs. Unlike traditional container runtimes (Docker, Podman) which
share a single Linux VM, `container` launches a dedicated micro-VM per container using Apple's
[Virtualization.framework](https://developer.apple.com/documentation/virtualization). It
consumes and produces standard OCI images, so images built here run anywhere and images from
any registry run here.

The underlying Swift package powering `container` is
[apple/containerization](https://github.com/apple/containerization), which you can also use
directly from Swift to embed container management in your own applications.

> **Requirements**: Mac with Apple silicon (M1 or later) · macOS 26 (Sequoia) or later.
> Intel Macs are **not supported**.

---

## Quick Start

```bash
# 1. Install (download the latest .pkg from GitHub releases)
# https://github.com/apple/container/releases
# Double-click the .pkg and follow the installer wizard.

# 2. Start the system service (installs a default kernel on first run)
container system start

# 3. Run your first container
container run --rm docker.io/alpine:latest echo "hello from a micro-VM"

# 4. Start an interactive shell
container run -it --rm docker.io/ubuntu:latest /bin/bash

# 5. Set up a local DNS domain (recommended — lets you reach containers by name)
sudo container system dns create test
container system property set dns.domain test

# 6. Run the included management script for common lifecycle tasks
./container/scripts/container.sh help
```

---

## Architecture: VM-per-Container

`container` differs fundamentally from Docker/Podman:

| | Docker / Podman | apple/container |
|---|---|---|
| Isolation | Linux namespaces + cgroups (shared kernel) | Full hardware VM per container |
| macOS approach | One Linux VM hosts all containers | One micro-VM **per** container |
| Boot time | Milliseconds | Sub-second (optimised kernel + vminitd) |
| Memory overhead | Low per container, but shared VM is always on | ~Minimal per VM; no "always on" daemon VM |
| Network | Bridge with NAT (container-to-container on same VM) | Each container gets its own IP on vmnet |
| Security | Namespace isolation | VM-level hardware isolation |
| OCI compatibility | Full | Full (pull/push any standard registry) |

### How a Container Starts

1. You run `container run my-image`.
2. `container-apiserver` (a launchd agent) receives the request via XPC.
3. It fetches the OCI image layers and assembles an ext4 root filesystem block.
4. `container-runtime-linux` launches a Virtualization.framework VM with:
   - The optimised Linux kernel (from Kata Containers, or your own).
   - `vminitd` as PID 1 — a tiny gRPC-over-vsock init daemon.
   - The OCI container process as a child of vminitd.
5. `container-network-vmnet` allocates an IP address on the vmnet bridge.
6. The container process runs. I/O, signals, and exit events flow back over vsock.

The kernel boots and the container process is running in **under one second**.

---

## Installation

### Install from GitHub Releases (recommended)

```bash
# Download the .pkg for the latest release from:
# https://github.com/apple/container/releases

# The installer places binaries under /usr/local/:
#   /usr/local/bin/container
#   /usr/local/bin/update-container.sh
#   /usr/local/bin/uninstall-container.sh
```

### Upgrade

```bash
# Stop first, then use the bundled update script:
container system stop
/usr/local/bin/update-container.sh           # upgrades to latest release

# To upgrade to a specific version, pass -v:
/usr/local/bin/update-container.sh -v 0.5.0
```

### Downgrade

```bash
container system stop
/usr/local/bin/uninstall-container.sh -k     # -k keeps user data
/usr/local/bin/update-container.sh -v 0.3.0
container system start
```

### Uninstall

```bash
/usr/local/bin/uninstall-container.sh -d     # -d removes user data too
# or to keep images/containers for a potential reinstall:
/usr/local/bin/uninstall-container.sh -k
```

---

## System Management

```bash
# Start all container services (apiserver, network, image store)
container system start

# Stop all services (running containers are stopped first)
container system stop

# Check service health
container system status

# Show CLI + API server versions
container system version

# Disk usage (images, containers, volumes)
container system df

# Tail system logs (last 5 min by default)
container system logs
container system logs --follow          # live tail
container system logs --last 30m        # last 30 minutes
```

### Kernel Management

On first `system start`, you are prompted to install the recommended default kernel
(from [Kata Containers](https://github.com/kata-containers/kata-containers/releases)).

```bash
# Install / update the recommended kernel
container system kernel set --recommended

# Install a custom kernel from a URL tar archive
container system kernel set --tar https://example.com/mykernel.tar.gz --binary vmlinux.container

# Use a local kernel binary
container system kernel set --binary /path/to/vmlinux
```

### Shell Completion

```bash
# Zsh (oh-my-zsh)
mkdir -p ~/.oh-my-zsh/completions
container --generate-completion-script zsh > ~/.oh-my-zsh/completions/_container

# Zsh (plain)
mkdir -p ~/.zsh/completion
echo 'fpath=(~/.zsh/completion $fpath)\nautoload -U compinit\ncompinit' >> ~/.zshrc
container --generate-completion-script zsh > ~/.zsh/completion/_container

# Bash (Homebrew bash-completion)
container --generate-completion-script bash > /opt/homebrew/etc/bash_completion.d/container

# Fish
container --generate-completion-script fish > ~/.config/fish/completions/container.fish
```

---

## DNS: Reaching Containers by Name

Without DNS setup, you reach containers by IP address. With a local domain you can
use names like `my-web-server.test`.

```bash
# Create the domain (needs sudo to write /etc/resolver/test)
sudo container system dns create test

# Tell container to use "test" as the default domain for unqualified names
container system property set dns.domain test

# Now run a named container and curl it by hostname:
container run -d --name web --rm my-image-name
curl http://web.test

# List configured domains
container system dns list

# Remove a domain
sudo container system dns delete test
```

---

## Container Lifecycle

### Core Commands

```bash
# Run (create + start in one step). Most common workflow.
container run -it --rm ubuntu:latest /bin/bash         # interactive, remove on exit
container run -d --name web --rm nginx:latest          # background, named, remove on exit
container run -d --name web -p 8080:80 nginx:latest    # with port forward

# Create without starting (useful for pre-flight inspection)
container create --name myapp myimage:latest /app/server

# Start a stopped (created) container
container start myapp
container start --attach myapp         # attach stdout/stderr

# Stop gracefully (SIGTERM, waits up to 5 s then SIGKILL)
container stop myapp
container stop --time 30 myapp         # 30 s grace period
container stop --all                   # stop everything

# Kill immediately (SIGKILL by default)
container kill myapp
container kill --signal SIGINT myapp   # send a specific signal

# Delete
container rm myapp                     # must be stopped
container rm --force myapp             # force-remove even if running
container rm --all                     # remove all stopped containers

# Remove all stopped containers (bulk cleanup)
container prune
```

### Listing & Inspecting

```bash
container ls                           # running containers only
container ls -a                        # all (including stopped)
container ls --format json | jq        # JSON output

# Inspect a specific container (detailed JSON)
container inspect myapp | jq

# Get just the IP address of a running container
container inspect myapp | jq -r '.[0].networks[0].address'

# List IPs of all running containers
container ls --format json | jq '.[] | select(.status=="running") | [.configuration.id, .networks[0].address]'
```

### Exec & Interactive Access

```bash
# Run a one-off command in a running container
container exec myapp ls /app

# Open an interactive shell
container exec -it myapp /bin/sh

# Run as a specific user
container exec --user nobody myapp whoami

# Run in a different working directory
container exec -w /tmp myapp pwd
```

### Logs

```bash
container logs myapp                   # all captured stdout/stderr
container logs -f myapp                # follow (stream)
container logs -n 50 myapp            # last 50 lines
container logs --boot myapp           # VM kernel + vminitd boot log (great for debugging)
```

### Stats

```bash
container stats                        # live stats for all running containers
container stats myapp web db          # specific containers
container stats --no-stream myapp     # single snapshot
container stats --format json --no-stream myapp | jq   # JSON for scripting
```

---

## Building Images

`container build` uses BuildKit internally. A separate builder VM is started on first build.

```bash
# Basic build
container build -t my-app:latest .

# Specify a Dockerfile path and pass build args
container build -f docker/Dockerfile.prod \
    --build-arg NODE_VERSION=20 \
    -t my-app:prod .

# Multi-stage target
container build --target production --no-cache -t my-app:prod .

# Multiple tags
container build -t my-app:latest -t my-app:v1.2.0 .

# Multi-arch (creates a fat manifest: arm64 + amd64 via Rosetta)
container build --arch arm64 --arch amd64 \
    -t registry.example.com/user/my-app:latest .
```

### Builder VM Management

The builder VM starts automatically on `container build`. You can tune it:

```bash
container builder start --cpus 8 --memory 16g    # start with custom resources
container builder status                          # is it running?
container builder stop                            # stop
container builder delete                          # stop + remove
container builder delete --force                  # remove even if running
```

### Build Performance Tips

- The default builder gets **2 CPUs / 2 GiB RAM**. For large builds, always pre-start
  the builder with more resources: `container builder start --cpus 8 --memory 16g`
- BuildKit caches layers. Use `--no-cache` only when you need a fully clean build.
- For amd64 images on Apple Silicon, Rosetta is used by default instead of QEMU emulation:
  `container system property set build.rosetta true` (default on).

---

## Image Management

```bash
container image list                            # list local images
container image list --verbose                  # include digest, size, created

container image pull ubuntu:latest             # pull from default registry (Docker Hub)
container image pull ghcr.io/org/app:v1.0      # pull from GHCR
container image pull --arch amd64 node:20      # pull a specific arch

container image tag web-test reg.example.com/user/web-test:latest   # re-tag
container image push reg.example.com/user/web-test:latest            # push

container image inspect web-test | jq         # detailed JSON

container image delete web-test               # remove by name
container image delete --all                  # remove all images
container image prune                         # remove untagged (dangling) images
container image prune --all                   # remove all images not used by any container

# Export / import (for offline transport)
container image save -o my-app.tar my-app:latest
container image load -i my-app.tar
```

---

## Networking

Each container gets its own IP on a vmnet bridge (`192.168.64.x` by default on macOS 26).
Container-to-container communication works natively on macOS 26.

### Port Publishing (expose to localhost)

```bash
# Publish a single port
container run -d --name web -p 8080:80 nginx:latest
curl http://127.0.0.1:8080

# Bind to a specific host IP
container run -d -p 127.0.0.1:8080:80 nginx:latest

# IPv6 loopback
container run -d -p '[::1]:8080:80' nginx:latest

# Multiple ports
container run -d -p 8080:80 -p 8443:443 nginx:latest
```

### Container-to-Container (direct IP, macOS 26+)

```bash
# Start a server
container run -d --name api-server --rm my-api-image

# Get its IP
API_IP=$(container inspect api-server | jq -r '.[0].networks[0].address' | cut -d/ -f1)

# Call it from another container
container run --rm my-client-image curl http://$API_IP:3000/health

# Or use DNS if you set up a domain:
container run --rm my-client-image curl http://api-server.test:3000/health
```

### User-defined Networks (macOS 26+)

```bash
# Create an isolated network
container network create mynet
container network create mynet --subnet 192.168.100.0/24 --subnet-v6 fd00:abcd::/64

# Run containers on it
container run -d --name api --network mynet --rm my-api
container run -d --name web --network mynet --rm my-web

# List, inspect, delete
container network list
container network inspect mynet | jq
container network delete mynet           # only when no containers attached
container network prune                  # remove all unused user networks
```

### Access a Host Service from a Container

```bash
# Map a synthetic domain to a host IP
sudo container system dns create host.container.internal \
    --localhost 203.0.113.113

# Then from inside a container:
container run -it --rm alpine/curl curl http://host.container.internal:8000
```

### Network Defaults

```bash
container system property set network.subnet 192.168.100.0/24    # default IPv4 subnet
container system property set network.subnetv6 fd00:abcd::/64    # default IPv6 prefix
```

---

## Volumes & File Sharing

### Bind Mounts (host directory into container)

```bash
# Mount a specific host directory (use absolute paths)
container run --rm -v "$HOME/myproject:/workspace" ubuntu:latest ls /workspace

# Alternate --mount syntax
container run --rm --mount source="$HOME/myproject",target=/workspace ubuntu:latest ls /workspace

# Read-only mount
container run --rm -v "$HOME/config:/etc/myapp:ro" ubuntu:latest cat /etc/myapp/config.yaml
```

### Named Volumes

```bash
container volume create mydata --size 10G      # 10 GiB volume
container run -d --name db -v mydata:/var/lib/postgresql/data postgres:16

# List, inspect, remove
container volume list
container volume inspect mydata | jq
container volume delete mydata                  # must not be in use
container volume delete --all
container volume prune                          # remove volumes with no container references
```

### Anonymous Volumes

```bash
# Created automatically when you use -v /path with no source
container run -v /data alpine touch /data/hello

# Anonymous volumes do NOT auto-delete with --rm (unlike Docker)
# Find and clean them up manually:
container volume list -q | grep anon
container volume prune
```

### SSH Agent Socket Forwarding

```bash
# Forward your macOS SSH agent into the container
container run -it --rm --ssh alpine:latest sh

# Inside the container you can now do:
# apk add openssh-client git
# ssh-add -l           # lists your keys
# git clone git@github.com:org/private-repo.git
```

---

## Registry Management

```bash
# Login (Docker Hub by default)
container registry login

# Login to a specific registry
container registry login ghcr.io --username myuser
echo "$MY_TOKEN" | container registry login ghcr.io -u myuser --password-stdin

# Login to a private registry
container registry login registry.example.com

# List saved logins
container registry list

# Logout
container registry logout ghcr.io
```

### Change Default Registry

```bash
# Default is docker.io (Docker Hub). To change:
container system property set registry.domain ghcr.io

# Now bare image names like "myimage:latest" pull from ghcr.io
```

---

## System Properties Reference

```bash
container system property list            # show all properties with current values

# Useful properties:
container system property get  build.rosetta         # amd64 builds use Rosetta? (default: true)
container system property get  dns.domain            # default DNS domain
container system property get  image.builder         # BuildKit image reference
container system property get  image.init            # vminitd image reference
container system property get  kernel.url            # kernel download URL
container system property get  registry.domain       # default registry
container system property get  network.subnet        # default IPv4 subnet
container system property get  network.subnetv6      # default IPv6 prefix

# Set examples:
container system property set  dns.domain            mycompany.local
container system property set  build.rosetta         false
container system property set  registry.domain       ghcr.io
container system property set  network.subnet        192.168.200.0/24

# Revert to default:
container system property clear dns.domain
```

---

## Advanced Features

### Resource Limits

Each container is a VM — specify resources accordingly:

```bash
# Default: 4 CPUs, 1 GiB RAM
container run -d --name web my-image

# Custom resources
container run --cpus 8 --memory 32g -d --name big-job my-image

# Memory abbreviations: k/m/g/t/p (case-insensitive)
container run --memory 512m --cpus 2 -d my-image
```

### Multi-Architecture

Apple Silicon natively runs `arm64`. For `amd64` images, Rosetta 2 provides transparent
translation with near-native performance — no slow QEMU emulation needed.

```bash
# Run an amd64-only image (Rosetta handles translation automatically)
container run --arch amd64 --rm ubuntu:latest uname -m     # → x86_64

# Build a multiplatform image
container build --arch arm64 --arch amd64 -t myapp:latest .

# Push individual arch
container image push --arch arm64 myapp:latest

# Disable Rosetta for builds (force QEMU/cross-compile):
container system property set build.rosetta false
```

### Custom Kernel per Container

You can pin specific containers to a particular kernel binary:

```bash
container run -k /path/to/vmlinux --rm ubuntu:latest uname -r
```

### Init Process (Zombie Reaping)

When your main process is PID 1, it must handle zombie processes. Use `--init`
to insert a lightweight init daemon that reaps zombies and forwards signals:

```bash
container run --init ubuntu:latest my-server
container create --init --name myapp ubuntu:latest /app/server
```

### Nested Virtualization (M3+ only)

```bash
# Requires kernel with KVM support and an M3 or newer chip
container run --virtualization -k /path/to/kvm-enabled-kernel --rm ubuntu:latest \
    sh -c "dmesg | grep kvm"
# Expected output: kvm [1]: Hyp mode initialized successfully
```

### Read-only Root Filesystem

```bash
container run --read-only --tmpfs /tmp --rm ubuntu:latest touch /tmp/ok
```

### Custom MAC Address

```bash
# LAAU (locally administered, unicast): first byte should have bits: ?X?????0 ??????1?
container run --network default,mac=02:42:ac:11:00:02 ubuntu:latest ip addr show eth0
```

### Socket Publishing

```bash
# Forward a Unix domain socket from host to container
container run --publish-socket /tmp/host.sock:/tmp/container.sock my-image
```

### Custom Init Image

For custom VM-level boot logic (eBPF filters, extra daemons, debugging):

```bash
# Build a custom init image (wraps the real vminitd)
# See container/recipes/custom-init/ for a full example
container build -t local/custom-init:latest container/recipes/custom-init/

# Use it
container run --init-image local/custom-init:latest ubuntu:latest echo hello

# Verify it ran by checking boot logs
container logs --boot <container-id> | grep custom-init
```

---

## Troubleshooting

### Service won't start

```bash
container system status
container system logs --last 10m | tail -50
# If stuck, try a full restart:
container system stop && container system start
```

### Container gets no IP / can't reach network

```bash
# Check vmnet bridge (should show bridge100 or similar)
ifconfig | grep -A5 bridge

# Check what IP the container sees
container inspect <name> | jq '.[0].networks'

# View boot log for network setup messages
container logs --boot <name>
```

### Image pull fails

```bash
# Check registry credentials
container registry list

# Try explicit scheme
container image pull --scheme https myregistry.example.com/myimage:tag

# Check DNS resolution from host
nslookup ghcr.io
```

### Build fails or is very slow

```bash
# Check builder status
container builder status

# Restart builder with more resources
container builder stop && container builder delete
container builder start --cpus 8 --memory 16g
```

### Disk space

```bash
container system df

# Clean up aggressively
container prune                   # stopped containers
container image prune --all       # unused images
container volume prune            # unreferenced volumes
```

---

## Comparison with Lima

| | Lima | apple/container |
|---|---|---|
| What it runs | Full Linux VMs | Linux containers (per-VM) |
| Primary use | VM with your shell, SSH in | Running containerized apps |
| macOS support | Intel + Apple Silicon | Apple Silicon only |
| Image format | QCOW2 VM disk | OCI container image |
| Registry integration | None | Full OCI push/pull |
| Build | N/A (`Dockerfile` in VM) | `container build` (BuildKit) |
| Network | QEMU/VZ user-mode NAT or vmnet | vmnet bridge (macOS 26+: full isolation) |
| When to use | Need a full distro environment | Running containerised workloads |
````
