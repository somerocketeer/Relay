#!/usr/bin/env sh
# Validate unicode kit and persona names function end-to-end
set -eu

REPO_ROOT=$(CDPATH='' cd -- "$(dirname -- "$0")/.." && pwd -P)
BIN="$REPO_ROOT/bin"

if ! command -v tmux >/dev/null 2>&1; then
  echo "SKIP: tmux is required for unicode_names test" >&2
  exit 0
fi

TMPDIR=$(mktemp -d)
export RELAY_KITS_DIR="$TMPDIR/kits"
export RELAY_PERSONAS_DIR="$TMPDIR/personas"
mkdir -p "$RELAY_PERSONAS_DIR/persó" "$RELAY_KITS_DIR/kit-ü"

# Persona
cat > "$RELAY_PERSONAS_DIR/persó/persona.toml" <<'EOF'
version = 1
[env]
UNICODE_OK = "1"
EOF

# Kit with unicode name, using the persona, write a trace
trace="$TMPDIR/unicode_trace.txt"
cat > "$RELAY_KITS_DIR/kit-ü/kit.toml" <<'EOF'
version = 1
session = "kit_u"
dir = "~"
attach = false
personas = ["persó"]

[[windows]]
name = "main"
dir = "~"
layout = "tiled"
panes = [
  "sh -lc 'test \"$UNICODE_OK\" = 1 && echo UNICODE_OK > \"__TRACE__\"'",
]
EOF

python3 - "$RELAY_KITS_DIR/kit-ü/kit.toml" "$trace" <<'PY'
import sys
path = sys.argv[1]
trace = sys.argv[2]
with open(path, 'r', encoding='utf-8') as handle:
    data = handle.read()
data = data.replace('__TRACE__', trace)
with open(path, 'w', encoding='utf-8') as handle:
    handle.write(data)
PY

(tmux kill-session -t kit_u >/dev/null 2>&1 || true)
(tmux kill-session -t relay-kit_u >/dev/null 2>&1 || true)
"$BIN/relay" kit start "kit-ü" >/dev/null

tries=0
while [ $tries -lt 10 ]; do
  if [ -f "$trace" ] && grep -q 'UNICODE_OK' "$trace" 2>/dev/null; then
    break
  fi
  tries=$((tries + 1))
  sleep 0.3
done

if ! [ -f "$trace" ] || ! grep -q 'UNICODE_OK' "$trace" 2>/dev/null; then
tmux capture-pane -pt kit_u -S -40 2>/dev/null || tmux capture-pane -pt relay-kit_u -S -40 2>/dev/null || true
  echo "FAIL: unicode kit/persona failed" >&2
  exit 1
fi

echo "OK: unicode kit and persona names"
