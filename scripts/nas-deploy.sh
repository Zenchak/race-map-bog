#!/usr/bin/env bash
set -Eeuo pipefail

REPO_SLUG="Zenchak/race-map-bog"
ROOT="${NAS_SITES_ROOT:-/volume1/docker/bogdan-sites}"
EXPECTED_SHA="${1:-${GITHUB_SHA:-}}"
STATUS_ROOT="${ROOT}/deploy-status-race-map.json"
PORT="${RACE_HUB_PORT:-8082}"

json_escape() {
  python3 -c 'import json,sys; print(json.dumps(sys.stdin.read())[1:-1])'
}

write_status() {
  local status="$1"
  local message="$2"
  local sha="${3:-}"
  local deploy_path="${4:-}"
  local now
  now="$(date -u +"%Y-%m-%dT%H:%M:%SZ")"
  local msg_escaped path_escaped
  msg_escaped="$(printf '%s' "$message" | json_escape)"
  path_escaped="$(printf '%s' "$deploy_path" | json_escape)"
  cat > "$STATUS_ROOT" <<EOF
{
  "service": "race-map-bog",
  "status": "$status",
  "deployed_sha": "$sha",
  "expected_sha": "$EXPECTED_SHA",
  "deployed_at": "$now",
  "deploy_path": "$path_escaped",
  "local_url": "http://127.0.0.1:$PORT/",
  "message": "$msg_escaped"
}
EOF
  if [[ -n "$deploy_path" && -d "$deploy_path" ]]; then
    cp "$STATUS_ROOT" "$deploy_path/deploy-status.json" 2>/dev/null || true
  fi
}

DEPLOY_DIR=""

on_error() {
  local code=$?
  local line="${BASH_LINENO[0]:-unknown}"
  local sha=""
  if [[ -n "$DEPLOY_DIR" && -d "$DEPLOY_DIR/.git" ]]; then
    sha="$(git -C "$DEPLOY_DIR" rev-parse HEAD 2>/dev/null || true)"
  fi
  write_status "ERROR" "Deploy failed at line $line (exit $code)." "$sha" "$DEPLOY_DIR"
  exit "$code"
}
trap on_error ERR

echo "Finding local checkout for $REPO_SLUG under $ROOT ..."

while IFS= read -r -d '' gitdir; do
  dir="${gitdir%/.git}"
  origin="$(git -C "$dir" remote get-url origin 2>/dev/null || true)"
  case "$origin" in
    *github.com/Zenchak/race-map-bog*|*Zenchak/race-map-bog.git*)
      DEPLOY_DIR="$dir"
      break
      ;;
  esac
done < <(find "$ROOT" -maxdepth 6 -type d -name .git -print0 2>/dev/null)

if [[ -z "$DEPLOY_DIR" ]]; then
  for candidate in     "$ROOT/race-map-bog"     "$ROOT/gare/race-map-bog"     "$ROOT/gare"     "$ROOT/sites/race-map-bog"; do
    if [[ -d "$candidate/.git" ]]; then
      origin="$(git -C "$candidate" remote get-url origin 2>/dev/null || true)"
      if [[ "$origin" == *"Zenchak/race-map-bog"* ]]; then
        DEPLOY_DIR="$candidate"
        break
      fi
    fi
  done
fi

if [[ -z "$DEPLOY_DIR" ]]; then
  write_status "ERROR" "Could not find a local Git checkout whose origin is Zenchak/race-map-bog." "" ""
  echo "ERROR: race-map-bog checkout not found under $ROOT" >&2
  exit 20
fi

echo "Deploy path: $DEPLOY_DIR"

git -C "$DEPLOY_DIR" fetch --prune origin main
git -C "$DEPLOY_DIR" reset --hard origin/main

DEPLOYED_SHA="$(git -C "$DEPLOY_DIR" rev-parse HEAD)"
echo "Deployed SHA: $DEPLOYED_SHA"

if [[ -n "$EXPECTED_SHA" && "$DEPLOYED_SHA" != "$EXPECTED_SHA" ]]; then
  write_status "ERROR" "Local checkout did not reach the expected GitHub SHA." "$DEPLOYED_SHA" "$DEPLOY_DIR"
  echo "ERROR: expected $EXPECTED_SHA, deployed $DEPLOYED_SHA" >&2
  exit 21
fi

for required in index.html app.html extra-races.js; do
  if [[ ! -s "$DEPLOY_DIR/$required" ]]; then
    write_status "ERROR" "Required file missing after deployment: $required" "$DEPLOYED_SHA" "$DEPLOY_DIR"
    echo "ERROR: required file missing: $required" >&2
    exit 22
  fi
done

if ! grep -q 'loadExtraRaces' "$DEPLOY_DIR/app.html"; then
  write_status "ERROR" "app.html is present but the HUB extra-race loader is missing." "$DEPLOYED_SHA" "$DEPLOY_DIR"
  exit 23
fi
if ! grep -q 'baseFilterState' "$DEPLOY_DIR/app.html"; then
  write_status "ERROR" "app.html is present but the combined-filter fix is missing." "$DEPLOYED_SHA" "$DEPLOY_DIR"
  exit 24
fi
if ! grep -q 'window.EXTRA_RACES' "$DEPLOY_DIR/extra-races.js"; then
  write_status "ERROR" "extra-races.js is present but does not expose window.EXTRA_RACES." "$DEPLOYED_SHA" "$DEPLOY_DIR"
  exit 25
fi

# The race site is static: no container restart should be required.
# Verify the exact content being served by the NAS after the checkout update.
sleep 2

TMPDIR_LOCAL="$(mktemp -d)"
trap 'rm -rf "$TMPDIR_LOCAL"' EXIT

curl --fail --silent --show-error --max-time 10 "http://127.0.0.1:$PORT/" -o "$TMPDIR_LOCAL/index.html"
curl --fail --silent --show-error --max-time 10 "http://127.0.0.1:$PORT/app.html" -o "$TMPDIR_LOCAL/app.html"
curl --fail --silent --show-error --max-time 10 "http://127.0.0.1:$PORT/extra-races.js" -o "$TMPDIR_LOCAL/extra-races.js"

if ! grep -q 'Calendario Gare' "$TMPDIR_LOCAL/index.html"; then
  write_status "ERROR" "NAS port $PORT answered, but the expected Calendario Gare page was not served." "$DEPLOYED_SHA" "$DEPLOY_DIR"
  exit 26
fi
if ! grep -q 'loadExtraRaces' "$TMPDIR_LOCAL/app.html"; then
  write_status "ERROR" "NAS is serving a stale app.html without the current HUB loader." "$DEPLOYED_SHA" "$DEPLOY_DIR"
  exit 27
fi
if ! grep -q 'baseFilterState' "$TMPDIR_LOCAL/app.html"; then
  write_status "ERROR" "NAS is serving a stale app.html without the current filter fix." "$DEPLOYED_SHA" "$DEPLOY_DIR"
  exit 28
fi
if ! grep -q 'window.EXTRA_RACES' "$TMPDIR_LOCAL/extra-races.js"; then
  write_status "ERROR" "NAS is serving an invalid or stale extra-races.js." "$DEPLOYED_SHA" "$DEPLOY_DIR"
  exit 29
fi

write_status "OK" "GitHub checkout updated and NAS port $PORT is serving the expected HUB files." "$DEPLOYED_SHA" "$DEPLOY_DIR"

echo "DEPLOY_OK"
cat "$STATUS_ROOT"
