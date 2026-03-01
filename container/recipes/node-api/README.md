# Node.js API

A minimal Express REST API demonstrating volume mounts for live-reload dev
workflows with `apple/container`.

## Build & Run (production)

```bash
# Install deps first (needs npm or Docker; here we build the image)
container build -t node-api:latest .

# Run in background
container run -d --name api --rm node-api:latest

# Test it
API_IP=$(container inspect api | python3 -c \
  "import sys,json; d=json.load(sys.stdin); print(d[0]['networks'][0]['address'].split('/')[0])")

curl http://$API_IP:3000/health
curl http://$API_IP:3000/items
curl -X POST http://$API_IP:3000/items -H 'Content-Type: application/json' -d '{"name":"Widget C"}'
curl http://$API_IP:3000/items/3
curl -X DELETE http://$API_IP:3000/items/1

# With port forward to localhost:
container run -d --name api -p 3000:3000 --rm node-api:latest
curl http://127.0.0.1:3000/health
```

## Development with live reload (volume mount)

```bash
# Mount source code from host into the container for hot-reload
container run -it --rm \
  -v "$PWD/src:/app/src" \
  -p 3000:3000 \
  --name api-dev \
  docker.io/node:20-alpine \
  sh -c "cd /app && npm install && node --watch src/index.js"
```

## Connect from another container (macOS 26+)

```bash
container run -d --name api --rm node-api:latest

# Hit the API from a second container using DNS (requires dns-create test)
container run --rm alpine/curl curl http://api.test:3000/health
```
