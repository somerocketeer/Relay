#!/usr/bin/env sh
# Stress the events bus with concurrent writers and verify line count
set -eu

REPO_ROOT=$(CDPATH='' cd -- "$(dirname -- "$0")/.." && pwd -P)
BIN="$REPO_ROOT/bin"

TMPDIR=$(mktemp -d)
export RELAY_STATE_DIR="$TMPDIR/state"
mkdir -p "$RELAY_STATE_DIR"

# Initialize and clear
"$BIN/relay" events init > /dev/null
"$BIN/relay" events clear

# Burst emit
N=50
pids=
for i in $(seq 1 $N); do
  "$BIN/relay" events emit stress "n=$i" &
  pids="$pids $!"
done
wait $pids

# Validate last N lines correspond to our emits (type 'stress')
count=$("$BIN/relay" events show | tail -n "$N" | grep -c '^stress|')
[ "$count" -eq "$N" ] || { echo "FAIL: expected $N stress events, got $count" >&2; exit 1; }

echo "OK: events concurrency"