#!/usr/bin/env sh
# Verify kits and personas parse with CRLF line endings
set -eu

REPO_ROOT=$(CDPATH='' cd -- "$(dirname -- "$0")/.." && pwd -P)
BIN="$REPO_ROOT/bin"

if ! command -v tmux >/dev/null 2>&1; then
  echo "SKIP: tmux is required for crlf_configs test" >&2
  exit 0
fi

TMPDIR=$(mktemp -d)
export RELAY_KITS_DIR="$TMPDIR/kits"
export RELAY_PERSONAS_DIR="$TMPDIR/personas"
mkdir -p "$RELAY_KITS_DIR/e2e" "$RELAY_PERSONAS_DIR/crlf"

# Persona with CRLF
printf 'version = 1\r\n[env]\r\nCRLF = "yes"\r\n' > "$RELAY_PERSONAS_DIR/crlf/persona.toml"

# Kit with CRLF, attach=false, one pane that echoes a marker
trace="$TMPDIR/trace.txt"
lf_kit="$TMPDIR/kit_lf.toml"
cat > "$lf_kit" <<EOF
version = 1
session = "e2e"
dir = "~"
attach = false
personas = ["crlf"]

[[windows]]
name = "main"
dir = "~"
layout = "tiled"
panes = [
  "sh -lc 'echo CRLF_OK > \"$trace\"'",
]
EOF
# Convert LF to CRLF
awk '{ printf "%s\r\n", $0 }' "$lf_kit" > "$RELAY_KITS_DIR/e2e/kit.toml"

(tmux kill-session -t e2e >/dev/null 2>&1 || true)
"$BIN/relay" kit start e2e >/dev/null
sleep 1

[ -f "$trace" ] && grep -q 'CRLF_OK' "$trace" || { echo "FAIL: CRLF kit did not execute" >&2; exit 1; }

echo "OK: CRLF configs parse and execute"