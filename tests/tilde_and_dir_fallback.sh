#!/usr/bin/env sh
# Validate tilde expansion for kit and pane dirs, and fallback when pane dir is invalid
set -eu

REPO_ROOT=$(CDPATH='' cd -- "$(dirname -- "$0")/.." && pwd -P)
BIN="$REPO_ROOT/bin"

if ! command -v tmux >/dev/null 2>&1; then
  echo "SKIP: tmux is required for tilde_and_dir_fallback test" >&2
  exit 0
fi

TMPDIR=$(mktemp -d)
export RELAY_STATE_DIR="$TMPDIR/state"
export RELAY_DATA_DIR="$TMPDIR/data"
export RELAY_KITS_DIR="$TMPDIR/kits"
export RELAY_PERSONAS_DIR="$TMPDIR/personas"
mkdir -p "$RELAY_STATE_DIR" "$RELAY_DATA_DIR" "$RELAY_KITS_DIR" "$RELAY_PERSONAS_DIR"

KIT_DIR="$RELAY_KITS_DIR/e2e"
mkdir -p "$KIT_DIR"

# Kit: base dir uses ~ (HOME); pane 2 uses ~ (should resolve to $HOME), pane 3 uses invalid path (should fallback to kit directory)
cat > "$KIT_DIR/kit.toml" <<EOF
version = 1
session = "e2e"
dir = "~"
attach = false

[[windows]]
name = "main"
dir = "~"
layout = "tiled"
panes = [
  { run = "sleep 5", dir = "~" },
  { run = "sleep 5", dir = "~/_relay_missing_$$" }
]
EOF

(tmux kill-session -t e2e >/dev/null 2>&1 || true)

"$BIN/relay" kit start e2e >/dev/null
sleep 1

resolve_session_name() {
  kit="$1"
  default="relay-$kit"
  if tmux has-session -t "$default" >/dev/null 2>&1; then
    printf '%s\n' "$default"
    return 0
  fi
  if tmux has-session -t "$kit" >/dev/null 2>&1; then
    printf '%s\n' "$kit"
    return 0
  fi
  printf '%s\n' "$default"
  return 1
}
SESSION_NAME=$(resolve_session_name e2e)
home_path=""
fallback_path=""
tries=0
paths_log="$TMPDIR/pane_paths.log"
while [ $tries -lt 20 ]; do
  paths=$(tmux list-panes -a -F '#{session_name} #{pane_id} #{pane_current_path}' 2>/dev/null || true)
  printf '%s\n' "$paths" > "$paths_log"
  home_path=""
  fallback_path=""
  while IFS=' ' read -r session _pane_id pane_path; do
    [ "$session" = "$SESSION_NAME" ] || continue
    case "$pane_path" in
      "$HOME"*)
        home_path="$pane_path"
        ;;
      "$KIT_DIR"*)
        fallback_path="$pane_path"
        ;;
    esac
  done <<EOF
$paths
EOF
  [ -n "$home_path" ] && [ -n "$fallback_path" ] && break
  tries=$((tries + 1))
  sleep 0.2
done

if [ -z "$home_path" ]; then
  echo "FAIL: home pane path not observed" >&2
  [ -f "$paths_log" ] && { echo "DEBUG pane paths:" >&2; cat "$paths_log" >&2; }
  tmux kill-session -t e2e >/dev/null 2>&1 || true
  exit 1
fi
if [ -z "$fallback_path" ]; then
  echo "FAIL: fallback pane path not observed" >&2
  [ -f "$paths_log" ] && { echo "DEBUG pane paths:" >&2; cat "$paths_log" >&2; }
  tmux kill-session -t e2e >/dev/null 2>&1 || true
  exit 1
fi

case "$home_path" in
  "$HOME"*) ;;
  *)
    echo "FAIL: home pane did not run in HOME (found: $home_path)" >&2
    tmux kill-session -t e2e >/dev/null 2>&1 || true
    exit 1
    ;;
esac

case "$fallback_path" in
  "$KIT_DIR"*) ;;
  *)
    echo "FAIL: fallback pane did not run in kit directory (found: $fallback_path)" >&2
    tmux kill-session -t e2e >/dev/null 2>&1 || true
    exit 1
    ;;
esac

(tmux kill-session -t e2e >/dev/null 2>&1 || true)

echo "OK: tilde expansion and dir fallback"
