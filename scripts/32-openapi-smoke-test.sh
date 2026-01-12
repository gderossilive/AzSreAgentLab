#!/usr/bin/env bash
set -euo pipefail

# OpenAPI-driven smoke test for the deployed Octopets backend.
# - Fetches the live OpenAPI document at: $OCTOPETS_API_URL/openapi/v1.json
# - Selects a small set of safe GET endpoints (no path params, no required query params, no auth)
# - Calls them and fails (non-zero exit) on any non-2xx response.
#
# Usage (from repo root):
#   scripts/32-openapi-smoke-test.sh
#
# Notes:
# - Uses python3 (standard library only).

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$repo_root"

# Load .env for this process.
# shellcheck disable=SC1091
source "$repo_root/scripts/load-env.sh"

: "${OCTOPETS_API_URL:?Missing OCTOPETS_API_URL (run scripts/31-deploy-octopets-containers.sh first)}"

python3 - <<'PY'
import json
import os
import sys
import urllib.error
import urllib.request

base = os.environ.get("OCTOPETS_API_URL", "").rstrip("/")
openapi_url = f"{base}/openapi/v1.json"

def fetch(url: str, accept: str = "application/json", timeout: int = 20):
    req = urllib.request.Request(url, headers={"Accept": accept})
    with urllib.request.urlopen(req, timeout=timeout) as resp:
        code = getattr(resp, "status", None) or resp.getcode()
        body = resp.read()
        content_type = resp.headers.get("content-type", "")
        return code, content_type, body

print(f"OpenAPI smoke test against: {base}")
print(f"Fetching OpenAPI: {openapi_url}")

try:
    code, content_type, body = fetch(openapi_url)
except Exception as e:
    print(f"FAIL: could not fetch OpenAPI: {e}")
    sys.exit(2)

if code != 200:
    print(f"FAIL: OpenAPI returned HTTP {code}")
    sys.exit(2)

try:
    spec = json.loads(body.decode("utf-8"))
except Exception as e:
    print(f"FAIL: OpenAPI JSON parse error: {e}")
    sys.exit(2)

info = spec.get("info") or {}
print(f"API: {info.get('title')} (version {info.get('version')})")

paths = spec.get("paths") or {}

global_security = spec.get("security")
if global_security is None:
    global_security = []

safe_gets: list[str] = []

for path, ops in paths.items():
    if not isinstance(ops, dict):
        continue

    # Avoid path params like /api/foo/{id}
    if "{" in path or "}" in path:
        continue

    get = ops.get("get")
    if not isinstance(get, dict):
        continue

    # Skip endpoints requiring auth.
    # OpenAPI: empty list means "no auth required".
    op_security = get.get("security", global_security)
    if op_security:
        continue

    params = get.get("parameters") or []
    required = False
    for p in params:
        if isinstance(p, dict) and p.get("required") is True:
            required = True
            break
    if required:
        continue

    safe_gets.append(path)

# Keep the probe small and deterministic.
# Prefer health and debug-ish endpoints first.
def score(p: str) -> tuple[int, str]:
    pl = p.lower()
    if "health" in pl:
        return (0, p)
    if "debug" in pl:
        return (1, p)
    if "openapi" in pl:
        return (2, p)
    return (3, p)

safe_gets = sorted(set(safe_gets), key=score)

if not safe_gets:
    print("WARN: no safe unauthenticated GET endpoints found in OpenAPI; nothing to probe.")
    sys.exit(0)

candidates = safe_gets[:12]
print("Candidate GET endpoints (unauthenticated, no required params):")
for p in candidates:
    print(f"- {p}")

failures = 0

for p in candidates:
    url = base + p
    try:
        code, content_type, _ = fetch(url)
        ok = 200 <= code < 300
        print(f"GET {p:35s} -> {code} ({content_type.split(';')[0]})")
        if not ok:
            failures += 1
    except urllib.error.HTTPError as e:
        print(f"GET {p:35s} -> {e.code} (HTTPError)")
        failures += 1
    except Exception as e:
        print(f"GET {p:35s} -> ERROR ({e})")
        failures += 1

if failures:
    print(f"FAIL: {failures} endpoint(s) did not return 2xx")
    sys.exit(1)

print("PASS: OpenAPI smoke test succeeded")
PY
