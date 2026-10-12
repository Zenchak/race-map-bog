#!/usr/bin/env bash
set -Eeuo pipefail

REPO_URL="https://github.com/Zenchak/race-map-bog"
RUNNER_DIR="/volume1/docker/bogdan-sites/github-runner-race"
RUNNER_NAME="DS920plus-race"
LABELS="synology"

if [[ "$(uname -m)" != "x86_64" ]]; then
  echo "ERROR: this installer expects x86_64 (DS920+). Found: $(uname -m)" >&2
  exit 10
fi

TOKEN="${1:-}"
if [[ -z "$TOKEN" ]]; then
  printf "Paste the temporary GitHub runner registration token: " >/dev/tty
  IFS= read -r -s TOKEN </dev/tty
  printf "\n" >/dev/tty
fi
if [[ -z "$TOKEN" ]]; then
  echo "ERROR: no registration token supplied." >&2
  exit 11
fi

mkdir -p "$RUNNER_DIR"
cd "$RUNNER_DIR"

if [[ ! -x ./run.sh ]]; then
  echo "Downloading latest GitHub Actions runner..."
  RELEASE_JSON="$(curl -fsSL https://api.github.com/repos/actions/runner/releases/latest)"
  VERSION="$(printf '%s' "$RELEASE_JSON" | sed -n 's/.*"tag_name":[[:space:]]*"v\([^"]*\)".*/\1/p' | head -n1)"
  if [[ -z "$VERSION" ]]; then
    echo "ERROR: could not determine latest runner version." >&2
    exit 12
  fi
  ARCHIVE="actions-runner-linux-x64-${VERSION}.tar.gz"
  curl -fL "https://github.com/actions/runner/releases/download/v${VERSION}/${ARCHIVE}" -o "$ARCHIVE"
  tar xzf "$ARCHIVE"
  rm -f "$ARCHIVE"
fi

if [[ -f .runner ]]; then
  echo "Runner is already configured locally; keeping the existing registration."
else
  ./config.sh \
    --url "$REPO_URL" \
    --token "$TOKEN" \
    --name "$RUNNER_NAME" \
    --labels "$LABELS" \
    --work "_work" \
    --unattended \
    --replace
fi

cat > "$RUNNER_DIR/start-runner.sh" <<'EOF'
#!/usr/bin/env bash
set -e
cd /volume1/docker/bogdan-sites/github-runner-race
if pgrep -f '/volume1/docker/bogdan-sites/github-runner-race/bin/Runner.Listener' >/dev/null 2>&1; then
  exit 0
fi
nohup ./run.sh >> runner.log 2>&1 &
EOF
chmod +x "$RUNNER_DIR/start-runner.sh"

"$RUNNER_DIR/start-runner.sh"
sleep 3

if pgrep -f "$RUNNER_DIR/bin/Runner.Listener" >/dev/null 2>&1; then
  echo "RUNNER_OK: $RUNNER_NAME is running."
else
  echo "Runner was configured but is not running. Check: $RUNNER_DIR/runner.log" >&2
  exit 13
fi

echo
echo "For reboot persistence, create a Synology Task Scheduler task:"
echo "  Triggered Task -> User-defined script -> Boot-up"
echo "  User: a NAS account with write permission to /volume1/docker/bogdan-sites"
echo "  Command: $RUNNER_DIR/start-runner.sh"
