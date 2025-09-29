#!/usr/bin/env sh
# Validate pane persona overlay assign/replace/clear behavior
set -eu

REPO_ROOT=$(CDPATH='' cd -- "$(dirname -- "$0")/.." && pwd -P)
BIN="$REPO_ROOT/bin"

TMPDIR=$(mktemp -d)
export RELAY_STATE_DIR="$TMPDIR/state"
export RELAY_DATA_DIR="$TMPDIR/data"
export RELAY_KITS_DIR="$TMPDIR/kits"
export RELAY_PERSONAS_DIR="$TMPDIR/personas"
mkdir -p "$RELAY_STATE_DIR" "$RELAY_DATA_DIR" "$RELAY_KITS_DIR" "$RELAY_PERSONAS_DIR"

# Personas referenced below
for p in alpha beta only; do
  mkdir -p "$RELAY_PERSONAS_DIR/$p"
  cat > "$RELAY_PERSONAS_DIR/$p/persona.toml" <<EOF
version = 1
[env]
P_$p = "$p"
EOF
done

# Kit with a dev window and two panes
mkdir -p "$RELAY_KITS_DIR/e2e"
cat > "$RELAY_KITS_DIR/e2e/kit.toml" <<'EOF'
version = 1
session = "e2e"
dir = "~"
attach = false

[[windows]]
name = "dev"
dir = "~"
layout = "tiled"
panes = [
  "echo one",
  "echo two",
]
EOF

JSON_PATH="$RELAY_KITS_DIR/e2e/pane-personas.json"

# Append alpha,beta onto window=dev pane=2 (indexes are 0-based in file, so key 0:1)
"$BIN/relay" kit persona assign e2e dev:2 alpha beta >/dev/null

grep -q '"0:1"' "$JSON_PATH" || { echo "FAIL: key 0:1 missing" >&2; exit 1; }

compact=$(sed -e ':a;N;$!ba;s/[[:space:]]//g' "$JSON_PATH")
printf '%s\n' "$compact" | grep -E -q '"0:1":\["alpha","beta"\]' || {
  echo "FAIL: expected alpha,beta in order for 0:1" >&2
  printf '%s\n' "$compact" >&2
  exit 1
}

# Replace with only
"$BIN/relay" kit persona assign --replace e2e dev:2 only >/dev/null

compact=$(sed -e ':a;N;$!ba;s/[[:space:]]//g' "$JSON_PATH")
printf '%s\n' "$compact" | grep -E -q '"0:1":\["only"\]' || {
  echo "FAIL: expected only after replace for 0:1" >&2
  printf '%s\n' "$compact" >&2
  exit 1
}

# Clear overlay
"$BIN/relay" kit persona clear e2e dev:2 >/dev/null

# Expect either no key or empty panes map
if grep -q '"0:1"' "$JSON_PATH"; then
  echo "FAIL: key 0:1 still present after clear" >&2
  cat "$JSON_PATH" >&2
  exit 1
fi

echo "OK: persona overlays append/replace/clear"