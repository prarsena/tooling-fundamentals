# Stage 1: Build the wrapper binary.
# --platform=$BUILDPLATFORM: toolchain runs natively on the build host.
# TARGETARCH/TARGETOS: injected by `container build --arch` for cross-compile.
FROM --platform=$BUILDPLATFORM docker.io/golang:1.24-alpine AS gobuilder

ARG TARGETOS=linux
ARG TARGETARCH=arm64

WORKDIR /build
COPY wrapper.go .

# Statically link so the binary runs in the vminit image with no libc dependency.
RUN CGO_ENABLED=0 GOOS=${TARGETOS} GOARCH=${TARGETARCH} go build -o wrapper wrapper.go

# Stage 2: Build the custom init image
# Start from the official vminitd image which provides the real /sbin/vminitd
FROM ghcr.io/apple/containerization/vminit:latest

# Move the real vminitd out of the way
COPY --from=ghcr.io/apple/containerization/vminit:latest /sbin/vminitd /sbin/vminitd.real

# Install our wrapper as the new /sbin/vminitd
COPY --from=gobuilder /build/wrapper /sbin/vminitd
