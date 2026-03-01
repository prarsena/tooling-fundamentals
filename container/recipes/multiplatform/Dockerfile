# Multiplatform demo image
# Shows: TARGETARCH/TARGETOS, per-arch downloads, and uname output at runtime.

FROM docker.io/alpine:latest

# TARGETARCH and TARGETOS are injected by `container build --arch` automatically.
ARG TARGETARCH
ARG TARGETOS

# Install curl for demo purposes
RUN apk add --no-cache curl

# Show build-time platform info in the image layer
RUN echo "Built for: ${TARGETOS}/${TARGETARCH}" > /etc/build-platform

# At runtime, print the architecture
CMD ["sh", "-c", "echo 'Build platform:' && cat /etc/build-platform && echo 'Runtime uname:' && uname -m"]
