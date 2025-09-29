#!/usr/bin/env sh
# Validate events log init/emit/show/clear
set -eu

REPO_ROOT=$(CDPATH='' cd -- "$(dirname -- "$0")/.." && pwd -P)
BIN="$REPO_ROOT/bin"

TMPDIR=$(mktemp -d)
export RELAY_STATE_DIR="$TMPDIR/state"
mkdir -p "$RELAY_STATE_DIR"

# init creates the log and prints the path
LOG_PATH=$("$BIN/relay" events init)
[ -n "$LOG_PATH" ] && [ -f "$LOG_PATH" ] || { echo "FAIL: events init did not create log" >&2; exit 1; }

# clear empties it
"$BIN/relay" events clear
[ ! -s "$LOG_PATH" ] || { echo "FAIL: events clear did not truncate log" >&2; exit 1; }

# emit an event and check the line format
"$BIN/relay" events emit e2e "status=ok"
last_line=$("$BIN/relay" events show | tail -n 1)
# Expect: type|timestamp|message
printf '%s\n' "$last_line" | grep -E -q '^e2e\|[0-9]+\|status=ok$' || {
  echo "FAIL: unexpected events line: $last_line" >&2
  exit 1
}

echo "OK: events init/emit/show/clear"