#!/usr/bin/env bash
# SPDX-License-Identifier: MulanPSL-2.0
# Run this deployment inside the robonix-aubo image on the host next to the arm.
# ./build.sh, ./start.sh and ./stop.sh call this; use it directly for the rest.
#
#   scripts/container.sh build MODE     fetch packages, then rbnx build (MODE: sim|readonly|motion)
#   scripts/container.sh MODE           fetch, build and boot MODE in a detached container
#   scripts/container.sh exec CMD...    run CMD inside the running container
#   scripts/container.sh logs           follow the boot output
#   scripts/container.sh update         fast-forward every fetched package checkout
#   scripts/container.sh stop           rbnx shutdown, then remove the container
#
# Settings come from the environment or ./.env (see .env.example).
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
if [ -f "$ROOT/.env" ]; then
  set -a
  # shellcheck disable=SC1091
  source "$ROOT/.env"
  set +a
fi
SOURCE="${ROBONIX_SOURCE:?set ROBONIX_SOURCE in .env}"
IMAGE="${ROBONIX_AUBO_IMAGE:-robonix-aubo:20260922}"
CREDENTIALS="${AUBO_CREDENTIALS_FILE:-$HOME/.config/aubo/sdk-credentials.json}"
CACHE="$ROOT/rbnx-boot/cache"
GRIPPER_DEVICE="${GRIPPER_DEVICE:-/dev/ttyUSB0}"
NAME=aubo-i10h-b0
ATLAS=127.0.0.1:50151

manifest_for() {
  case "$1" in
    sim) echo robonix_manifest.sim.yaml ;;
    readonly) echo robonix_manifest.readonly.yaml ;;
    motion) echo robonix_manifest.yaml ;;
    *) echo "unknown mode '$1' (sim|readonly|motion)" >&2; return 1 ;;
  esac
}

