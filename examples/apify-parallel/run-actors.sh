#!/usr/bin/env bash
# Run one Apify/Crawlee actor per chrome workspace, in parallel.
#
#   ./run-actors.sh NAME [NAME...]
#
# Each NAME gets: its own workspace (created if missing), its own headless
# Chrome with resource limits, and its own actor process (actor/main.js)
# attached to that Chrome via CDP with isolated storage.
#
# Env knobs: MEM (default 1G), CPU (default 100%), ACTOR (default ./actor).
set -euo pipefail
cd "$(dirname "$0")"

(( $# >= 1 )) || { echo "usage: $0 NAME [NAME...]"; exit 1; }

CWS="${CWS:-cws}"
command -v "$CWS" >/dev/null 2>&1 || CWS="$(cd .. && pwd)/../bin/cws"
MEM="${MEM:-1G}"; CPU="${CPU:-100%}"; ACTOR="${ACTOR:-$PWD/actor}"

pids=()
cleanup() {
  echo "stopping actors and chromes..."
  kill "${pids[@]}" 2>/dev/null || true
  for n in "$@"; do "$CWS" stop "$n" 2>/dev/null || true; done
}
trap 'cleanup "$@"' EXIT INT TERM

for name in "$@"; do
  "$CWS" list --json | grep -q "\"name\":\"$name\"" || "$CWS" create "$name"
  "$CWS" launch "$name" --memory "$MEM" --cpu "$CPU"
done

# let the CDP endpoints come up
sleep 2

for name in "$@"; do
  echo "starting actor in workspace $name"
  "$CWS" apify "$name" -- node "$ACTOR/main.js" &
  pids+=($!)
done

wait "${pids[@]}"
