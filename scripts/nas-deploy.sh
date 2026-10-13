#!/usr/bin/env bash
set -Eeuo pipefail

ROOT="${NAS_SITES_ROOT:-/volume1/docker/bogdan-sites}"
EXPECTED_SHA="${1:-${GITHUB_SHA:-}}"
STATUS_ROOT="${ROOT}/deploy-status-race-map.json"
PORT="${RACE_HUB_PORT:-8082}"
SOURCE_DIR="${GITHUB_WORKSPACE:-$(pwd)}"
RUNNER_ROOT="${ROOT}/github-runner-race"

DEPLOY_DIR=""
TMPDIR_LOCAL=""

write_status() {
  local status="$1"
  local message="$2"
  local sha="${3:-}"
  local deploy_path="${4:-}"
  local now
  now="$(date -u +"%Y-%m-%dT%H:%M:%SZ")"

  jq -n     --arg service "race-map-bog"     --arg status "$status"     --arg deployed_sha "$sha"     --arg expected_sha "$EXPECTED_SHA"     --arg deployed_at "$now"     --arg deploy_path "$deploy_path"     --arg local_url "http://127.0.0.1:$PORT/"     --arg message "$message"     '{
      service:$service,
      status:$status,
      deployed_sha:$deployed_sha,
      expected_sha:$expected_sha,
      deployed_at:$deployed_at,
      deploy_path:$deploy_path,
      local_url:$local_url,
      message:$message
    }' > "$STATUS_ROOT"

  if [[ -n "$deploy_path" && -d "$deploy_path" ]]; then
    cp "$STATUS_ROOT" "$deploy_path/deploy-status.json" 2>/dev/null || true
  fi
}

cleanup() {
  [[ -n "$TMPDIR_LOCAL" && -d "$TMPDIR_LOCAL" ]] && rm -rf "$TMPDIR_LOCAL" || true
}
trap cleanup EXIT

on_error() {
  local code=$?
  local line="${BASH_LINENO[0]:-unknown}"
  write_status "ERROR" "Deploy failed at line $line (exit $code)." "$EXPECTED_SHA" "$DEPLOY_DIR" || true
  exit "$code"
}
trap on_error ERR

echo "SOURCE_DIR=$SOURCE_DIR"
echo "ROOT=$ROOT"
echo "Checking current HUB served on port $PORT ..."

TMPDIR_LOCAL="$(mktemp -d)"
curl --fail --silent --show-error --max-time 10 "http://127.0.0.1:$PORT/" -o "$TMPDIR_LOCAL/current-index.html"
curl --fail --silent --show-error --max-time 10 "http://127.0.0.1:$PORT/app.html" -o "$TMPDIR_LOCAL/current-app.html"

CURRENT_APP_SHA="$(sha256sum "$TMPDIR_LOCAL/current-app.html" | awk '{print $1}')"
echo "Current served app SHA256: $CURRENT_APP_SHA"

