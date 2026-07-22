# nominatim-api

A self-hosted, Antioquia-only Nominatim instance with a minimal HTTP API that
returns a postcode for a given latitude/longitude. Built to deploy as a
single Docker service on [Railway](https://railway.app).

It wraps the [`mediagis/nominatim`](https://github.com/mediagis/nominatim-docker)
all-in-one image (Postgres + PostGIS + osm2pgsql + Nominatim's API server in
one container) and imports only the Antioquia department (`address` import
style, reverse-lookup-only) to keep the dataset light — no search index, no
POI data, just what's needed to resolve a coordinate down to a postcode.

Scoped down from full-country Colombia coverage because Geofabrik doesn't
offer department-level extracts and the full country import doesn't fit
under Railway's 5GB Hobby-plan volume cap. The Antioquia extract
(`data/antioquia-latest.osm.pbf`, bbox-clipped from the full Colombia PBF
with `osmium extract`) is ~64MB vs. the full country's ~307MB. See
"Changing region" below to restore full coverage on a larger volume.

## API

### `GET /postcode?lat=<float>&lon=<float>`

```sh
curl "http://localhost:8000/postcode?lat=4.7110&lon=-74.0721"
# {"postcode": "110111"}
```

Returns `404` with `{"error": "no postcode found for this location"}` if
Nominatim has no result, or if OSM simply has no postcode tagged at that
location (coverage in Colombia is incomplete in rural areas — this is a
legitimate response, not a bug).

If `API_KEY` is set, requests must include a matching `X-API-Key` header or
they get `401`.

### `GET /health`

Returns `200 {"status": "ok"}` when the underlying Nominatim instance is up,
`503` otherwise. Used as Railway's healthcheck target.

## Local development

```sh
cp .env.example .env
docker compose up --build
```

First run downloads and imports the Colombia OSM extract (~307MB PBF) —
expect this to take anywhere from several minutes to over an hour depending
on your machine. Subsequent `docker compose up` runs skip the import (data
persists in the `nominatim-data` volume).

```sh
curl "http://localhost:8000/postcode?lat=4.7110&lon=-74.0721"   # Bogotá
curl http://localhost:8000/health
curl "http://localhost:8080/status"                              # Nominatim itself, for debugging
```

## Deploying to Railway

1. Push this repo to GitHub and create a new Railway service from it.
   Railway will auto-detect `railway.json` and build the `Dockerfile`.
2. **Attach a Volume** to the service in the Railway dashboard, mounted at
   `/var/lib/postgresql/16/main`. Start at **10GB** — Railway bills per GB
   actually used (~$0.25/GB/month) and resizes live with no downtime, so
   there's no cost to starting small and growing later. Without this volume,
   every redeploy re-imports Colombia from scratch.
3. Set service variables:
   - `NOMINATIM_PASSWORD` — any secure password (used internally only).
   - `RAILWAY_SHM_SIZE_BYTES` — e.g. `1073741824` (1GB). **Required.** Docker's
     default 64MB `/dev/shm` is too small for Nominatim's import and causes a
     misleading "no space left on device" error even when disk is fine.
   - `API_KEY` — optional, protects `/postcode` with a header check.
4. Deploy. The first deploy imports Colombia and can take **30–90+ minutes**;
   `railway.json` sets a generous healthcheck timeout so Railway doesn't kill
   the deploy while this is in progress. Watch the deploy logs for
   `"Nominatim is healthy, starting wrapper API"`.
5. Recommended plan sizing: **≥4GB RAM**, 10GB volume to start (per above).

### Changing region

To cover a different area, override `PBF_URL` as a service variable with
either a [Geofabrik](https://download.geofabrik.de) `.osm.pbf` URL (country-level
only — no sub-national extracts for Colombia) or a custom bbox-clipped extract
like `data/antioquia-latest.osm.pbf` (see below for how that one was made).
Re-importing requires clearing the Railway volume (or starting a fresh
service) since the existing import marker will otherwise be reused.

To restore full Colombia coverage, either move to a plan/volume without the
5GB cap and set `PBF_URL` back to
`https://download.geofabrik.de/south-america/colombia-latest.osm.pbf`, or clip
a larger custom region the same way Antioquia was extracted:

```sh
docker run --rm -v "$(pwd)/data:/data" debian:bookworm-slim bash -c "
  apt-get update -qq && apt-get install -y -qq osmium-tool
  osmium extract -b <left>,<bottom>,<right>,<top> --strategy=smart \
    /data/colombia-latest.osm.pbf -o /data/custom-region.osm.pbf
"
```

Commit the resulting file under `data/` and point `PBF_URL` at its raw
GitHub URL (or any other HTTPS host).

## How it works

The container's entrypoint (`docker/entrypoint.sh`) starts Nominatim's own
bootstrap process (`/app/start.sh` — handles the one-time import, Postgres,
and Nominatim's API server on internal port `8080`) in the background, waits
for it to report healthy, then execs a small stdlib-only Python HTTP wrapper
(`wrapper/main.py`) in the foreground bound to Railway's `$PORT`. Only the
wrapper is exposed publicly; Nominatim's own API on `8080` stays internal,
so the full search API is never exposed — only the filtered `/postcode`
endpoint.
