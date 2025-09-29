#!/usr/bin/env bash
# test_relay_integration.sh - Integration and regression tests for relay

set -euo pipefail

SCRIPT_DIR=$(CDPATH='' cd -- "$(dirname -- "$0")" && pwd -P)
REPO_ROOT=$(CDPATH='' cd -- "$SCRIPT_DIR/.." && pwd -P)

if ! command -v tmux >/dev/null 2>&1; then
  echo "SKIP: tmux is required for integration tests" >&2
  exit 0
fi

PATH="$REPO_ROOT/bin:$PATH"
export PATH

TEST_HOME=$(mktemp -d)
export HOME="$TEST_HOME"
export XDG_STATE_HOME="$TEST_HOME/.local/state"
export XDG_DATA_HOME="$TEST_HOME/.local/share"

sessions_to_cleanup=()

resolve_session_name() {
  local kit="$1"
  local default="relay-$kit"
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

cleanup() {
  set +e
  for session in "${sessions_to_cleanup[@]}"; do
    tmux kill-session -t "$session" >/dev/null 2>&1 || true
  done
  rm -rf "$TEST_HOME"
}
trap cleanup EXIT INT TERM

require_file_contains() {
  local file=$1
  local needle=$2
  if ! [ -f "$file" ]; then
    echo "FAIL: expected file missing: $file" >&2
    exit 1
  fi
  if ! grep -q "$needle" "$file" 2>/dev/null; then
    echo "FAIL: expected '$needle' in $file" >&2
    exit 1
  fi
}

test_kit_persona_integration() {
  echo "[TEST] Kit + persona lifecycle"

  tmux kill-session -t relay-integration >/dev/null 2>&1 || true
  tmux kill-session -t integration >/dev/null 2>&1 || true

  local persona_alpha_dir="$HOME/.local/share/relay/personas/alpha"
  local persona_beta_dir="$HOME/.local/share/relay/personas/beta"
  mkdir -p "$persona_alpha_dir" "$persona_beta_dir"
  cat > "$persona_alpha_dir/persona.toml" <<'EOF'
version = 1
[env]
KIT_ALPHA = "1"
EOF
  cat > "$persona_beta_dir/persona.toml" <<'EOF'
version = 1
[env]
KIT_BETA = "1"
EOF

  local kit_dir="$HOME/.local/share/relay/kits/integration"
  mkdir -p "$kit_dir"
  local trace_alpha="$TEST_HOME/trace_alpha.out"
  local trace_beta="$TEST_HOME/trace_beta.out"
  cat > "$kit_dir/kit.toml" <<EOF
version = 1
session = "relay-integration"
dir = "~"
attach = false
personas = ["alpha"]

[[windows]]
name = "dev"
dir = "~"
layout = "tiled"
panes = [
  "sh -lc 'printf \"%s\" \"\$KIT_ALPHA\" > \"$trace_alpha\" ; tail -f /dev/null'",
  "sh -lc 'printf \"%s %s\" \"\$KIT_ALPHA\" \"\$KIT_BETA\" > \"$trace_beta\" ; tail -f /dev/null'",
]
EOF

  relay kit start integration >/dev/null

  local session_name
  session_name=$(resolve_session_name integration)
  sessions_to_cleanup+=("$session_name")

  for _ in $(seq 1 20); do
    [ -f "$trace_alpha" ] && [ -f "$trace_beta" ] && break
    sleep 0.2
  done
  require_file_contains "$trace_alpha" "1"

  if grep -q "1 1" "$trace_beta" 2>/dev/null; then
    echo "FAIL: beta persona unexpectedly present before overlay" >&2
    exit 1
  fi

  relay kit stop integration >/dev/null

  relay kit persona assign integration dev:2 beta >/dev/null
  rm -f "$trace_alpha" "$trace_beta"

  relay kit start integration >/dev/null
  session_name=$(resolve_session_name integration)
  for _ in $(seq 1 20); do
    [ -f "$trace_alpha" ] && [ -f "$trace_beta" ] && break
    sleep 0.2
  done
  require_file_contains "$trace_alpha" "1"
  require_file_contains "$trace_beta" "1 1"

  relay kit stop integration >/dev/null
}

test_events_pipeline() {
  echo "[TEST] Events pipeline"
  local log_path
  log_path=$(relay events init)
  relay events clear >/dev/null
  local capture="$TEST_HOME/events_tail.log"
  tail -n 0 -F "$log_path" > "$capture" &
  local tail_pid=$!
  sleep 0.1
  for i in $(seq 1 40); do
    relay events emit "test" "event-$i" >/dev/null
  done
  sleep 0.2
  kill "$tail_pid" >/dev/null 2>&1 || true
  wait "$tail_pid" 2>/dev/null || true
  local total
  total=$(wc -l < "$log_path")
  if [ "$total" -ne 40 ]; then
    echo "FAIL: expected 40 events, found $total" >&2
    exit 1
  fi
  require_file_contains "$capture" "event-40"
  relay events clear >/dev/null
  if [ -s "$log_path" ]; then
    echo "FAIL: log not cleared" >&2
    exit 1
  fi
}

test_concurrent_kits() {
  echo "[TEST] Concurrent kits"
  local kit_a_dir="$HOME/.local/share/relay/kits/integration-a"
  local kit_b_dir="$HOME/.local/share/relay/kits/integration-b"

  tmux kill-session -t relay-integration-a >/dev/null 2>&1 || true
  tmux kill-session -t integration-a >/dev/null 2>&1 || true
  tmux kill-session -t relay-integration-b >/dev/null 2>&1 || true
  tmux kill-session -t integration-b >/dev/null 2>&1 || true
  mkdir -p "$kit_a_dir" "$kit_b_dir"
  local trace_a="$TEST_HOME/concurrent_a.out"
  local trace_b="$TEST_HOME/concurrent_b.out"
  cat > "$kit_a_dir/kit.toml" <<EOF
version = 1
session = "relay-integration-a"
dir = "~"
attach = false

[[windows]]
name = "main"
dir = "~"
layout = "tiled"
panes = [
  "sh -lc 'echo A > \"$trace_a\" ; tail -f /dev/null'",
]
EOF
  cat > "$kit_b_dir/kit.toml" <<EOF
version = 1
session = "relay-integration-b"
dir = "~"
attach = false

[[windows]]
name = "main"
dir = "~"
layout = "tiled"
panes = [
  "sh -lc 'echo B > \"$trace_b\" ; tail -f /dev/null'",
]
EOF

  relay kit start integration-a >/dev/null &
  local pid_a=$!
  relay kit start integration-b >/dev/null &
  local pid_b=$!
  wait "$pid_a"
  wait "$pid_b"

  local session_a session_b
  session_a=$(resolve_session_name integration-a)
  session_b=$(resolve_session_name integration-b)
  sessions_to_cleanup+=("$session_a" "$session_b")

  for _ in $(seq 1 20); do
    [ -f "$trace_a" ] && [ -f "$trace_b" ] && break
    sleep 0.2
  done
  require_file_contains "$trace_a" "A"
  require_file_contains "$trace_b" "B"
  if ! tmux has-session -t "$session_a" >/dev/null 2>&1; then
    echo "FAIL: session for integration-a missing" >&2
    exit 1
  fi
  if ! tmux has-session -t "$session_b" >/dev/null 2>&1; then
    echo "FAIL: session for integration-b missing" >&2
    exit 1
  fi

  relay kit stop integration-a >/dev/null
  relay kit stop integration-b >/dev/null
}

main() {
  test_kit_persona_integration
  test_events_pipeline
  test_concurrent_kits
  echo "All integration tests passed"
}

main "$@"
