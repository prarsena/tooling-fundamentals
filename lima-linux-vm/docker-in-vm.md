# Docker Inside a Lima VM

Running Docker Engine inside a Lima VM is the closest you get to a native Linux Docker
experience on macOS — no Docker Desktop, no licensing concerns, no abstraction layer.
The VM is just a Linux machine; Docker runs exactly as it would on a real server.

> **Contrast with `/container/`**: The `container/` folder documents Apple's own
> `container` tool, which is macOS-only and Apple Silicon-only. This guide is about
> running the upstream Docker Engine daemon *inside* a Lima Linux guest.

---

## Why Run Docker Inside a Lima VM?

| Approach | Isolation | Docker socket location | Complexity |
|---|---|---|---|
| Docker Desktop | macOS app wraps a hidden Linux VM | `/var/run/docker.sock` on host via magic | Low — GUI, auto-updates |
| Lima VM + Docker Engine | Full Linux VM, you control everything | Inside the VM; can be forwarded | Medium |
| apple/container | Micro-VM per container, Apple Silicon only | macOS-native API | Low for simple use |

**Good reasons to use Lima + Docker Engine:**
- You want exact parity with a Linux CI/CD or production environment.
- You need a specific Docker Engine version or buildx plugin.
- You want rootless Docker without daemon privileges on macOS.
- You need to test Linux-specific container behavior (cgroups, namespaces, `/proc`).
- You want to forward the Docker socket to your macOS CLI tools without Docker Desktop.

---

## Installing Docker Engine by Distro

### Ubuntu / Debian

Both use the same official Docker APT repository.

```bash
# 1. Remove any distro-packaged docker that conflicts
sudo apt remove -y docker.io docker-doc docker-compose podman-docker

# 2. Set up the repository
sudo apt update
sudo apt install -y ca-certificates curl gnupg

sudo install -m 0755 -d /etc/apt/keyrings
curl -fsSL https://download.docker.com/linux/ubuntu/gpg \
  | sudo gpg --dearmor -o /etc/apt/keyrings/docker.gpg
sudo chmod a+r /etc/apt/keyrings/docker.gpg

# For Debian, replace 'ubuntu' with 'debian' in the URL and command below:
echo \
  "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.gpg] \
  https://download.docker.com/linux/ubuntu \
  $(. /etc/os-release && echo "$VERSION_CODENAME") stable" \
  | sudo tee /etc/apt/sources.list.d/docker.list > /dev/null

# 3. Install
sudo apt update
sudo apt install -y docker-ce docker-ce-cli containerd.io \
                    docker-buildx-plugin docker-compose-plugin

# 4. Enable and start
sudo systemctl enable --now docker

# 5. Add yourself to the docker group (avoid sudo for every command)
sudo usermod -aG docker $USER
newgrp docker          # apply group change without logging out
docker run --rm hello-world
```

---

### Fedora

```bash
# 1. Remove conflicting packages
sudo dnf remove -y docker docker-client docker-client-latest docker-common \
                   docker-latest docker-latest-logrotate docker-logrotate \
                   docker-selinux docker-engine-selinux docker-engine

# 2. Add the Docker repo
sudo dnf -y install dnf-plugins-core
sudo dnf config-manager --add-repo \
  https://download.docker.com/linux/fedora/docker-ce.repo

# 3. Install
sudo dnf install -y docker-ce docker-ce-cli containerd.io \
                    docker-buildx-plugin docker-compose-plugin

# 4. Enable and start
sudo systemctl enable --now docker

# 5. Add user to group
sudo usermod -aG docker $USER
newgrp docker
docker run --rm hello-world
```

---

### Arch Linux

Docker is in the official Arch repositories.

```bash
# 1. Install
sudo pacman -S docker docker-compose

# 2. Enable and start
sudo systemctl enable --now docker

# 3. Add user to group
sudo usermod -aG docker $USER
newgrp docker
docker run --rm hello-world
```

> **Note:** Arch rolling releases can push Docker updates that temporarily break the
> daemon. After a major `pacman -Syu`, restart the daemon: `sudo systemctl restart docker`.

---

### Alpine Linux

Alpine ships Docker in its `community` repository. Alpine uses OpenRC, not systemd.

