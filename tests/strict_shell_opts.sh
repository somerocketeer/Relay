#!/usr/bin/env sh
# Ensure strict shell options in pane do not break command execution
set -eu

REPO_ROOT=$(CDPATH='' cd -- "$(dirname -- "$0")/.." && pwd -P)
BIN="$REPO_ROOT/bin"

if ! command -v tmux >/dev/null 2>&1; then
  echo "SKIP: tmux is required for strict_shell_opts test" >&2
  exit 0
fi

TMPDIR=$(mktemp -d)
export RELAY_KITS_DIR="$TMPDIR/kits"
mkdir -p "$RELAY_KITS_DIR/strict"

trace="$TMPDIR/strict_ok.txt"
cat > "$RELAY_KITS_DIR/strict/kit.toml" <<EOF
version = 1
session = "strict"
dir = "~"
attach = false

[[windows]]
name = "main"
dir = "~"
layout = "tiled"
panes = [
  "sh -lc 'set -euo pipefail; IFS=\"\n\t\"; echo OK_STRICT > \"$trace\"'",
]
EOF

(tmux kill-session -t strict >/dev/null 2>&1 || true)
"$BIN/relay" kit start strict >/dev/null
sleep 1

[ -f "$trace" ] && grep -q 'OK_STRICT' "$trace" || { echo "FAIL: strict shell options broke pane command" >&2; exit 1; }

echo "OK: strict shell options in pane"