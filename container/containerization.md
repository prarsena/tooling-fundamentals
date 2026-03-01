````markdown
# apple/containerization Swift Package

[apple/containerization](https://github.com/apple/containerization) is the Swift library
that powers `apple/container`. You can embed it directly in your own Swift applications on
Apple Silicon Macs (macOS 26+) to build, run, and manage Linux containers programmatically.

> **Requirements**: Mac with Apple silicon · macOS 26 · Xcode 26 (or Swift 6.2+).

---

## What the Package Provides

| Module | Purpose |
|---|---|
| `Containerization` | Spawn and manage Linux containers (`LinuxContainer`, `LinuxProcess`) |
| `ContainerizationOCI` | Pull, push, and manipulate OCI container images and manifests |
| `ContainerizationOCI/Client` | Authenticate and communicate with OCI registries |
| `ContainerizationEXT4` | Create and populate ext4 filesystem blocks (used as container rootfs) |
| `ContainerizationNetlink` | Interact with the Linux Netlink socket family |
| `vminitd` | The minimal init daemon that runs inside each container VM (subproject) |

API reference: <https://apple.github.io/containerization/documentation/>

---

## Adding the Package to Your Swift Project

### Swift Package Manager (`Package.swift`)

```swift
// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "MyContainerApp",
    platforms: [.macOS(.v26)],    // macOS 26 minimum
    dependencies: [
        .package(
            url: "https://github.com/apple/containerization",
            .upToNextMinorVersion(from: "0.1.0")  // source-stable within minor versions
        ),
    ],
    targets: [
        .executableTarget(
            name: "MyContainerApp",
            dependencies: [
                .product(name: "Containerization",    package: "containerization"),
                .product(name: "ContainerizationOCI", package: "containerization"),
            ]
        ),
    ]
)
```

> **Stability note**: Until 1.0.0, source stability is only guaranteed within
> patch versions (e.g. 0.1.0 → 0.1.1). Use `.upToNextMinorVersion` to avoid
> unexpected breaking changes from minor bumps.

---

## Building the Package

```bash
git clone https://github.com/apple/containerization
cd containerization

# Install Swiftly + Swift 6.2 + Static Linux SDK
make cross-prep

# Build everything
make all

# Run unit + integration tests (integration requires a kernel)
make fetch-default-kernel    # downloads the Kata kernel; only needed once after clean
make all test integration
```

### Building a Custom Kernel

The `kernel/` directory contains an optimised Linux kernel configuration for fast
boot times. To build your own:

```bash
# Requirements: Docker or a Linux environment for the kernel build container
cd kernel
# Follow the instructions in kernel/README.md
```

To use a pre-built kernel from Kata Containers:

```bash
# The kernel tools expect the binary at opt/kata/share/kata-containers/vmlinux.container
# inside a tar archive. With container CLI you install it via:
container system kernel set --recommended
```

---

## Key API Concepts

### 1. OCI Image management (`ContainerizationOCI`)

Pull an image from a registry:

```swift
import ContainerizationOCI

// Pull ubuntu:latest from Docker Hub
let client = RegistryClient(registry: "registry-1.docker.io")
let reference = ImageReference(repository: "library/ubuntu", tag: "latest")
let manifest = try await client.pull(reference: reference, destination: localStore)
```

List local images, inspect manifests, push to a registry, log in/out — all
available on `RegistryClient` and `LocalImageStore`. See:
- [ImageCommand.swift](https://github.com/apple/containerization/blob/main/Sources/cctl/ImageCommand.swift)
- [LoginCommand.swift](https://github.com/apple/containerization/blob/main/Sources/cctl/LoginCommand.swift)

### 2. Creating a root filesystem block (`ContainerizationEXT4`)

`container` converts OCI image layers into an ext4 block device. The
`ContainerizationEXT4` module exposes APIs to do this programmatically:

```swift
import ContainerizationEXT4

// Unpack OCI layers into an ext4 image
let rootfsPath = URL(fileURLWithPath: "/tmp/rootfs.ext4")
try await EXT4Image.create(from: layers, outputPath: rootfsPath, size: .gigabytes(4))
```

See [RootfsCommand.swift](https://github.com/apple/containerization/blob/main/Sources/cctl/RootfsCommand.swift).

### 3. Running a container (`Containerization`)

`LinuxContainer` spawns a Virtualization.framework VM, boots `vminitd`, and runs
your containerised process:

```swift
import Containerization

// Minimal container run example (see RunCommand.swift for full usage)
let config = LinuxContainerConfiguration(
    kernel: URL(fileURLWithPath: "/path/to/vmlinux"),
    initrd: nil,
    rootfs: URL(fileURLWithPath: "/path/to/rootfs.ext4"),
    cpuCount: 2,
    memorySize: .gigabytes(1)
)

let container = try LinuxContainer(configuration: config)
try await container.start()

let process = LinuxProcess(
    executablePath: "/bin/sh",
    arguments: ["-c", "echo hello from containerization"],
    environment: ["PATH=/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin"]
)

let exitCode = try await container.run(process: process)
print("Exit code: \(exitCode)")

try await container.stop()
```

See [RunCommand.swift](https://github.com/apple/containerization/blob/main/Sources/cctl/RunCommand.swift).

### 4. `cctl` — the exploration executable

`cctl` (Container ConTroL) lives in `Sources/cctl/` and is a playground for the
Containerization APIs. It's a great starting point for understanding all
available operations:

```bash
# Build and run cctl
swift build
.build/debug/cctl --help

# Pull an image
.build/debug/cctl image pull ubuntu:latest

# Create a rootfs block
.build/debug/cctl rootfs create ubuntu:latest /tmp/ubuntu.ext4

# Run a container
.build/debug/cctl run --kernel /path/to/vmlinux --rootfs /tmp/ubuntu.ext4 -- /bin/sh
```

---

## Architecture Deep Dive

```
Your macOS App / container CLI
        │
        │  Swift API calls
        ▼
 Containerization Swift Package
        │
        ├── ContainerizationOCI  ←── OCI image registry (Docker Hub, GHCR, etc.)
        │     Pulls layers, builds manifests, caches locally
        │
        ├── ContainerizationEXT4
        │     Assembles OCI layers into an ext4 block device
        │
        ├── Containerization (LinuxContainer)
        │     Calls Apple Virtualization.framework
        │     Boots a micro-VM per container:
        │       ┌─────────────────────────────┐
        │       │  Linux kernel (Kata/custom) │
        │       │  vminitd (PID 1)            │ ← gRPC-over-vsock
        │       │  containerized process       │
        │       └─────────────────────────────┘
        │
        └── ContainerizationNetlink
              Network interface setup inside the VM
```

### vminitd

`vminitd` is PID 1 inside every container VM. It:
- Exposes a gRPC API over virtio socket (vsock) to the host.
- Receives the OCI container process spec from the host.
- Starts the containerised process, managing I/O and signals.
- Reports exit events back to the host.
- Is published as a container image: `ghcr.io/apple/containerization/vminit:latest`

---

## Generating API Documentation

```bash
# Generate DocC docs
make docs

# Serve locally (open in browser)
make serve-docs
# Then: open http://localhost:8000/containerization/documentation/
```

---

## Contributing

The containerization project is under active development and welcomes
contributions. See
[CONTRIBUTING.md](https://github.com/apple/containerization/blob/main/CONTRIBUTING.md).

```bash
# Install the optional pre-commit hook (checks formatting + license headers)
make pre-commit

# Re-generate protobuf RPC interfaces (if you change .proto files)
# Requires: grpc-swift and swift-protobuf installed
make protos
```

---

## Relationship: `container` (CLI) ↔ `containerization` (library)

```
apple/container  (CLI tool, ~100% Swift)
      │
      └── depends on apple/containerization  (Swift package)
               │
               └── depends on Apple frameworks:
                       Virtualization.framework
                       vmnet.framework
                       Security.framework (Keychain)
                       XPC
                       Unified Logging
```

- **`apple/container`** — for users who want a Docker-like CLI on their Mac.
- **`apple/containerization`** — for developers building container management
  capabilities into their own Swift apps (CI runners, dev tools, build systems, etc.).
````