```bash
# 1. Enable the community repo if not already
# /etc/apk/repositories should include a line ending in /community
# e.g.: https://dl-cdn.alpinelinux.org/alpine/v3.21/community

# 2. Install
sudo apk add docker docker-cli-compose

# 3. Enable at boot and start
sudo rc-update add docker default
sudo rc-service docker start

# 4. Add user to group
sudo addgroup $USER docker
# Log out and back in, or open a new shell:
newgrp docker
docker run --rm hello-world
```

> **Alpine gotcha:** Alpine uses musl libc. Most Docker images are glibc-based and run fine
> because they bring their own libc inside the image. But building Go or C code *in* Alpine
> containers may behave differently than on glibc distros.

---

## Post-Install Pro-Tips

### Forward the Docker socket to your macOS host

You can expose the Docker socket inside the VM so your macOS `docker` CLI talks to it
without entering the VM every time.

**Option A — SSH socket forwarding (no port involved)**

Add this to your `~/.ssh/config` (after running `limactl show-ssh --format=config myvm`):

```
Host lima-myvm
  LocalForward /tmp/docker-myvm.sock /var/run/docker.sock
```

Then on macOS:

```bash
ssh -N lima-myvm &      # hold the tunnel open in background
export DOCKER_HOST=unix:///tmp/docker-myvm.sock
docker ps               # talks to the VM daemon
```

**Option B — TCP listener inside the VM (simpler, less secure)**

Edit `/etc/docker/daemon.json` inside the VM:

```json
{
  "hosts": ["unix:///var/run/docker.sock", "tcp://0.0.0.0:2375"]
}
```

Restart Docker, then add a port forward in the Lima template:

```yaml
portForwards:
  - guestPort: 2375
    hostPort: 2375
```

On macOS:

```bash
export DOCKER_HOST=tcp://localhost:2375
docker ps
```

> **Warning:** TCP without TLS exposes the daemon. Only use this on a trusted local VM,
> never when the VM is network-bridged to an untrusted network.

---

### Run Docker rootless (no root daemon)

Rootless mode runs the daemon and all containers as your normal user. No `sudo`, no
`docker` group, daemon compromise doesn't get root on the host VM.

```bash
# Prerequisites (Debian/Ubuntu)
sudo apt install -y uidmap dbus-user-session

# Install rootless
dockerd-rootless-setuptool.sh install

# Set environment variables (add to ~/.bashrc)
export PATH=/usr/bin:$PATH
export DOCKER_HOST=unix://$XDG_RUNTIME_DIR/docker.sock

# Start as user service (systemd distros)
systemctl --user enable --now docker
```

On Alpine (OpenRC, no user units): rootless mode is less straightforward; stick with
the standard group-based setup.

---

### Multi-arch builds with buildx

Lima VMs on Apple Silicon run aarch64 by default. To build x86_64 images:

```bash
# Check available platforms
docker buildx ls

# Create a builder with QEMU emulation support
docker run --privileged --rm tonistiigi/binfmt --install all
docker buildx create --name multiarch --use
docker buildx inspect --bootstrap

# Build for multiple platforms
docker buildx build \
  --platform linux/amd64,linux/arm64 \
  -t myimage:latest \
  --push \
  .

# Or just local, single platform
docker buildx build --platform linux/amd64 -t myimage:amd64 --load .
```

If your Lima VM is VZ-mode with `rosetta.enabled: true`, x86_64 binaries run via Rosetta.
For building amd64 images you still want the QEMU binfmt approach above — Rosetta handles
execution but `docker buildx` needs the binfmt registration to transparently run amd64
container processes.

---

### Disk usage cleanup

Docker accumulates images, stopped containers, build cache, and dangling volumes.

```bash
# See what's taking space
docker system df

# Remove stopped containers + dangling images + unused networks + build cache
docker system prune

# Also remove all unused images (not just dangling)
docker system prune -a

# Prune volumes too (destructive — removes all volumes not attached to a container)
docker system prune -a --volumes

# Targeted cleanup
docker image prune -a          # all unused images
docker container prune         # stopped containers
docker volume prune            # unused volumes
docker builder prune           # build cache
```

