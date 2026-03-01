# Lima VM Management on macOS

Lima (Linux Machines) runs Linux VMs on macOS using either QEMU or Apple's Virtualization
Framework (VZ). It manages SSH keys, port forwarding, host mounts, and cloud-init automatically.

## Quick Start

```bash
# Install lima and networking prerequisites
brew install lima
brew install socket_vmnet          # required for host<->guest networking
limactl sudoers | sudo tee /etc/sudoers.d/lima   # lets lima manage vmnet without sudo prompts

# Create and start a VM
limactl create --name=mydebian lima/templates/debian.yaml
limactl start mydebian

# Open a shell
limactl shell mydebian

# Or use the included management script
./lima/scripts/vm.sh create debian mydebian
./lima/scripts/vm.sh shell mydebian
```

---

## Hypervisor Backends: QEMU vs VZ

### QEMU (`vmType: qemu`)
- Works on **all Macs** (Intel and Apple Silicon)
- Slower than VZ — full hardware emulation layer
- Can **cross-compile**: run x86_64 VMs on Apple Silicon (slowly) and vice-versa
- Required for some distros that don't ship VZ-compatible kernels (e.g., Alpine, Arch)
- Supports legacy BIOS (`firmware.legacyBIOS: true`) for special cases
- Most compatible option; use when in doubt

### VZ (Apple Virtualization Framework, `vmType: vz`)
- macOS 13 (Ventura)+ only; **much faster** — near-native performance
- On Apple Silicon: supports **Rosetta 2** (`rosetta.enabled: true`) to run x86 binaries
  inside an aarch64 guest transparently — great for Docker x86 images etc.
- Requires distros with a VZ-compatible kernel (Ubuntu 23.10+, Fedora 37+, Debian 12+)
- Does NOT support legacy BIOS boot
- VirtioFS mounts are faster than 9p (use `mountType: virtiofs` with VZ)
- **Recommended for daily use on Apple Silicon Macs with supported distros**

### Choosing
| Situation | Use |
|---|---|
| Apple Silicon, modern distro (Debian 12+, Fedora 37+, Ubuntu 23.04+) | `vz` |
| Intel Mac | `qemu` (VZ works too on macOS 13+, but QEMU is fine) |
| Alpine, Arch, or unusual kernel | `qemu` |
| Need Rosetta (x86 binaries in an arm64 guest) | `vz` + `rosetta.enabled: true` |
| Cross-arch VM (x86 on M-chip) | `qemu` + explicit `arch: x86_64` |

---

## Networking

### Mode 1: User-mode NAT (`lima: user-v2`) — Default
- Guest can reach the **internet** and the **host** (via `192.168.5.2` from guest side)
- Host **cannot** reach the guest by IP — only via forwarded ports or `limactl shell`
- No extra setup needed
- Good for: internet access, running servers you forward ports to

```yaml
networks:
  - lima: user-v2
```

### Mode 2: Shared (`lima: shared`) — Recommended for most use
- Uses `socket_vmnet` in "shared" mode (NAT with a dedicated subnet)
- Guest gets an IP like `192.168.105.x` that the **host can reach directly**
- Guest can reach the internet (via NAT)
- Requires `brew install socket_vmnet` and the sudoers setup (see Quick Start)
- Good for: multi-VM clusters, SSH'ing to the guest, running services you want to hit by IP

```yaml
networks:
  - lima: shared
```

### Mode 3: Bridged (`lima: bridged`, network interface name required)
- Guest appears on your **local LAN** with its own IP from your router
- Can be reached by other devices on the network
- Requires knowing your network interface name (`en0`, `en1`, etc.)
- Not always stable; DHCP assignment can vary

```yaml
networks:
  - interface: "en0"
    lima: bridged
```

### Combining modes
You can combine user-v2 (for guaranteed internet) and shared (for host access):

```yaml
networks:
  - lima: user-v2     # internet via NAT
  - lima: shared      # host-reachable IP
```

### Port Forwarding (user-v2 or when you don't need direct IP access)
```yaml
portForwards:
  - guestPort: 80
    hostPort: 8080
  - guestPort: 443
    hostPort: 8443
  - guestPort: 22      # avoid if you want limactl's built-in SSH on a different port
    hostPort: 2222
```

### Finding the guest IP (shared/bridged modes)
```bash
limactl shell myvm -- ip addr show
# or
limactl shell myvm -- hostname -I
```

---

## Mounts (Host Directories in the VM)

```yaml
mounts:
  - location: "~"               # your home directory, read-only
    writable: false
    mountType: "9p"             # use virtiofs with vmType: vz for better performance
  - location: "/tmp/lima"       # writable scratch space
    writable: true
    # sshfs and 9p are slower; virtiofs is fast but VZ only
```

