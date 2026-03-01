# Custom Init Image

Each `apple/container` container runs inside a micro-VM with `vminitd` as PID 1.
A *custom init image* wraps `vminitd` so you can inject VM-level boot logic that
runs **before** the OCI container process starts.

Use cases:
- Load eBPF programs into the VM kernel at boot.
- Start an extra daemon (logging agent, telemetry sidecar) in the VM.
- Debug or instrument the init process.
- Run custom network setup (e.g. configure a bridge, load a kernel module).

## How it works

1. Your custom init image is based on `ghcr.io/apple/containerization/vminit:latest`.
2. You replace `/sbin/vminitd` with a wrapper binary.
3. The wrapper does its work, then `exec`s the real `vminitd` (saved as `/sbin/vminitd.real`).
4. `vminitd` takes over as normal and starts your OCI container process.

## The wrapper (Go)

```go
// wrapper.go
package main

import (
    "os"
    "syscall"
)

func main() {
    // Write a message to the kernel log ring buffer
    kmsg, err := os.OpenFile("/dev/kmsg", os.O_WRONLY, 0)
    if err == nil {
        kmsg.WriteString("<6>custom-init: === CUSTOM INIT RUNNING ===\n")
        kmsg.Close()
    }

    // Hand off to the real vminitd
    if err := syscall.Exec("/sbin/vminitd.real", os.Args, os.Environ()); err != nil {
        os.Exit(1)
    }
}
```

## Build & Run

```bash
# 1. Build the wrapper binary for Linux arm64 (must match container arch)
CGO_ENABLED=0 GOOS=linux GOARCH=arm64 go build -o wrapper wrapper.go

# 2. Build the custom init image
container build -t local/custom-init:latest .

# 3. Use --init-image to run a container with your custom init
container run --name test-init --init-image local/custom-init:latest --rm \
    ubuntu:latest echo "hello"

# 4. Verify your custom init ran
container logs --boot test-init | grep custom-init
# Expected: [    0.129230] custom-init: === CUSTOM INIT RUNNING ===
```

## Files

- `wrapper.go` — the Go wrapper (exec's real vminitd)
- `Dockerfile` — builds the custom init image
- `README.md` — this file
