#!/usr/bin/env sh
# Ensure PATH entries with spaces in personas work and precedence is respected
set -eu

REPO_ROOT=$(CDPATH='' cd -- "$(dirname -- "$0")/.." && pwd -P)
BIN="$REPO_ROOT/bin"

TMPDIR=$(mktemp -d)
export RELAY_PERSONAS_DIR="$TMPDIR/personas"
mkdir -p "$RELAY_PERSONAS_DIR"

# Create temp bin dir with spaces
SPACE_DIR="$TMPDIR/dir with space/bin"
mkdir -p "$SPACE_DIR"
cat > "$SPACE_DIR/mybin" <<'EOF'
#!/usr/bin/env sh
echo OK_SPACE_PATH
EOF
chmod +x "$SPACE_DIR/mybin"

# Persona that prepends SPACE_DIR to PATH
mkdir -p "$RELAY_PERSONAS_DIR/pathspace"
cat > "$RELAY_PERSONAS_DIR/pathspace/persona.toml" <<EOF
version = 1
[path]
prepend = ["$SPACE_DIR"]
append = []
EOF

# Apply persona exports
EXP="$TMPDIR/exports.sh"
"$BIN/relay" persona use pathspace > "$EXP"

# Verify command resolution finds our mybin in the spaced path
res=$(sh -lc '. '"$EXP"'; command -v mybin')
case "$res" in
  "$SPACE_DIR"/*) : ;;
  *) echo "FAIL: mybin did not resolve to spaced path (got: $res)" >&2; exit 1;;
esac

# And running it works
out=$(sh -lc '. '"$EXP"'; mybin')
[ "$out" = "OK_SPACE_PATH" ] || { echo "FAIL: mybin did not execute properly" >&2; exit 1; }

echo "OK: PATH with spaces in personas"