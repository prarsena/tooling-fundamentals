# Python Web Server

Serves a static HTML page on port 80 using Python's built-in HTTP server.
This mirrors the official `apple/container` tutorial exactly.

## Files

- `Dockerfile` — builds the image
- `index.html` — the page being served

## Build & Run

```bash
# Build
container build -t web-test:latest .

# Run in background (gets its own IP on the vmnet bridge)
container run -d --name web --rm web-test:latest

# If you have set up DNS:
#   sudo container system dns create test
#   container system property set dns.domain test
open http://web.test

# Or use the container's IP directly:
container inspect web | python3 -c \
  "import sys,json; d=json.load(sys.stdin); print('http://'+d[0]['networks'][0]['address'].split('/')[0])"

# Forward to localhost on port 8080:
container run -d --name web -p 8080:80 --rm web-test:latest
curl http://127.0.0.1:8080

# Stream logs
container logs -f web

# Exec in
container exec -it web sh

# Stop (--rm removes it automatically)
container stop web
```

## Multi-arch

```bash
container build --arch arm64 --arch amd64 -t web-test:latest .
container run --arch amd64 --rm web-test:latest uname -m   # → x86_64 (via Rosetta)
```
