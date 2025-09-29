#!/usr/bin/env sh
# Verify that kits apply linked personas before launching tmux sessions.
set -eu

REPO_ROOT=$(CDPATH='' cd -- "$(dirname -- "$0")/.." && pwd -P)
PATH="$REPO_ROOT/bin:$PATH"

TMP_ROOT=$(mktemp -d)
trap 'rm -rf "$TMP_ROOT"' EXIT

KITS_DIR="$TMP_ROOT/kits"
PERSONAS_DIR="$TMP_ROOT/personas"
STUB_BIN="$TMP_ROOT/bin"
mkdir -p "$KITS_DIR/demo" "$PERSONAS_DIR/work" "$PERSONAS_DIR/extra" "$PERSONAS_DIR/override" "$STUB_BIN"

cat > "$PERSONAS_DIR/work/persona.toml" <<'TOML'
version = 1
[env]
KIT_FLAG = "persona-work"

[path]
prepend = ["/tmp/workbin"]
TOML

cat > "$PERSONAS_DIR/extra/persona.toml" <<'TOML'
version = 1
[env]
EXTRA_FLAG = "persona-extra"
TOML

cat > "$KITS_DIR/demo/kit.toml" <<'TOML'
version = 1
session = "demo"
dir = "~/"
attach = false
personas = ["work", "extra"]

[[windows]]
name = "main"
layout = "tiled"
dir = "~/"
panes = [
  "echo demo",
]
TOML

cat > "$PERSONAS_DIR/override/persona.toml" <<'TOML'
version = 1
[env]
KIT_FLAG = "persona-override"
TOML

cat > "$STUB_BIN/tmux" <<'SH'
#!/usr/bin/env sh
cmd=${1:-}
case "$cmd" in
  has-session)
    exit 1
    ;;
  new-session)
    if [ -n "${TMUX_TEST_ENV:-}" ]; then
      env | sort > "$TMUX_TEST_ENV"
    fi
    exit 0
    ;;
  send-keys|new-window|switch-client|kill-session|set-environment)
    exit 0
    ;;
  attach)
    exit 0
    ;;
  *)
    exit 0
    ;;
esac
SH
chmod +x "$STUB_BIN/tmux"

export PATH="$STUB_BIN:$PATH"
export RELAY_KITS_DIR="$KITS_DIR"
export RELAY_PERSONAS_DIR="$PERSONAS_DIR"

# Prevent accidental real tmux detection via existing TMUX variable.
unset TMUX || true

# Default launch applies kit personas in order.
TMUX_TEST_ENV="$TMP_ROOT/env-default.txt" "$REPO_ROOT/bin/relay-kit" start demo >/dev/null

[ -f "$TMP_ROOT/env-default.txt" ] || {
  echo "tmux environment capture missing" >&2
  exit 1
}

grep -q '^KIT_FLAG=persona-work$' "$TMP_ROOT/env-default.txt"
grep -q '^EXTRA_FLAG=persona-extra$' "$TMP_ROOT/env-default.txt"
grep -q '^PATH=' "$TMP_ROOT/env-default.txt" && true

# --no-persona skips kit-linked personas.
TMUX_TEST_ENV="$TMP_ROOT/env-skip.txt" "$REPO_ROOT/bin/relay-kit" start --no-persona demo >/dev/null

[ -f "$TMP_ROOT/env-skip.txt" ] || {
  echo "tmux environment capture missing for --no-persona" >&2
  exit 1
}

if grep -q '^KIT_FLAG=' "$TMP_ROOT/env-skip.txt"; then
  echo "KIT_FLAG should not be present when personas are skipped" >&2
  exit 1
fi
if grep -q '^EXTRA_FLAG=' "$TMP_ROOT/env-skip.txt"; then
  echo "EXTRA_FLAG should not be present when personas are skipped" >&2
  exit 1
fi

# --persona after defaults layers an override persona last.
TMUX_TEST_ENV="$TMP_ROOT/env-layer.txt" "$REPO_ROOT/bin/relay-kit" start demo --persona override >/dev/null

grep -q '^KIT_FLAG=persona-override$' "$TMP_ROOT/env-layer.txt"
grep -q '^EXTRA_FLAG=persona-extra$' "$TMP_ROOT/env-layer.txt"

# Combining --no-persona with --persona applies only the explicit list.
TMUX_TEST_ENV="$TMP_ROOT/env-override.txt" "$REPO_ROOT/bin/relay-kit" start --no-persona --persona override demo >/dev/null

grep -q '^KIT_FLAG=persona-override$' "$TMP_ROOT/env-override.txt"
if grep -q '^EXTRA_FLAG=' "$TMP_ROOT/env-override.txt"; then
  echo "EXTRA_FLAG should not be present when only override persona is applied" >&2
  exit 1
fi
