"""Minimal reverse-geocoding-to-postcode API in front of a local Nominatim instance.

Deliberately stdlib-only (no FastAPI/Flask) so the Docker image doesn't need
any extra pip installs on top of the base Nominatim image.
"""

import json
import os
import urllib.parse
import urllib.request
import urllib.error
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer

NOMINATIM_URL = "http://127.0.0.1:8080"
PORT = int(os.environ.get("PORT", "8000"))
API_KEY = os.environ.get("API_KEY")


def call_nominatim_reverse(lat, lon):
    query = urllib.parse.urlencode(
        {"lat": lat, "lon": lon, "format": "jsonv2", "zoom": 18}
    )
    url = f"{NOMINATIM_URL}/reverse?{query}"
    with urllib.request.urlopen(url, timeout=30) as resp:
        return json.loads(resp.read())


def nominatim_is_healthy():
    try:
        with urllib.request.urlopen(f"{NOMINATIM_URL}/status", timeout=5) as resp:
            return resp.status == 200
    except (urllib.error.URLError, OSError):
        return False


class Handler(BaseHTTPRequestHandler):
    server_version = "postcode-wrapper/1.0"

    def log_message(self, fmt, *args):
        print("%s - %s" % (self.address_string(), fmt % args))

    def _send_json(self, status, payload):
        body = json.dumps(payload).encode("utf-8")
        self.send_response(status)
        self.send_header("Content-Type", "application/json")
        self.send_header("Content-Length", str(len(body)))
        self.send_header("Access-Control-Allow-Origin", "*")
        self.end_headers()
        self.wfile.write(body)

    def _authorized(self):
        if not API_KEY:
            return True
        return self.headers.get("X-API-Key") == API_KEY

    def do_GET(self):
        parsed = urllib.parse.urlparse(self.path)
        params = urllib.parse.parse_qs(parsed.query)

        if parsed.path == "/health":
            if nominatim_is_healthy():
                self._send_json(200, {"status": "ok"})
            else:
                self._send_json(503, {"status": "nominatim unavailable"})
            return

        if parsed.path == "/postcode":
            if not self._authorized():
                self._send_json(401, {"error": "invalid or missing API key"})
                return

            try:
                lat = float(params["lat"][0])
                lon = float(params["lon"][0])
            except (KeyError, IndexError, ValueError):
                self._send_json(
                    400, {"error": "lat and lon query params are required and must be numeric"}
                )
                return

            if not (-90 <= lat <= 90) or not (-180 <= lon <= 180):
                self._send_json(400, {"error": "lat/lon out of range"})
                return

            try:
                result = call_nominatim_reverse(lat, lon)
            except urllib.error.URLError as exc:
                self._send_json(502, {"error": f"nominatim request failed: {exc}"})
                return

            postcode = result.get("address", {}).get("postcode")
            if not postcode:
                self._send_json(404, {"error": "no postcode found for this location"})
                return

            self._send_json(200, {"postcode": postcode})
            return

        self._send_json(404, {"error": "not found"})

    def do_OPTIONS(self):
        self.send_response(204)
        self.send_header("Access-Control-Allow-Origin", "*")
        self.send_header("Access-Control-Allow-Methods", "GET, OPTIONS")
        self.send_header("Access-Control-Allow-Headers", "X-API-Key")
        self.end_headers()


if __name__ == "__main__":
    server = ThreadingHTTPServer(("0.0.0.0", PORT), Handler)
    print(f"Wrapper API listening on :{PORT}")
    server.serve_forever()