> The VM's `diffdisk` (`~/.lima/<name>/diffdisk` on macOS) grows as data is written.
> It does **not** automatically shrink when you delete containers or images. Run
> `docker system prune` inside the VM to free logical space, but the qcow2 file on
> disk won't shrink until you compact it:
>
> ```bash
> # On macOS, after stopping the VM
> qemu-img convert -O qcow2 ~/.lima/myvm/diffdisk ~/.lima/myvm/diffdisk.compact
> mv ~/.lima/myvm/diffdisk.compact ~/.lima/myvm/diffdisk
> ```

---

### Persist data with volumes or bind mounts

```bash
# Named volume (Docker manages it, survives container removal)
docker run -v mydata:/app/data myimage

# Bind mount from Lima-mounted macOS directory (editable on both sides)
# Your macOS ~/projects is at /Users/yourname/projects inside the VM
docker run -v /Users/yourname/projects/myapp:/app myimage

# Bind mount from VM-local path
docker run -v /home/yourname/data:/data myimage
```

> **Performance note:** The Lima host-mount path (`/Users/yourname/...`) goes through
> virtiofs or 9p. For I/O-heavy containers (databases, build caches), prefer a
> VM-local path or a named Docker volume — they stay on `diffdisk` and avoid the
> host-mount overhead.

---

### Useful daemon configuration (`/etc/docker/daemon.json`)

```json
{
  "log-driver": "local",
  "log-opts": {
    "max-size": "10m",
    "max-file": "3"
  },
  "storage-driver": "overlay2",
  "features": {
    "buildkit": true
  }
}
```

- `log-driver: local` uses a compact binary format instead of JSON-file; smaller and faster.
- `overlay2` is the default on modern kernels; explicit here for clarity.
- `buildkit: true` is the default since Docker 23 but worth making explicit for older builds.

Apply changes: `sudo systemctl restart docker` (or `sudo rc-service docker restart` on Alpine).

---

### Docker Compose inside the VM

The `docker compose` plugin (v2, lowercase) is installed alongside Docker via the
`docker-compose-plugin` package in the instructions above.

```bash
# V2 (plugin, recommended)
docker compose up -d
docker compose logs -f
docker compose down

# Check version
docker compose version
```

If you only have the older standalone `docker-compose` (v1, hyphenated):

```bash
# Alpine: apk add docker-cli-compose  (installs the standalone binary)
# Or install v2 plugin manually:
mkdir -p ~/.docker/cli-plugins
curl -SL https://github.com/docker/compose/releases/latest/download/docker-compose-linux-$(uname -m) \
  -o ~/.docker/cli-plugins/docker-compose
chmod +x ~/.docker/cli-plugins/docker-compose
```

---

## Troubleshooting

### `Got permission denied ... /var/run/docker.sock`
You haven't been added to the `docker` group yet, or the group change hasn't taken effect.

```bash
sudo usermod -aG docker $USER
newgrp docker     # applies immediately in current shell
```

### `Cannot connect to the Docker daemon`
The daemon isn't running.

```bash
# systemd distros
sudo systemctl status docker
sudo systemctl start docker

# Alpine (OpenRC)
sudo rc-service docker status
sudo rc-service docker start
```

### `WARNING: bridge-nf-call-iptables is disabled`
A kernel parameter needs setting. Add to `/etc/sysctl.d/99-docker.conf`:

```
net.bridge.bridge-nf-call-iptables = 1
net.bridge.bridge-nf-call-ip6tables = 1
```

Then: `sudo sysctl --system`

### `/proc/sys/net/ipv4/ip_forward` not enabled
Docker needs IP forwarding for container networking.

```bash
# Temporary
sudo sysctl -w net.ipv4.ip_forward=1

# Permanent — add to /etc/sysctl.d/99-docker.conf
net.ipv4.ip_forward = 1
```

Then: `sudo sysctl --system && sudo systemctl restart docker`

### Containers can't reach the internet (Alpine/Arch)
DNS resolution can fail if the host VM's resolver isn't propagated. Set a fallback in
`/etc/docker/daemon.json`:

```json
{
  "dns": ["1.1.1.1", "8.8.8.8"]
}
```
