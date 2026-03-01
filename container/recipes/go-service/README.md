# Go Service (multi-stage build)

Demonstrates a two-stage Dockerfile that produces a **minimal scratch image**:
the build stage compiles a statically-linked Go binary; the runtime stage is
`FROM scratch` — containing only the binary and TLS certificates.

Typical final image size: **< 10 MiB** vs ~300 MiB with the Go toolchain included.

## Build & Run

```bash
# Build
container build -t go-service:latest .

# Verify image is tiny
container image list --verbose

# Run
container run -d --name svc --rm go-service:latest

# Test
SVC_IP=$(container inspect svc | python3 -c \
  "import sys,json; d=json.load(sys.stdin); print(d[0]['networks'][0]['address'].split('/')[0])")

curl http://$SVC_IP:8080/health
curl http://$SVC_IP:8080/items
curl -X POST http://$SVC_IP:8080/items \
     -H 'Content-Type: application/json' \
     -d '{"name":"Widget C"}'
```

## Multi-arch build

The Dockerfile currently cross-compiles explicitly for `linux/arm64`. For a
true fat manifest supporting both arm64 and amd64:

```bash
# Remove the explicit GOARCH from the Dockerfile (let `container build` set it),
# then:
container build --arch arm64 --arch amd64 -t go-service:latest .
```

## Key Points

- `CGO_ENABLED=0` + `GOOS=linux` ensures static linking (no libc dependency).
- `-ldflags="-s -w"` strips debug info, cutting binary size significantly.
- `-trimpath` removes local filesystem paths from the binary (reproducibility +
  privacy).
- The `scratch` base image has no shell, package manager, or OS utilities —
  the container's attack surface is just your binary.
- Copy `ca-certificates.crt` if your service makes outbound HTTPS requests.