echo "Finding the exact app.html currently served by the NAS ..."
while IFS= read -r -d '' candidate; do
  case "$candidate" in
    "$RUNNER_ROOT"/*) continue ;;
  esac

  candidate_sha="$(sha256sum "$candidate" 2>/dev/null | awk '{print $1}' || true)"
  if [[ "$candidate_sha" == "$CURRENT_APP_SHA" ]]; then
    DEPLOY_DIR="$(dirname "$candidate")"
    break
  fi
done < <(find "$ROOT" -maxdepth 8 -type f -name app.html -print0 2>/dev/null)

# Fallback: locate a likely race-HUB directory even if the served file was transformed/cached.
if [[ -z "$DEPLOY_DIR" ]]; then
  echo "Exact hash match not found; checking likely HUB candidates ..."
  while IFS= read -r -d '' candidate; do
    case "$candidate" in
      "$RUNNER_ROOT"/*) continue ;;
    esac
    dir="$(dirname "$candidate")"
    if [[ -f "$dir/index.html" ]] && grep -q "Calendario Gare" "$candidate" 2>/dev/null; then
      DEPLOY_DIR="$dir"
      echo "Fallback candidate: $DEPLOY_DIR"
      break
    fi
  done < <(find "$ROOT" -maxdepth 8 -type f -name app.html -print0 2>/dev/null)
fi

if [[ -z "$DEPLOY_DIR" ]]; then
  echo "ERROR: could not identify the NAS directory serving app.html on port $PORT." >&2
  echo "app.html candidates under $ROOT:" >&2
  find "$ROOT" -maxdepth 8 -type f -name app.html -not -path "$RUNNER_ROOT/*" -print 2>/dev/null >&2 || true
  write_status "ERROR" "Could not identify the NAS directory serving the race HUB." "$EXPECTED_SHA" ""
  exit 20
fi

echo "DEPLOY_DIR=$DEPLOY_DIR"

for required in index.html app.html extra-races.js; do
  if [[ ! -s "$SOURCE_DIR/$required" ]]; then
    write_status "ERROR" "Source checkout is missing required file: $required" "$EXPECTED_SHA" "$DEPLOY_DIR"
    exit 21
  fi
done

# Keep one rollback copy before replacing the live static files.
BACKUP_DIR="$DEPLOY_DIR/.deploy-backup"
mkdir -p "$BACKUP_DIR"
for file in index.html app.html extra-races.js feasibility.js; do
  if [[ -f "$DEPLOY_DIR/$file" ]]; then
    cp "$DEPLOY_DIR/$file" "$BACKUP_DIR/$file.previous" || true
  fi
done

echo "Copying current GitHub checkout into live HUB directory ..."
install -m 0644 "$SOURCE_DIR/index.html" "$DEPLOY_DIR/index.html"
install -m 0644 "$SOURCE_DIR/app.html" "$DEPLOY_DIR/app.html"
install -m 0644 "$SOURCE_DIR/extra-races.js" "$DEPLOY_DIR/extra-races.js"
if [[ -f "$SOURCE_DIR/feasibility.js" ]]; then
  install -m 0644 "$SOURCE_DIR/feasibility.js" "$DEPLOY_DIR/feasibility.js"
fi

# Verify the live files on disk first.
grep -q "HUB_BUILD='2026.10.12-2350'" "$DEPLOY_DIR/app.html"
grep -q "applyStructuredRaceFilters" "$DEPLOY_DIR/app.html"
grep -q "window.EXTRA_RACES" "$DEPLOY_DIR/extra-races.js"

# Then verify the files actually served by the NAS.
sleep 2
curl --fail --silent --show-error --max-time 10 "http://127.0.0.1:$PORT/" -o "$TMPDIR_LOCAL/served-index.html"
curl --fail --silent --show-error --max-time 10 "http://127.0.0.1:$PORT/app.html?deploy=$EXPECTED_SHA" -o "$TMPDIR_LOCAL/served-app.html"
curl --fail --silent --show-error --max-time 10 "http://127.0.0.1:$PORT/extra-races.js?deploy=$EXPECTED_SHA" -o "$TMPDIR_LOCAL/served-extra.js"

grep -q "Calendario Gare" "$TMPDIR_LOCAL/served-index.html"
grep -q "HUB_BUILD='2026.10.12-2350'" "$TMPDIR_LOCAL/served-app.html"
grep -q "applyStructuredRaceFilters" "$TMPDIR_LOCAL/served-app.html"
grep -q "window.EXTRA_RACES" "$TMPDIR_LOCAL/served-extra.js"

# Confirm the expected dataset volume is really present in the live response.
RACE_COUNT="$(grep -o 'id:' "$TMPDIR_LOCAL/served-extra.js" | wc -l | tr -d ' ')"
if [[ "$RACE_COUNT" -lt 50 ]]; then
  write_status "ERROR" "HUB served extra-races.js, but only $RACE_COUNT race IDs were detected." "$EXPECTED_SHA" "$DEPLOY_DIR"
  exit 22
fi

write_status "OK" "Deployed GitHub commit to the exact NAS HUB directory and verified files served on port $PORT. Race IDs detected: $RACE_COUNT." "$EXPECTED_SHA" "$DEPLOY_DIR"

echo "DEPLOY_OK"
cat "$STATUS_ROOT"
