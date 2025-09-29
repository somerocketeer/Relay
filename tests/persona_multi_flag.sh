#!/usr/bin/env sh
# Ensure multiple --persona flags remain distinct in dry-run output.
set -eu

REPO_ROOT=$(CDPATH='' cd -- "$(dirname -- "$0")/.." && pwd -P)
PATH="$REPO_ROOT/bin:$PATH"

TMPDIR=$(mktemp -d)
# shellcheck disable=SC2329
cleanup() {
  rm -rf "$TMPDIR"
}
trap cleanup EXIT

export RELAY_KITS_DIR="$TMPDIR/kits"
export RELAY_PERSONAS_DIR="$TMPDIR/personas"
mkdir -p "$RELAY_KITS_DIR/multi" "$RELAY_PERSONAS_DIR"

cat >"$RELAY_KITS_DIR/multi/kit.toml" <<'TOML'
version = 1
session = "multi"
dir = "."
attach = false

[[windows]]
name = "main"
dir = "."
panes = [
  "echo hello",
]
TOML

if ! output=$(relay kit start --dry-run multi --persona alpha --persona beta 2>&1); then
  printf '%s\n' "$output" >&2
  exit 1
fi

printf '%s\n' "$output" | grep -q 'Extra personas:' || {
  printf 'missing personas section\n' >&2
  printf '%s\n' "$output" >&2
  exit 1
}

printf '%s\n' "$output" | grep -q '        - alpha' || {
  printf 'expected alpha persona entry\n' >&2
  printf '%s\n' "$output" >&2
  exit 1
}

printf '%s\n' "$output" | grep -q '        - beta' || {
  printf 'expected beta persona entry\n' >&2
  printf '%s\n' "$output" >&2
  exit 1
}

exit 0