**Gotchas:**
- With `vmType: vz`, always use `mountType: virtiofs` — it's dramatically faster.
- With `vmType: qemu`, you're stuck with `9p` or `sshfs`. `9p` is default and decent.
- Write performance on `9p` is poor for heavy I/O (builds, databases). Use a disk image instead.
- Mounted paths in the guest match the host path. `~` on host → `/Users/yourname` in guest.

---

## VM Lifecycle & Best Practices

### State is stored in `~/.lima/<name>/`
Each VM gets a directory containing:
- `lima.yaml` — the config used at creation time (copy of your template)
- `*.qcow2` — the disk image (this is your VM's data)
- `*.pid`, `*.sock` — runtime files (cleaned up on stop)
- `cidata.iso` — cloud-init seed (generated once)
- `ssh` — SSH keys

**Never delete `~/.lima/<name>/` manually while the VM is running.**
**The disk image (`basedisk`, `diffdisk`) lives here — back it up if data matters.**

### Lifecycle Commands
```bash
limactl list                    # list all VMs and status
limactl create --name=foo template.yaml   # create (does NOT start)
limactl start foo               # start (also creates if given a template file)
limactl stop foo                # graceful shutdown
limactl stop --force foo        # hard kill (like pulling the power)
limactl shell foo               # interactive shell
limactl shell foo -- command    # run a single command
limactl copy foo:/remote/path ./local     # scp from guest
limactl copy ./local foo:/remote/path     # scp to guest
limactl delete foo              # delete VM and all data (irreversible)
limactl delete --force foo      # delete even if running
```

### Should I separate create/start/delete scripts?
**Recommended pattern:**
- **One YAML template per distro** (edit inline for resources/name)
- **One management script** (`vm.sh`) for all lifecycle operations
- The `create` step is separate from `start` — useful to inspect config before first boot
- Stopped VMs retain their disk — restart them, don't recreate for the same data

### Upgrading a VM
Lima does not support in-place template upgrades after creation. To change CPU/memory:
```bash
limactl stop myvm
# Edit ~/.lima/myvm/lima.yaml directly (cpu, memory ok; disk size cannot shrink)
limactl start myvm
```

To change disk size (can only grow):
```bash
limactl stop myvm
limactl disk resize myvm --size 40GiB   # Lima 0.16+
```

### Snapshots
QEMU VMs support snapshots:
```bash
limactl stop myvm
# Use qemu-img directly on the disk
qemu-img snapshot -c snap1 ~/.lima/myvm/diffdisk
qemu-img snapshot -l ~/.lima/myvm/diffdisk   # list snapshots
qemu-img snapshot -a snap1 ~/.lima/myvm/diffdisk  # restore
```
VZ does not support QEMU snapshots.

### Data Persistence Strategy
| Data type | Where to put it |
|---|---|
| Throwaway/ephemeral | VM disk (default, fast) |
| Source code you edit on macOS | Mount from host (`~/code`) |
| Long-lived VM data | Mount a dedicated directory (`~/lima-data/myvm`) |
| Database data, large files | Keep on VM disk; back up with `rsync` or `limactl copy` |

---

## Rosetta (Apple Silicon only, VZ only)

Run x86_64 Linux binaries natively on aarch64 guests via macOS Rosetta 2:

```yaml
vmType: vz
rosetta:
  enabled: true
  binfmt: true    # registers Rosetta as binfmt handler so x86 ELFs run transparently
```

After boot, install binfmt support in the guest if needed:
```bash
# Rosetta mount appears at /mnt/lima-rosetta inside the guest
ls /mnt/lima-rosetta/
```

---

## Environment Variables & Cloud-Init

Use `provision` blocks to run scripts at first boot:

```yaml
provision:
  - mode: system   # runs as root
    script: |
      #!/bin/bash
      set -eux
      apt-get update -y
      apt-get install -y htop curl git vim
  - mode: user     # runs as the lima user
    script: |
      #!/bin/bash
      echo 'export EDITOR=vim' >> ~/.bashrc
```

`mode: boot` runs on every start (not just first boot). Use for services that need
to be reconfigured after restart.

---

## SSH Access

Lima manages SSH automatically. Two ways to connect:

```bash
# Via limactl (always works)
limactl shell myvm

# Via standard SSH (after getting the config)
limactl show-ssh --format=config myvm >> ~/.ssh/config
ssh lima-myvm
```

The SSH port is ephemeral and auto-assigned (unless you fix it with `ssh.localPort`).

---

## Installed Templates

| File | Distro | vmType | Notes |
|---|---|---|---|
| `templates/debian.yaml` | Debian 12 (Bookworm) | vz (qemu fallback) | Stable, broad support |
| `templates/fedora.yaml` | Fedora 41 | vz (qemu fallback) | Cutting-edge packages |
| `templates/arch.yaml` | Arch Linux | qemu | Rolling release, qemu only |
| `templates/alpine.yaml` | Alpine 3.21 | qemu | Minimal, fast boot |
| `templates/ubuntu.yaml` | Ubuntu 24.04 LTS | vz (qemu fallback) | Most Lima examples target this |
