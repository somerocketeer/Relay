#!/usr/bin/env sh
# Validate that the first kit command targets the active pane regardless of tmux base-index
set -eu

REPO_ROOT=$(CDPATH='' cd -- "$(dirname -- "$0")/.." && pwd -P)
BIN="$REPO_ROOT/bin"

if ! command -v tmux >/dev/null 2>&1; then
  echo "SKIP: tmux is required for base_index test" >&2
  exit 0
fi

# Isolate Relay state/data and kit/persona roots
TMPDIR=$(mktemp -d)
export RELAY_STATE_DIR="$TMPDIR/state"
export RELAY_DATA_DIR="$TMPDIR/data"
export RELAY_KITS_DIR="$TMPDIR/kits"
export RELAY_PERSONAS_DIR="$TMPDIR/personas"
mkdir -p "$RELAY_STATE_DIR" "$RELAY_DATA_DIR" "$RELAY_KITS_DIR" "$RELAY_PERSONAS_DIR"

# Persona used by the kit
mkdir -p "$RELAY_PERSONAS_DIR/test"
cat > "$RELAY_PERSONAS_DIR/test/persona.toml" <<'EOF'
version = 1
[env]
RELAY_E2E = "1"
EOF

# Kit with attach=false and simple echo command
mkdir -p "$RELAY_KITS_DIR/e2e"
TRACE_FILE="$TMPDIR/first_trace.txt"

cat > "$RELAY_KITS_DIR/e2e/kit.toml" <<EOF
version = 1
session = "e2e"
dir = "~"
attach = false
personas = ["test"]

[[windows]]
name = "main"
dir = "~"
layout = "tiled"
panes = [
  "sh -lc 'printf FIRST_OK > \"$TRACE_FILE\"'",
]
EOF

# Ensure no prior session remains
(tmux kill-session -t e2e >/dev/null 2>&1 || true)

set +e
"$BIN/relay" kit start e2e >/dev/null 2>&1
status=$?
set -e
if [ "$status" -ne 0 ]; then
  echo "FAIL: relay kit start e2e returned non-zero ($status)" >&2
  exit 1
fi

# Wait for trace file to appear
for _ in $(seq 1 20); do
  [ -f "$TRACE_FILE" ] && break
  sleep 0.2
done

if ! [ -f "$TRACE_FILE" ] || ! grep -q 'FIRST_OK' "$TRACE_FILE" 2>/dev/null; then
  echo "FAIL: Did not find FIRST_OK trace" >&2
  tmux kill-session -t e2e >/dev/null 2>&1 || true
  exit 1
fi

tmux kill-session -t e2e >/dev/null 2>&1 || true

echo "OK: base_index first command targeted active pane"