# Clone the manifest's url packages with this host's git credentials, into the
# directory rbnx uses (rbnx-boot/cache/<repo>). rbnx then finds them present
# and does not clone inside the container, which has no GitHub credentials.
# The checkouts are ordinary clones: develop in them, commit and push.
fetch_packages() {
  local url branch dir
  mkdir -p "$CACHE"
  while read -r url branch; do
    dir="$CACHE/$(basename "${url%.git}")"
    [ -d "$dir/.git" ] && continue
    echo "fetching $url${branch:+ ($branch)}"
    git clone -q ${branch:+--branch "$branch"} "$url" "$dir"
  done < <(awk '$1 == "url:" { if (u) print u; u = $2 }
                $1 == "branch:" && u { print u, $2; u = "" }
                END { if (u) print u }' "$ROOT/$1")
}

DOCKER_ARGS=(--user "$(id -u):$(id -g)" -e HOME=/tmp/aubo-home
             -v "$ROOT:/workspace" -v "$SOURCE:/opt/robonix:ro")

build() {
  local manifest
  manifest="$(manifest_for "$1")"
  test -x "$SOURCE/target/release/rbnx" || { echo "no Robonix release build in $SOURCE" >&2; exit 1; }
  fetch_packages "$manifest"
  docker run --rm "${DOCKER_ARGS[@]}" "$IMAGE" rbnx build -f "$manifest"
}

boot() {
  local mode="$1" manifest motion=0
  manifest="$(manifest_for "$mode")"
  test -x "$SOURCE/target/release/rbnx" || { echo "no Robonix release build in $SOURCE" >&2; exit 1; }
  if docker ps -a --format '{{.Names}}' | grep -qx "$NAME"; then
    echo "container $NAME already exists; run: $0 stop" >&2; exit 1
  fi
  fetch_packages "$manifest"
  : "${AUBO_HOST:?set AUBO_HOST in .env}"
  local args=(-e ROBONIX_ATLAS="$ATLAS" -e RBNX_MANIFEST="$manifest" -e AUBO_HOST) prelude=""
  if [ "$mode" = sim ]; then
    # The sim manifest's gripper is tests/fake_rg.py on a pty.
    prelude="python3 /workspace/tests/fake_rg.py /tmp/fake-rg & sleep 0.5; "
  else
    test -f "$CREDENTIALS" || { echo "missing SDK credentials: $CREDENTIALS" >&2; exit 1; }
    test -c "$GRIPPER_DEVICE" || { echo "no gripper adapter at $GRIPPER_DEVICE" >&2; exit 1; }
    args+=(-v "$CREDENTIALS:/run/aubo-credentials.json:ro" -e AUBO_RPC_CREDENTIALS=/run/aubo-credentials.json
           --device "$GRIPPER_DEVICE:/dev/ttyUSB0" --group-add "$(stat -Lc %g "$GRIPPER_DEVICE")")
  fi
  [ "$mode" = motion ] && motion=1
  # Pilot's model: the caller's VLM_* settings, or else the deterministic fake
  # VLM from the Robonix testing harness with this repo's scripted scenarios.
  local vlm
  if [ "$mode" != readonly ] && [ -z "${VLM_BASE_URL:-}" ]; then
    prelude+="python3 /opt/robonix/testing/fake_vlm/server.py --port 18080 \
      --scenarios /workspace/tests/vlm_scenarios >/workspace/.runtime/fake_vlm.log 2>&1 & "
    args+=(-e VLM_BASE_URL=http://127.0.0.1:18080/v1 -e VLM_API_KEY=fake -e VLM_MODEL=fake-vlm)
    vlm="fake VLM (scripted: tests/vlm_scenarios)"
  else
    # Inherited by name, so the key never appears on the docker command line.
    args+=(-e VLM_BASE_URL -e VLM_API_KEY -e VLM_MODEL)
    vlm="${VLM_MODEL:-none}"
  fi
  mkdir -p "$ROOT/.runtime"
  docker run -d --init --name "$NAME" --network host "${DOCKER_ARGS[@]}" \
    -e AUBO_ENABLE_MOTION="$motion" "${args[@]}" \
    "$IMAGE" bash -c "rbnx build -f $manifest || exit 1; ${prelude}exec rbnx boot -f $manifest" >/dev/null
  echo "booting $manifest in container $NAME (motion=$motion, model: $vlm); follow with: $0 logs"
}

case "${1:-}" in
  sim|readonly|motion) boot "$1" ;;
  build) build "${2:?usage: $0 build sim|readonly|motion}" ;;
  exec)
    shift
    # A terminal makes Ctrl-C reach the command (fruit_pick_client.py cancels the run on it).
    tty=(-i); [ -t 0 ] && tty=(-it)
    exec docker exec "${tty[@]}" -e ROBONIX_ATLAS="$ATLAS" "$NAME" bash /workspace/scripts/container-entry.sh "$@"
    ;;
  logs) exec docker logs -f "$NAME" ;;
  update)
    for dir in "$CACHE"/*/; do
      [ -d "$dir/.git" ] && { echo "updating $(basename "$dir")"; git -C "$dir" pull --ff-only -q; }
    done
    ;;
  stop)
    if [ "$(docker inspect -f '{{.State.Running}}' "$NAME" 2>/dev/null)" = true ]; then
      manifest="$(docker exec "$NAME" printenv RBNX_MANIFEST)"
      # Shutdown deactivates every provider; the arm primitive stops owned
      # motion and must confirm it. Keep the container if it cannot.
      if ! docker exec "$NAME" bash /workspace/scripts/container-entry.sh rbnx shutdown -f "$manifest"; then
        echo "rbnx shutdown reported a problem; container kept for inspection." >&2
        echo "Check the arm, then remove it with: docker rm -f $NAME" >&2
        exit 1
      fi
    fi
    docker rm -f "$NAME" >/dev/null 2>&1 || true
    echo "stopped $NAME"
    ;;
  *) sed -n '3,13p' "$0"; exit 2 ;;
esac
