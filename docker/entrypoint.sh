#!/bin/bash -e

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
