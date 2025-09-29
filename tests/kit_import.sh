#!/usr/bin/env sh
# Verify that relay kit import captures a tmux session into a kit.toml.
#
# How to run:
#   ./tests/kit_import.sh
#   RELAY_DEBUG=1 ./tests/kit_import.sh   # verbose tmux/python diagnostics
#
# Expectation:
#   The script creates a disposable tmux session, imports it, and emits
#   "OK: kit import captured tmux session" on success.
#
# If it fails:
#   - Socket errors ("error connecting ...") mean tmux cannot be launched.
#     Start a tmux server on the host or adjust tmux socket permissions.
#   - Test assertions print a "FAIL:" message. Inspect the generated kit under
#     "$RELAY_KITS_DIR" (shown in the log) and update lib/relay_tmux_import.py or
#     bin/relay-kit as needed. Re-run the test until it passes.
#   - When sharing results, include the exact command you ran, the failure
#     message, and the relevant portion of the generated kit.toml/import.log.
set -eu

REPO_ROOT=$(CDPATH='' cd -- "$(dirname -- "$0")/.." && pwd -P)
BIN="$REPO_ROOT/bin"

if ! command -v tmux >/dev/null 2>&1; then
  echo "SKIP: tmux is required for kit import test" >&2
  exit 0
fi

TMPDIR=$(mktemp -d)
trap 'rm -rf "$TMPDIR"' EXIT
export RELAY_KITS_DIR="$TMPDIR/kits"
export RELAY_PERSONAS_DIR="$TMPDIR/personas"
export RELAY_STATE_DIR="$TMPDIR/state"
export RELAY_DATA_DIR="$TMPDIR/data"
mkdir -p "$RELAY_KITS_DIR" "$RELAY_PERSONAS_DIR" "$RELAY_STATE_DIR" "$RELAY_DATA_DIR"

TMUX_SOCKET_NAME="relay-import-$$"
tmux_cmd() {
  TMUX="" tmux -L "$TMUX_SOCKET_NAME" -f /dev/null "$@"
}

session_name="relay-import-$$"
new_session_output=$(tmux_cmd new-session -ds "$session_name" -c "$REPO_ROOT" 2>&1) || {
  echo "SKIP: unable to start tmux session: $new_session_output" >&2
  exit 0
}
trap 'tmux_cmd kill-session -t "$session_name" >/dev/null 2>&1 || true; rm -rf "$TMPDIR"' EXIT

# ensure importer uses the same socket
export RELAY_TMUX_SOCKET_NAME="$TMUX_SOCKET_NAME"

# Keep the main pane busy
tmux_cmd send-keys -t "$session_name" "tail -f /dev/null" C-m

# Add a logging window with a placeholder command
tmux_cmd new-window -d -t "$session_name" -n logs -c "$REPO_ROOT" "sh -lc 'kubectl logs -f pod/api-123 || true; tail -f /dev/null'"

kit_name_raw="Monitor-Import"
expected_kit_name=$(printf '%s' "$kit_name_raw" | tr '[:upper:]' '[:lower:]' | tr -c 'a-z0-9-_' '-' | sed 's/-\{2,\}/-/g; s/_\{2,\}/_/g; s/^-//; s/-$//; s/^_//; s/_$//')

if ! "$BIN/relay-kit" import --output "$kit_name_raw" "$session_name" >/dev/null 2>&1; then
  echo "FAIL: relay kit import returned non-zero" >&2
  exit 1
fi

kit_dir="$RELAY_KITS_DIR/$expected_kit_name"
kit_file="$kit_dir/kit.toml"
if [ ! -f "$kit_file" ]; then
  echo "FAIL: kit.toml not created ($kit_file)" >&2
  exit 1
fi

if ! grep -q "session = \"$expected_kit_name\"" "$kit_file"; then
  echo "FAIL: kit.toml session mismatch" >&2
  exit 1
fi

if ! grep -q 'backend = "tmux"' "$kit_file"; then
  echo "FAIL: kit.toml missing backend" >&2
  exit 1
fi

if ! grep -q "Generated from tmux session '$session_name'" "$kit_file"; then
  echo "FAIL: kit.toml missing provenance comment" >&2
  exit 1
fi

if [ -f "$kit_dir/import.log" ]; then
  if ! grep -qi 'api-123' "$kit_dir/import.log"; then
    echo "FAIL: expected warning about pod/api-123" >&2
    exit 1
  fi
fi

tmux_cmd kill-session -t "$session_name" >/dev/null 2>&1 || true

echo "OK: kit import captured tmux session"
