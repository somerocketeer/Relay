#!/usr/bin/env sh
# Ensure persona env values can contain real newlines and quotes
set -eu

REPO_ROOT=$(CDPATH='' cd -- "$(dirname -- "$0")/.." && pwd -P)
BIN="$REPO_ROOT/bin"

TMPDIR=$(mktemp -d)
export RELAY_PERSONAS_DIR="$TMPDIR/personas"
mkdir -p "$RELAY_PERSONAS_DIR"

# Create persona with a newline in the value
mkdir -p "$RELAY_PERSONAS_DIR/multiline"
cat > "$RELAY_PERSONAS_DIR/multiline/persona.toml" <<'EOF'
version = 1
[env]
MULTI = "line1\nline2"
QUOTED = "val 'with' \"quotes\""
EOF

# Apply exports to a temp file to avoid quoting pitfalls
EXP="$TMPDIR/exports.sh"
"$BIN/relay" persona use multiline > "$EXP"

# Expect MULTI to contain exactly one newline char (apply in subshell)
count=$(sh -lc '. '"$EXP"'; python3 -c "import os; v=os.getenv(\"MULTI\",\"\"); print(v.count(\"\\n\"))"')
[ "$count" = "1" ] || { echo "FAIL: expected one newline in MULTI (got $count)" >&2; exit 1; }

# Smoke check that QUOTED survives escaping
out=$(sh -lc '. '"$EXP"'; python3 -c "import os; v=os.getenv(\"QUOTED\",\"\"); print(\"quotes\" in v)"')
[ "$out" = "True" ] || { echo "FAIL: QUOTED lost quotes in export" >&2; exit 1; }

echo "OK: persona multiline env values"