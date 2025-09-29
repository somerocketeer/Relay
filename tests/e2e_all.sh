#!/usr/bin/env sh
# Run all e2e/edge tests and aggregate results
set -eu

THIS_DIR=$(CDPATH='' cd -- "$(dirname -- "$0")" && pwd -P)

pass=0
fail=0
skip=0

run_test() {
  name="$1"
  path="$2"
  printf 'Running %s... ' "$name"
  out=$(sh "$path" 2>&1)
  status=$?
  if [ $status -eq 0 ]; then
    pass=$((pass+1))
    printf 'OK\n'
  else
    case "$out" in
      SKIP:*)
        skip=$((skip+1))
        printf 'SKIP\n'
        ;;
      *)
        fail=$((fail+1))
        printf 'FAIL\n'
        printf '%s\n' "$out" >&2
        ;;
    esac
  fi
}

run_test base_index "$THIS_DIR/base_index.sh"
run_test persona_overlays "$THIS_DIR/persona_overlays.sh"
run_test persona_dedupe "$THIS_DIR/persona_dedupe.sh"
run_test commands_fallback "$THIS_DIR/commands_fallback.sh"
run_test tilde_and_dir_fallback "$THIS_DIR/tilde_and_dir_fallback.sh"
run_test events "$THIS_DIR/events.sh"
run_test persona_multiline_env "$THIS_DIR/persona_multiline_env.sh"
run_test paths_with_spaces "$THIS_DIR/paths_with_spaces.sh"
run_test crlf_configs "$THIS_DIR/crlf_configs.sh"
run_test unicode_names "$THIS_DIR/unicode_names.sh"
run_test strict_shell_opts "$THIS_DIR/strict_shell_opts.sh"
run_test events_concurrency "$THIS_DIR/events_concurrency.sh"

printf '\nSummary: %d passed, %d failed, %d skipped\n' "$pass" "$fail" "$skip"
[ "$fail" -eq 0 ]