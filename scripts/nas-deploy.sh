#!/usr/bin/env bash
set -Eeuo pipefail

ROOT="/volume1/docker/bogdan-sites"
LIVE_DIR="${RACE_HUB_LIVE_DIR:-/sites/race-map-bog}"
EXPECTED_SHA="${1:-${GITHUB_SHA:-}}"
SOURCE_DIR="${GITHUB_WORKSPACE:-$(pwd)}"
STATUS_ROOT="$ROOT/deploy-status-race-map.json"
PORT="${RACE_HUB_PORT:-8082}"
TMPDIR_LOCAL=""

write_status() {
  local status="$1" message="$2" sha="${3:-}" path="${4:-}"
  local now
  now="$(date -u +"%Y-%m-%dT%H:%M:%SZ")"
  jq -n     --arg service "race-map-bog"     --arg status "$status"     --arg deployed_sha "$sha"     --arg expected_sha "$EXPECTED_SHA"     --arg deployed_at "$now"     --arg deploy_path "$path"     --arg local_url "http://127.0.0.1:$PORT/"     --arg message "$message"     '{service:$service,status:$status,deployed_sha:$deployed_sha,expected_sha:$expected_sha,deployed_at:$deployed_at,deploy_path:$deploy_path,local_url:$local_url,message:$message}'     > "$STATUS_ROOT"
  [[ -d "$path" ]] && cp "$STATUS_ROOT" "$path/deploy-status.json" 2>/dev/null || true
}

cleanup(){ [[ -n "$TMPDIR_LOCAL" && -d "$TMPDIR_LOCAL" ]] && rm -rf "$TMPDIR_LOCAL" || true; }
trap cleanup EXIT
trap 'code=$?; write_status "ERROR" "Deploy failed at line ${BASH_LINENO[0]:-unknown} (exit $code)." "$EXPECTED_SHA" "$LIVE_DIR" || true; exit $code' ERR

echo "SOURCE_DIR=$SOURCE_DIR"
echo "LIVE_DIR=$LIVE_DIR"

if [[ ! -d /sites ]]; then
  write_status "ERROR" "Runner cannot see the Docker volume mounted at /sites." "$EXPECTED_SHA" "$LIVE_DIR"
  echo "ERROR: /sites is not mounted in the runner container." >&2
  exit 20
fi

if [[ ! -d "$LIVE_DIR" ]]; then
  write_status "ERROR" "Live HUB directory does not exist: $LIVE_DIR" "$EXPECTED_SHA" "$LIVE_DIR"
  echo "ERROR: live HUB directory missing: $LIVE_DIR" >&2
  exit 21
fi

for required in index.html app.html extra-races.js hub-overlay.js; do
  [[ -s "$SOURCE_DIR/$required" ]] || {
    write_status "ERROR" "Source checkout missing $required." "$EXPECTED_SHA" "$LIVE_DIR"
    exit 22
  }
done

BACKUP_DIR="$LIVE_DIR/.deploy-backup"
mkdir -p "$BACKUP_DIR"
for file in index.html app.html extra-races.js feasibility.js hub-overlay.js; do
  [[ -f "$LIVE_DIR/$file" ]] && cp "$LIVE_DIR/$file" "$BACKUP_DIR/$file.previous" || true
done

install -m 0644 "$SOURCE_DIR/index.html" "$LIVE_DIR/index.html"
install -m 0644 "$SOURCE_DIR/app.html" "$LIVE_DIR/app.html"
install -m 0644 "$SOURCE_DIR/extra-races.js" "$LIVE_DIR/extra-races.js"
install -m 0644 "$SOURCE_DIR/hub-overlay.js" "$LIVE_DIR/hub-overlay.js"
install -m 0644 "$SOURCE_DIR/hub-overlay.js" "$LIVE_DIR/legacy/hub-overlay.js"
[[ -f "$SOURCE_DIR/feasibility.js" ]] && install -m 0644 "$SOURCE_DIR/feasibility.js" "$LIVE_DIR/feasibility.js"

# Ensure the legacy page runs the direct HUB renderer in its own document.
if ! grep -q 'hub-overlay.js' "$LIVE_DIR/legacy/index.html"; then
  sed -i 's#</body>#<script src="/legacy/hub-overlay.js?build=202610130805"></script></body>#' "$LIVE_DIR/legacy/index.html"
else
  sed -i 's#hub-overlay.js[^"]*#hub-overlay.js?build=202610130805#g' "$LIVE_DIR/legacy/index.html"
fi

grep -q "HUB build 2026.10.13-0805" "$LIVE_DIR/app.html"
grep -q "window.EXTRA_RACES" "$LIVE_DIR/extra-races.js"
grep -q "hub-overlay.js" "$LIVE_DIR/legacy/index.html"
grep -q "HUB 2026.10.13-0805" "$LIVE_DIR/legacy/hub-overlay.js"

TMPDIR_LOCAL="$(mktemp -d)"
sleep 2
curl --fail --silent --show-error --max-time 10 "http://127.0.0.1:$PORT/" -o "$TMPDIR_LOCAL/index.html"
curl --fail --silent --show-error --max-time 10 "http://127.0.0.1:$PORT/app.html?deploy=$EXPECTED_SHA" -o "$TMPDIR_LOCAL/app.html"
curl --fail --silent --show-error --max-time 10 "http://127.0.0.1:$PORT/extra-races.js?deploy=$EXPECTED_SHA" -o "$TMPDIR_LOCAL/extra-races.js"
curl --fail --silent --show-error --max-time 10 "http://127.0.0.1:$PORT/legacy/index.html?deploy=$EXPECTED_SHA" -o "$TMPDIR_LOCAL/legacy-index.html"
curl --fail --silent --show-error --max-time 10 "http://127.0.0.1:$PORT/legacy/hub-overlay.js?deploy=$EXPECTED_SHA" -o "$TMPDIR_LOCAL/hub-overlay.js"

grep -q "Calendario Gare" "$TMPDIR_LOCAL/index.html"
grep -q "HUB build 2026.10.13-0805" "$TMPDIR_LOCAL/app.html"
grep -q "window.EXTRA_RACES" "$TMPDIR_LOCAL/extra-races.js"
grep -q "hub-overlay.js" "$TMPDIR_LOCAL/legacy-index.html"
grep -q "HUB 2026.10.13-0805" "$TMPDIR_LOCAL/hub-overlay.js"

RACE_COUNT="$(grep -oE '"?id"?[[:space:]]*:' "$TMPDIR_LOCAL/extra-races.js" | wc -l | tr -d ' ')"
[[ "$RACE_COUNT" -ge 50 ]] || {
  write_status "ERROR" "Live HUB returned only $RACE_COUNT race IDs." "$EXPECTED_SHA" "$LIVE_DIR"
  exit 23
}

write_status "OK" "Deployed exact GitHub commit into /sites/race-map-bog and verified live HTTP on port $PORT. Race IDs: $RACE_COUNT." "$EXPECTED_SHA" "$LIVE_DIR"
echo "DEPLOY_OK"
cat "$STATUS_ROOT"
