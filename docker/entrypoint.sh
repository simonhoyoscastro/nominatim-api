#!/bin/bash -e

PGDATA=/var/lib/postgresql/16/main

# Railway (and other block-storage volume providers) format the volume with
# a filesystem that leaves a lost+found dir at the mount root. initdb refuses
# to initialize into a non-empty directory, so on a fresh volume it fails
# every time with "directory exists but is not empty". Only strip it when
# Postgres hasn't been initialized yet (PG_VERSION doesn't exist) so this is
# a no-op once real data is present.
if [ -d "$PGDATA/lost+found" ] && [ ! -f "$PGDATA/PG_VERSION" ]; then
  echo "Removing lost+found from fresh volume mount so initdb can proceed"
  rm -rf "$PGDATA/lost+found"
fi

# Nominatim's own start.sh does the import (first boot only, guarded by an
# on-disk marker file), starts Postgres, and daemonizes gunicorn on :8080.
# It never returns while running, so we background it and wait for it to
# become healthy before handing off to our wrapper API in the foreground.
/app/start.sh &
NOMINATIM_PID=$!

echo "Waiting for Nominatim to become healthy on :8080 (this can take a while on first boot while Colombia imports)..."

until curl -sf http://127.0.0.1:8080/status >/dev/null 2>&1; do
  if ! kill -0 "$NOMINATIM_PID" 2>/dev/null; then
    echo "Nominatim process exited before becoming healthy" >&2
    exit 1
  fi
  sleep 5
done

echo "Nominatim is healthy, starting wrapper API"

exec python3 /app/wrapper/main.py
