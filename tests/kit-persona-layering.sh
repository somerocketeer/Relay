#!/usr/bin/env sh
# Verify pane-level persona layering and clearing commands.
set -eu

REPO_ROOT=$(CDPATH='' cd -- "$(dirname -- "$0")/.." && pwd -P)
PATH="$REPO_ROOT/bin:$PATH"

TMP_ROOT=$(mktemp -d)
trap 'rm -rf "$TMP_ROOT"' EXIT

KITS_DIR="$TMP_ROOT/kits"
PERSONAS_DIR="$TMP_ROOT/personas"
STUB_BIN="$TMP_ROOT/bin"
LOG_ONE="$TMP_ROOT/log-assign.txt"
LOG_TWO="$TMP_ROOT/log-clear.txt"
mkdir -p "$KITS_DIR/demo" "$PERSONAS_DIR/overlay" "$STUB_BIN"

cat > "$PERSONAS_DIR/overlay/persona.toml" <<'PERSONA'
version = 1
[env]
OVERLAY_FLAG = "persona-overlay"
PERSONA

cat > "$KITS_DIR/demo/kit.toml" <<'KIT'
version = 1
session = "demo"
dir = "~/"
attach = false

[[windows]]
name = "main"
panes = [
  "echo pane-one",
  "echo pane-two",
]
KIT

cat > "$STUB_BIN/tmux" <<'TMUXSTUB'
#!/usr/bin/env sh
log_file="${TMUX_TEST_LOG:-}"
cmd=${1:-}
if [ -n "$log_file" ]; then
  shift
  {
    printf '%s' "$cmd"
    for arg in "$@"; do
      printf ' %s' "$arg"
    done
    printf '\n'
  } >> "$log_file"
fi
case "$cmd" in
  has-session)
    exit 1
    ;;
  new-window)
    while [ $# -gt 0 ]; do
      case "$1" in
        -P)
          shift
          ;;
        -F)
          shift
          if [ $# -gt 0 ] && [ "$1" = '#{pane_id}' ]; then
            printf '%%pane_stub\n'
          fi
          shift
          ;;
        --)
          shift
          break
          ;;
        *)
          shift
          ;;
      esac
    done
    exit 0
    ;;
  send-keys|new-session|switch-client|kill-session|set-environment|attach|display-message|list-panes)
    exit 0
    ;;
  *)
    exit 0
    ;;
esac
TMUXSTUB
chmod +x "$STUB_BIN/tmux"

export PATH="$STUB_BIN:$PATH"
export RELAY_KITS_DIR="$KITS_DIR"
export RELAY_PERSONAS_DIR="$PERSONAS_DIR"

unset TMUX || true

# Assign overlay to the first pane.
"$REPO_ROOT/bin/relay-kit" persona assign demo main:1 overlay >/dev/null

[ -f "$KITS_DIR/demo/pane-personas.json" ] || {
  echo "pane-personas.json was not created" >&2
  exit 1
}

python3 - "$KITS_DIR/demo/pane-personas.json" <<'CHECKJSON'
import json
import sys
path = sys.argv[1]
with open(path, 'r', encoding='utf-8') as handle:
    data = json.load(handle)
panes = data.get('panes') or {}
if panes.get('0:0') != ['overlay']:
    raise SystemExit('Expected overlay persona assigned to pane 0:0')
CHECKJSON

TMUX_TEST_LOG="$LOG_ONE" "$REPO_ROOT/bin/relay-kit" start demo >/dev/null

python3 - "$LOG_ONE" <<'LOGCHECK'
import pathlib
import sys

log_path = pathlib.Path(sys.argv[1])
content = log_path.read_text(encoding='utf-8')
if 'relay/bin/relay-persona' not in content:
    raise SystemExit('relay-persona helper missing for pane overlay')
if "'exec' 'overlay' --" not in content:
    raise SystemExit('overlay command not layered on pane')
for line in content.splitlines():
    if 'pane-two' in line and "'overlay'" in line:
        raise SystemExit('Overlay should not apply to second pane')
LOGCHECK

# Clear overlay and ensure wrapper no longer appears.
"$REPO_ROOT/bin/relay-kit" persona clear demo main:1 >/dev/null

TMUX_TEST_LOG="$LOG_TWO" "$REPO_ROOT/bin/relay-kit" start demo >/dev/null
if grep -Fq 'relay-persona' "$LOG_TWO"; then
  echo "Persona wrapper should be absent after clear" >&2
  exit 1
fi

python3 - "$KITS_DIR/demo/pane-personas.json" <<'CHECKCLEAR'
import json
import sys
path = sys.argv[1]
with open(path, 'r', encoding='utf-8') as handle:
    data = json.load(handle)
panes = data.get('panes') or {}
if '0:0' in panes:
    raise SystemExit('Pane overlay entry should be cleared')
CHECKCLEAR
