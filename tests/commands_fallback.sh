#!/usr/bin/env sh
# Validate commands fallback when no windows are defined
set -eu

REPO_ROOT=$(CDPATH='' cd -- "$(dirname -- "$0")/.." && pwd -P)
BIN="$REPO_ROOT/bin"

if ! command -v tmux >/dev/null 2>&1; then
  echo "SKIP: tmux is required for commands_fallback test" >&2
  exit 0
fi

TMPDIR=$(mktemp -d)
export RELAY_STATE_DIR="$TMPDIR/state"
export RELAY_DATA_DIR="$TMPDIR/data"
export RELAY_KITS_DIR="$TMPDIR/kits"
mkdir -p "$RELAY_STATE_DIR" "$RELAY_DATA_DIR" "$RELAY_KITS_DIR"

mkdir -p "$RELAY_KITS_DIR/e2e"
cat > "$RELAY_KITS_DIR/e2e/kit.toml" <<'EOF'
version = 1
session = "e2e"
dir = "~"
attach = false
commands = [
  "echo CMD_FALLBACK",
]
EOF

(tmux kill-session -t e2e >/dev/null 2>&1 || true)

"$BIN/relay" kit start e2e >/dev/null
sleep 0.5

pane=$(tmux display-message -p -t e2e '#{pane_id}')
out=$(tmux capture-pane -pt "$pane" -S -50 2>/dev/null || true)

echo "$out" | grep -q 'CMD_FALLBACK' || { echo "FAIL: commands fallback did not execute" >&2; exit 1; }

(tmux kill-session -t e2e >/dev/null 2>&1 || true)

echo "OK: commands fallback"