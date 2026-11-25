#!/usr/bin/env bash
# One-shot guarded recovery test. Does not stop the API unless preflight succeeds.
set -Eeuo pipefail
SOCK=/var/run/docker.sock
API=bogdan-sites-house-api
WD=bogdan-sites-api-watchdog
HEALTH=http://127.0.0.1:8090/healthz

say(){ echo "[HUB_RECOVERY_TEST] $*"; }
dget(){ curl --fail --silent --show-error --connect-timeout 4 --max-time 10 --unix-socket "$SOCK" "http://localhost$1"; }
dpost(){ curl --silent --show-error --connect-timeout 4 --max-time 18 -o /dev/null -w '%{http_code}' --unix-socket "$SOCK" -X POST "http://localhost$1"; }
healthy(){ [[ "$(curl --silent --connect-timeout 2 --max-time 5 -o /dev/null -w '%{http_code}' "$HEALTH" || true)" == 200 ]]; }
running(){ [[ "$(dget "/containers/$1/json" | jq -r '.State.Running')" == true ]]; }
EXIT_RESTORE=0
restore(){
  if [[ "$EXIT_RESTORE" == 1 ]]; then
    if ! running "$API" || ! healthy; then
      say "SAFEGUARD: attempted manual API start after failed recovery test."
      dpost "/containers/$API/start" || true
    fi
  fi
}
trap restore EXIT

say "Preflight: no service will be stopped until NAS/Docker/updater/web/API are stable."
test -S "$SOCK"
command -v jq >/dev/null
uptime_secs="$(cut -d. -f1 /proc/uptime)"
if (( uptime_secs < 900 )); then say "STOP: NAS uptime below 15 minutes (update/reboot may still be settling)."; exit 1; fi
say "NAS uptime: $uptime_secs seconds"
for c in bogdan-sites-updater bogdan-sites-web "$API"; do
  if ! running "$c"; then say "STOP: required container $c not running."; exit 1; fi
  say "Container $c: running"
done
if ! healthy; then say "STOP: main Hub health check is not HTTP 200."; exit 1; fi
sleep 8
if ! healthy; then say "STOP: health check unstable during preflight."; exit 1; fi
say "Hub healthy (HTTP 200) before recovery test."

# Wait for NAS GitHub updater to deliver the watchdog JS file.
for i in $(seq 1 28); do
  [[ -s /sites/training-dashboard-bog/nas/hub-api-watchdog.js ]] && break
  sleep 5
done
if [[ ! -s /sites/training-dashboard-bog/nas/hub-api-watchdog.js ]]; then
  say "STOP: watchdog JS not present on shared /sites mount."; exit 1
fi
say "Watchdog JS present on the live NAS volume."

# Install a *local*, always-on watchdog. Independent of GitHub scheduled runs.
if dget "/containers/$WD/json" >/dev/null 2>&1; then
  say "Watchdog container already exists; inspect before starting."
else
  volume="$(dget "/containers/bogdan-sites-updater/json" | jq -r '.Mounts[] | select(.Destination=="/sites") | .Name // empty' | head -1)"
  network="$(dget "/containers/bogdan-sites-web/json" | jq -r '.NetworkSettings.Networks | keys[0] // empty')"
  if [[ -z "$volume" || -z "$network" ]]; then say "STOP: cannot identify shared sites volume/network."; exit 1; fi
  say "Installing local watchdog on existing Docker network (no ports exposed)."
  payload="$(jq -n --arg volume "$volume" --arg network "$network" '{
    Image:"node:22-alpine",
    Cmd:["node","/sites/training-dashboard-bog/nas/hub-api-watchdog.js"],
    HostConfig:{
      Binds:[($volume+":/sites:ro"),"/var/run/docker.sock:/var/run/docker.sock"],
      NetworkMode:$network,
      RestartPolicy:{Name:"unless-stopped"}
    },
    Labels:{"zenchak.component":"hub-api-self-healing","zenchak.source":"github"}
  }')"
  status="$(curl --silent --show-error --connect-timeout 5 --max-time 20 --unix-socket "$SOCK" \
    -H 'Content-Type: application/json' -d "$payload" \
    -o /tmp/hub-watchdog-create-result -w '%{http_code}' \
    "http://localhost/containers/create?name=$WD")"
  if [[ "$status" != 201 ]]; then
    say "STOP: Docker watchdog create HTTP $status"; cat /tmp/hub-watchdog-create-result; exit 1
  fi
fi
if ! running "$WD"; then
  result="$(dpost "/containers/$WD/start")"
  [[ "$result" == 204 || "$result" == 304 ]] || { say "STOP: watchdog start HTTP $result"; exit 1; }
fi
sleep 9
if ! running "$WD" || ! healthy; then say "STOP: watchdog or Hub not stable after setup."; exit 1; fi
say "Local watchdog is running; Hub remains healthy."

# Prove watchdog, rather than docker restart policy, recovers an intentional stop.
say "TEST START: stopping $API once. Expected automatic recovery in under ~90 seconds."
EXIT_RESTORE=1
st="$(dpost "/containers/$API/stop?t=5")"
if [[ "$st" != 204 && "$st" != 304 ]]; then
  say "STOP action returned HTTP $st; abort."; exit 1
fi
say "Intentional stop accepted: HTTP $st."
recovered=0
for i in $(seq 1 22); do
  sleep 5
  if running "$API" && healthy; then
    recovered=1
    say "Hub API recovered and /healthz returned HTTP 200 after ~$(($i*5)) seconds."
    break
  fi
done
if [[ "$recovered" != 1 ]]; then
  say "FAIL: watchdog did not restore the Hub API within 110 seconds."
  exit 1
fi
logs="$(dget "/containers/$WD/logs?stdout=true&stderr=true&tail=60" | tr -d '\000')"
if ! grep -q 'risulta spento: avvio automatico' <<< "$logs"; then
  say "WARNING: API recovered, but watchdog start event was not found in logs."
  echo "$logs" | tail -12
  exit 1
fi
if ! grep -q 'Docker start eseguito' <<< "$logs"; then
  say "WARNING: watchdog detected stop, but no successful Docker start log found."
  echo "$logs" | tail -12
  exit 1
fi
EXIT_RESTORE=0
say "PASS: intentional stop -> detected by local watchdog -> automatic Docker start -> HTTP 200."
say "Local watchdog survives GitHub runner outages (Docker restart unless-stopped)."
