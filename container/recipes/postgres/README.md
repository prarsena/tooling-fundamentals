# PostgreSQL with Persistent Volume

Runs PostgreSQL 16 with a named volume so data survives container restarts and
removals. This recipe shows the canonical data-persistence pattern for stateful
services with `apple/container`.

## Why a volume?

`apple/container` runs each container in an ephemeral micro-VM. Without a volume,
the entire filesystem (including the database files) disappears when the container
is removed. A named volume persists independently of the container lifecycle.

## Quick Start

```bash
# 1. Create a dedicate volume for the database files
container volume create pgdata --size 20G

# 2. Run Postgres (first run initialises the database cluster)
container run -d \
  --name postgres \
  --rm \
  -v pgdata:/var/lib/postgresql/data \
  -e POSTGRES_PASSWORD=secret \
  -e POSTGRES_USER=myuser \
  -e POSTGRES_DB=mydb \
  docker.io/postgres:16-alpine

# 3. Wait ~3 seconds for Postgres to start, then connect
PG_IP=$(container inspect postgres | python3 -c \
  "import sys,json; d=json.load(sys.stdin); print(d[0]['networks'][0]['address'].split('/')[0])")

# Option A — psql in a second container (no local psql needed)
container run -it --rm docker.io/postgres:16-alpine \
  psql "postgresql://myuser:secret@$PG_IP:5432/mydb"

# Option B — forward port 5432 to localhost and use a local psql / GUI
container run -d \
  --name postgres \
  --rm \
  -p 127.0.0.1:5432:5432 \
  -v pgdata:/var/lib/postgresql/data \
  -e POSTGRES_PASSWORD=secret \
  -e POSTGRES_USER=myuser \
  -e POSTGRES_DB=mydb \
  docker.io/postgres:16-alpine

psql "postgresql://myuser:secret@localhost:5432/mydb"
```

## Data persistence test

```bash
# Create a table
container exec -it postgres psql -U myuser mydb \
  -c "CREATE TABLE notes (id SERIAL PRIMARY KEY, body TEXT);"

# Insert a row
container exec -it postgres psql -U myuser mydb \
  -c "INSERT INTO notes (body) VALUES ('Survives container restart!');"

# Stop the container (--rm removes it, but the volume persists)
container stop postgres

# Start a fresh container pointing at the same volume
container run -d --name postgres --rm \
  -v pgdata:/var/lib/postgresql/data \
  -e POSTGRES_PASSWORD=secret -e POSTGRES_USER=myuser -e POSTGRES_DB=mydb \
  docker.io/postgres:16-alpine

# The row is still there
container exec -it postgres psql -U myuser mydb -c "SELECT * FROM notes;"
```

## Connect from another container (macOS 26+)

```bash
# Start Postgres as above, named "postgres"
# Set up DNS domain (one-time):
#   sudo container system dns create test
#   container system property set dns.domain test

# Connect from your app container:
container run --rm docker.io/postgres:16-alpine \
  psql "postgresql://myuser:secret@postgres.test:5432/mydb" -c "SELECT 1;"
```

## Backup and restore

```bash
# Backup — pg_dump runs inside the container, tar is piped to host
container exec postgres pg_dump -U myuser mydb | gzip > mydb-backup.sql.gz

# Restore
gunzip -c mydb-backup.sql.gz | \
  container exec -i postgres psql -U myuser mydb

# Alternatively, save the full volume contents via a helper container:
container run --rm \
  -v pgdata:/data:ro \
  -v "$PWD":/backup \
  docker.io/alpine:latest \
  tar czf /backup/pgdata-backup.tgz -C /data .

# Restore the volume:
container volume create pgdata-restored
container run --rm \
  -v pgdata-restored:/data \
  -v "$PWD":/backup \
  docker.io/alpine:latest \
  sh -c "cd /data && tar xzf /backup/pgdata-backup.tgz"
```

## Cleanup

```bash
container stop postgres
container volume rm pgdata    # WARNING: destroys all database data
# or just remove stale/unreferenced volumes in bulk:
container volume prune
```
