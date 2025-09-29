#!/usr/bin/env sh
# Non-regression safety test: ensure Relay never writes into protected Linux directories.
set -e

REPO_ROOT=$(CDPATH='' cd -- "$(dirname -- "$0")/.." && pwd -P)
PATH="$REPO_ROOT/bin:$PATH"
snap() {
  dir="$1"; target="$2"
  if [ -d "$dir" ]; then
    find "$dir" -type f -printf '%p %T@ %s\n' | sort > "$target"
  else
    : > "$target"
  fi
}

snap_many() {
  out="$1"
  shift
  : > "$out"
  for dir in "$@"; do
    tmp=$(mktemp "$SNAPDIR/tmp.XXXXXX")
    snap "$dir" "$tmp"
    printf '# %s\n' "$dir" >> "$out"
    cat "$tmp" >> "$out"
    rm -f "$tmp"
  done
}

fail() {
  echo "FAIL: $1" >&2
  exit 1
}

SNAPDIR=$(mktemp -d)
export RELAY_STATE_DIR="$SNAPDIR/state"
export RELAY_DATA_DIR="$SNAPDIR/data"
mkdir -p "$RELAY_STATE_DIR" "$RELAY_DATA_DIR"
PROTECTED_DIRS=${PROTECTED_DIRS:-"$RELAY_DATA_DIR $RELAY_STATE_DIR"}
BEFORE="$SNAPDIR/protected_before.txt"
AFTER="$SNAPDIR/protected_after.txt"

relay events init >/dev/null 2>&1 || true

# shellcheck disable=SC2086
set -- $PROTECTED_DIRS
snap_many "$BEFORE" "$@"

# run a battery of commands
relay help >/dev/null || true
relay version >/dev/null || true
relay doctor >/dev/null || true
relay events init >/dev/null || true
relay kit list >/dev/null || true
relay persona list >/dev/null || true

test_events_filesystem() {
  marker=$(mktemp)
  : > "$marker"
  relay events init >/dev/null 2>&1 || true
  log_backup=""
  log_path="$RELAY_STATE_DIR/events.log"
  if [ -f "$log_path" ]; then
    log_backup=$(mktemp)
    cp -p "$log_path" "$log_backup"
  fi
  relay events emit noreg filesystem >/dev/null 2>&1 || true
  rm -f "$marker"
  if [ -n "$log_backup" ]; then
    mv "$log_backup" "$log_path"
  else
    rm -f "$log_path"
  fi
}

test_events_filesystem

# shellcheck disable=SC2086
set -- $PROTECTED_DIRS
snap_many "$AFTER" "$@"

diff -u "$BEFORE" "$AFTER" && echo "OK: no changes in protected directories"
