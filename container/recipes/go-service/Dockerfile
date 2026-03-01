# ---- Build stage ----
# Use BUILDPLATFORM so the toolchain always runs natively on the host.
# The binary is cross-compiled for TARGETPLATFORM via GOOS/GOARCH below.
FROM --platform=$BUILDPLATFORM docker.io/golang:1.24-alpine AS builder

# TARGETOS / TARGETARCH are injected automatically by `container build --arch`.
ARG TARGETOS=linux
ARG TARGETARCH=arm64

WORKDIR /build

# Cache module downloads separately from source compilation.
# go.sum must exist — omitting it skips module verification (supply-chain risk).
COPY go.mod go.sum ./
RUN go mod download && go mod verify

COPY . .

# Cross-compile a fully static binary for the target platform.
RUN CGO_ENABLED=0 GOOS=${TARGETOS} GOARCH=${TARGETARCH} \
    go build -ldflags="-s -w" -trimpath -o /go-service ./cmd/server

# ---- Runtime stage ----
# scratch = empty filesystem; the binary is the only thing in the image.
# Result: < 10 MiB image vs ~300 MiB with the Go toolchain.
FROM scratch

# TLS root certs (required if the server makes outbound HTTPS calls).
COPY --from=builder /etc/ssl/certs/ca-certificates.crt /etc/ssl/certs/

COPY --from=builder /go-service /go-service

EXPOSE 8080

# Run as nobody (65534) rather than root. In a scratch image there is no
# /etc/passwd so we use numeric UID:GID directly.
USER 65534:65534

ENTRYPOINT ["/go-service"]
