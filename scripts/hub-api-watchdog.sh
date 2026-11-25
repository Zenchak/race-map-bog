#!/usr/bin/env bash
# NAS Hub API self-healing. Runs on the existing Synology GitHub Actions runner.
# Uses the local Docker socket; never restarts the Nginx/web or race deploy containers.
set -Eeuo pipefail

SOCKET=/var/run/docker.sock
CONTAINER=bogdan-sites-house-api
HEALTH_URL=http://127.0.0.1:8090/healthz
STATE_DIR=/volume1/docker/bogdan-sites
STATUS_FILE="$STATE_DIR/hub-api-watchdog-status.json"
LAST_RECOVERY_FILE="$STATE_DIR/hub-api-watchdog-last-recovery"
COOLDOWN_SECONDS=900
mkdir -p "$STATE_DIR"

status() {
  local state="$1" details="$2"
  echo "HUB_API_WATCHDOG: $state - $details"
  jq -n --arg state "$state" --arg details "$details" \
    --arg checked_at "$(date -u +%Y-%m-%dT%H:%M:%SZ)" \
    '{state:$state,details:$details,checked_at:$checked_at}' > "$STATUS_FILE" || true
}

docker_inspect() {
  curl --fail --silent --show-error --connect-timeout 4 --max-time 10 \
    --unix-socket "$SOCKET" "http://localhost/containers/$CONTAINER/json"
}

is_running() {
  local inspect
  inspect="$(docker_inspect)" || return 1
  [[ "$(jq -r '.State.Running // false' <<< "$inspect")" == true ]]
}

health_status() {
  curl --silent --output /dev/null --connect-timeout 3 --max-time 7 \
    --write-out '%{http_code}' "$HEALTH_URL" 2>/dev/null || true
}

healthy() {
  local code
  code="$(health_status)"
  echo "HUB_API_WATCHDOG: GET $HEALTH_URL -> HTTP $code"
  [[ "$code" == 200 || "$code" == 204 ]]
}

recover() {
  local operation="$1" code
  code="$(curl --silent --show-error --connect-timeout 5 --max-time 55 \
    --unix-socket "$SOCKET" -X POST \
    --output /dev/null --write-out '%{http_code}' \
    "http://localhost/containers/$CONTAINER/$operation" 2>/dev/null)" || {
      status ERROR "Docker $operation did not respond; inspect Container Manager on the NAS."
      return 1
    }
  [[ "$code" == 204 || ("$operation" == start && "$code" == 304) ]] || {
    status ERROR "Docker $operation returned HTTP $code."
    return 1
  }
  date +%s > "$LAST_RECOVERY_FILE" || true
  for delay in 5 10 10 10 10; do
    sleep "$delay"
    if is_running && healthy; then
      status RECOVERED "Container $operation succeeded; API healthy."
      return 0
    fi
  done
  status ERROR "Container $operation requested, but the API is still not healthy."
  return 1
}

[[ -S "$SOCKET" ]] || { status ERROR "Docker socket unavailable on the Synology runner."; exit 1; }
command -v jq >/dev/null || { status ERROR "jq unavailable on runner."; exit 1; }

if ! is_running; then
  echo "HUB_API_WATCHDOG: API container stopped; starting it without affecting other services."
  recover start
  exit $?
fi

if healthy; then
  status HEALTHY "House API running and Hub health check responds."
  exit 0
fi

# Do not restart the service for a momentary Nginx reload or network hiccup.
for attempt in 2 3; do
  sleep 6
  if healthy; then
    status HEALTHY "Temporary health-check failure cleared (attempt $attempt)."
    exit 0
  fi
done

last=0
[[ -f "$LAST_RECOVERY_FILE" ]] && read -r last < "$LAST_RECOVERY_FILE" || true
[[ "$last" =~ ^[0-9]+$ ]] || last=0
now="$(date +%s)"
if (( now - last < COOLDOWN_SECONDS )); then
  status ERROR "Health check failed 3 times; recovery cooldown active to avoid restart loops."
  exit 1
fi

echo "HUB_API_WATCHDOG: API running but unresponsive for 3 checks; restarting only $CONTAINER."
recover 'restart?t=10'
