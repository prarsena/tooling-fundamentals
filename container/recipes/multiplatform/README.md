# Multiplatform Images (arm64 + amd64)

`apple/container` can build and run images for both `linux/arm64` (native on
Apple Silicon) and `linux/amd64` (via Rosetta 2 — near-native performance,
no slow QEMU emulation).

A multiplatform ("fat manifest") image is a single tag that contains variants
for multiple architectures. Registries serve the right variant automatically
based on the pulling machine's architecture.

## Build a fat manifest

```bash
cd container/recipes/multiplatform

# Build both architectures (amd64 uses Rosetta under the hood)
container build \
    --arch arm64 \
    --arch amd64 \
    -t ghcr.io/myorg/multiplatform-demo:latest \
    .

# Verify both variants exist
container image inspect ghcr.io/myorg/multiplatform-demo:latest | \
    python3 -c "import sys,json; d=json.load(sys.stdin); \
    [print(v['platform']) for v in d[0].get('variants',[])]"
```

## Run specific architectures

```bash
# Native arm64 (default on Apple Silicon)
container run --arch arm64 --rm ghcr.io/myorg/multiplatform-demo:latest uname -m
# → aarch64

# amd64 via Rosetta (transparent x86_64 emulation)
container run --arch amd64 --rm ghcr.io/myorg/multiplatform-demo:latest uname -m
# → x86_64
```

## Push the fat manifest

```bash
container registry login ghcr.io
container image push ghcr.io/myorg/multiplatform-demo:latest
```

## Rosetta configuration

Rosetta is used by default for `amd64` builds and runs on Apple Silicon.
To disable (forces slower QEMU emulation instead):

```bash
container system property set build.rosetta false
```

## Platform detection in Dockerfile

Use `TARGETARCH` and `TARGETOS` build args (automatically set by the builder):

```dockerfile
ARG TARGETARCH
RUN echo "Building for $TARGETARCH"
```

Or download architecture-specific binaries:

```dockerfile
ARG TARGETARCH
RUN if [ "$TARGETARCH" = "arm64" ]; then \
      wget https://example.com/tool-arm64 -O /usr/local/bin/tool; \
    else \
      wget https://example.com/tool-amd64 -O /usr/local/bin/tool; \
    fi
```
