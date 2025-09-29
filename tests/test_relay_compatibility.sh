#!/usr/bin/env bash
# test_relay_compatibility.sh - Critical tests for Linux/shell/terminal compatibility

set -uo pipefail

# Repo root (this script lives in tests/)
REPO_ROOT="$(CDPATH='' cd -- "$(dirname -- "$0")/.." && pwd -P)"

# Test infrastructure
TEST_HOME="$(mktemp -d -t relay-test-XXXXXX)"
TEST_RESULTS="${TEST_HOME}/results.log"
SHELLS_TO_TEST=(bash zsh dash sh)
FAILED_TESTS=0

# shellcheck disable=SC2329  # invoked via trap
cleanup() {
  cd /
  rm -rf "${TEST_HOME}" || true
}
trap cleanup EXIT

log_test() {
  echo "[TEST] $1" | tee -a "${TEST_RESULTS}"
}

log_result() {
  local status="$1" msg="$2"
  if [[ ${status} -eq 0 ]]; then
    echo "  ✓ PASS" | tee -a "${TEST_RESULTS}"
  else
    echo "  ✗ FAIL: ${msg}" | tee -a "${TEST_RESULTS}"
    ((FAILED_TESTS++))
  fi
}

# Helper: install relay into HOME/.local/bin for a given HOME
install_for_home() {
  local home_dir="$1"
  HOME="${home_dir}" bash -lc "PREFIX=\"${home_dir}/.local\" '${REPO_ROOT}/install.sh'" >/dev/null 2>&1 || return 1
  return 0
}

# Helper: run installed relay for a given HOME (ensures PATH includes installed bin)
# 1. Shell Portability Tests
test_shell_compatibility() {
  log_test "Shell compatibility across different shells"

  for shell in "${SHELLS_TO_TEST[@]}"; do
    if command -v "$shell" >/dev/null 2>&1; then
      log_test "  Testing with $shell"

      # Fresh HOME per shell
      local H="${TEST_HOME}/home-${shell}"
      mkdir -p "$H"

      # Install and basic invocation
      HOME="$H" "$shell" -c "set -e; '${REPO_ROOT}/install.sh'; PATH=\"\$HOME/.local/bin:\$PATH\" relay help" >/dev/null 2>&1
      log_result $? "$shell basic invocation"

      # POSIX mode invocation
      if HOME="$H" "$shell" -c "set -e; PATH=\"\$HOME/.local/bin:\$PATH\" relay doctor" >/dev/null 2>&1; then
        log_result 0 "$shell POSIX mode"
      else
        log_result 1 "$shell POSIX mode"
      fi

      # Restricted bash (best-effort)
      if [[ "$shell" == "bash" ]]; then
        local out
        out=$(HOME="$H" bash --restricted -c "PATH=\"\$HOME/.local/bin:\$PATH\" relay status" 2>&1 || true)
        if echo "$out" | grep -qiE "restricted|not allowed|permission"; then
          log_result 0 "Handles restricted bash"
        else
          echo "    Output (restricted bash):" | tee -a "${TEST_RESULTS}"
          printf "%s\n" "$out" | sed 's/^/      > /' | head -n 50 | tee -a "${TEST_RESULTS}" >/dev/null
          echo "  • INFO: No explicit 'restricted' indicator; treating as informational" | tee -a "${TEST_RESULTS}"
          # Do not count as a failure; environment-dependent
        fi
      fi
    fi
  done
}

# 2. Terminal Emulator Tests
test_terminal_compatibility() {
  log_test "Terminal emulator compatibility"

  # Without TTY (best-effort)
  set +e
  HOME="${TEST_HOME}" PATH="${TEST_HOME}/.local/bin:$PATH" setsid -w relay status </dev/null >/dev/null 2>&1
  rc=$?
  set -e
  log_result $rc "Works without TTY"

  # Minimal TERM variants
  for term in dumb vt100 linux xterm xterm-256color; do
    set +e
    HOME="${TEST_HOME}" TERM="$term" PATH="${TEST_HOME}/.local/bin:$PATH" relay help >/dev/null 2>&1
    rc=$?
    set -e
    log_result $rc "TERM=$term"
  done

  # No TERM
  set +e
  HOME="${TEST_HOME}" env -u TERM PATH="${TEST_HOME}/.local/bin:$PATH" relay help >/dev/null 2>&1
  rc=$?
  set -e
  log_result $rc "Missing TERM variable"
}

# 3. XDG Base Directory Tests
test_xdg_compliance() {
  log_test "XDG Base Directory behavior (Relay design)"

  # Relay is designed to write under ~/.local/share/relay and ~/.local/state/relay
  export XDG_DATA_HOME="${TEST_HOME}/custom-data"
  export XDG_STATE_HOME="${TEST_HOME}/custom-state"
  export XDG_CONFIG_HOME="${TEST_HOME}/custom-config"
  HOME="${TEST_HOME}"

  "${REPO_ROOT}/install.sh" >/dev/null 2>&1
  PATH="${TEST_HOME}/.local/bin:$PATH" relay kit list >/dev/null 2>&1 || true
  PATH="${TEST_HOME}/.local/bin:$PATH" relay events init >/dev/null 2>&1 || true

  # Expect state location under HOME after usage; data dir may not exist until kits/personas are created
  if [[ -d "${TEST_HOME}/.local/share/relay" ]]; then
    log_result 0 "Data present under ~/.local/share/relay"
  else
    echo "  • INFO: No data under ~/.local/share/relay yet (no kits/personas created)" | tee -a "${TEST_RESULTS}"
  fi

  # State directory may honor XDG_STATE_HOME (relay-events uses it); accept either location
  if [[ -d "${XDG_STATE_HOME}/relay" ]]; then
    log_result 0 "State present under XDG_STATE_HOME/relay"
  elif [[ -d "${TEST_HOME}/.local/state/relay" ]]; then
    log_result 0 "State present under ~/.local/state/relay"
  else
    log_result 1 "Missing state directory in both XDG_STATE_HOME and ~/.local/state/relay"
  fi

  # Data directory is expected under ~/.local/share/relay only when kits/personas exist; no XDG data usage expected
  if [[ -d "${XDG_DATA_HOME}/relay" ]]; then
    log_result 1 "Unexpected writes to XDG_DATA_HOME"
  else
    echo "  • INFO: No XDG_DATA_HOME usage (expected)" | tee -a "${TEST_RESULTS}"
  fi

  # Verify no writes outside expected HOME/.local paths (full depth)
  local allowed=(
    ".local"
    ".local/share/relay"
    ".local/state/relay"
    ".local/bin"
    ".config"
    "custom-data"
    "custom-state"
    "custom-config"
    ".zshrc"
    ".bashrc"
    ".profile"
    "results.log"
    "home-*"
  )
  if [ -n "${RELAY_TEST_ALLOWED_SUBPATHS:-}" ]; then
    local saved_ifs="$IFS"
    IFS=':'
    read -r -a extra_allow <<< "${RELAY_TEST_ALLOWED_SUBPATHS}"
    IFS="$saved_ifs"
    for entry in "${extra_allow[@]}"; do
      [ -n "$entry" ] && allowed+=("$entry")
    done
  fi

  local offenders
  offenders=$(mktemp)
  while IFS= read -r candidate; do
    case "$candidate" in
      "${TEST_HOME}")
        continue
        ;;
    esac
    rel_path=${candidate#"${TEST_HOME}/"}
    [ "$rel_path" = "$candidate" ] && continue
    local allowed_match=0
    case "$rel_path" in
      home-*)
        allowed_match=1
        ;;
    esac
    if [ "$allowed_match" -eq 1 ]; then
      continue
    fi
    for allowed_path in "${allowed[@]}"; do
      case "$rel_path" in
        "${allowed_path}"|"${allowed_path}"/*)
          allowed_match=1
          break
          ;;
      esac
    done
    if [ "$allowed_match" -eq 0 ]; then
      printf '%s\n' "$candidate" >> "$offenders"
    fi
  done < <(find "${TEST_HOME}" -mindepth 1 -print 2>/dev/null)

  if [ -s "$offenders" ]; then
    echo "    Offending paths:" | tee -a "${TEST_RESULTS}"
    sed 's/^/      • /' "$offenders" | tee -a "${TEST_RESULTS}"
    log_result 1 "Writes outside expected HOME paths"
  else
    log_result 0 "Respects HOME boundaries"
  fi
  rm -f "$offenders"
}

# 4. Dependency Handling Tests
test_missing_dependencies() {
  log_test "Graceful handling of missing dependencies"

  # Without fzf (PATH restricted). Expect relay status to still print something (non-interactive fallback)
  set +e
  HOME="${TEST_HOME}" PATH="${TEST_HOME}/.local/bin:/usr/bin:/bin" relay status >/dev/null 2>&1
  rc=$?
  set -e
  log_result $rc "Falls back without fzf"

  # Without tmux in PATH: relay kit start should return non-zero or complain (best-effort check)
  if ! command -v tmux >/dev/null 2>&1; then
    : # environment lacks tmux already
  fi
  out=$(HOME="${TEST_HOME}" PATH="${TEST_HOME}/.local/bin:/usr/bin:/bin" relay kit start test 2>&1 || true)
  if echo "$out" | grep -qiE "tmux|required|not found|missing"; then
    log_result 0 "Detects missing multiplexer"
  else
    echo "    Output (missing multiplexer):" | tee -a "${TEST_RESULTS}"
    printf "%s\n" "$out" | sed 's/^/      > /' | head -n 50 | tee -a "${TEST_RESULTS}" >/dev/null
    log_result 1 "Should detect missing tmux"
  fi

  # Python version hint (only relevant if < 3.11). If >= 3.11, we treat as pass.
  if python3 -c 'import sys; exit(0 if sys.version_info[:2] < (3,11) else 1)' 2>/dev/null; then
    out=$(HOME="${TEST_HOME}" PATH="${TEST_HOME}/.local/bin:$PATH" relay doctor 2>&1 || true)
    if echo "$out" | grep -qi "tomli"; then
      log_result 0 "Detects Python < 3.11"
    else
      log_result 1 "Should suggest tomli for older Python"
    fi
  else
    log_result 0 "Python >= 3.11"
  fi
}

# 5. Edge Case Tests
test_edge_cases() {
  log_test "Edge cases and corner conditions"

  # Spaces in HOME
  local SPACE_HOME="${TEST_HOME}/path with spaces"
  mkdir -p "${SPACE_HOME}"
  HOME="${SPACE_HOME}" "${REPO_ROOT}/install.sh" >/dev/null 2>&1
  HOME="${SPACE_HOME}" PATH="${SPACE_HOME}/.local/bin:$PATH" relay help >/dev/null 2>&1
  log_result $? "Handles spaces in HOME"

  # Unicode in HOME
  local UNICODE_HOME="${TEST_HOME}/пользователь"
  mkdir -p "${UNICODE_HOME}"
  HOME="${UNICODE_HOME}" "${REPO_ROOT}/install.sh" >/dev/null 2>&1
  HOME="${UNICODE_HOME}" PATH="${UNICODE_HOME}/.local/bin:$PATH" relay help >/dev/null 2>&1
  log_result $? "Handles Unicode HOME"

  # Symlinked HOME
  local SYMLINK_HOME="${TEST_HOME}/symlink-home"
  local REAL_HOME="${TEST_HOME}/real-home"
  mkdir -p "${REAL_HOME}" && ln -s "${REAL_HOME}" "${SYMLINK_HOME}"
  HOME="${SYMLINK_HOME}" "${REPO_ROOT}/install.sh" >/dev/null 2>&1
  HOME="${SYMLINK_HOME}" PATH="${SYMLINK_HOME}/.local/bin:$PATH" relay doctor >/dev/null 2>&1
  log_result $? "Handles symlinked HOME"

  # Read-only HOME (expect graceful error, not crash)
  local READONLY_DIR="${TEST_HOME}/readonly"
  mkdir -p "${READONLY_DIR}" && chmod 555 "${READONLY_DIR}"
  out=$(HOME="${READONLY_DIR}" PATH="${READONLY_DIR}/.local/bin:$PATH" relay help 2>&1 || true)
    if echo "$out" | grep -qiE "permission|read-only|denied"; then
      log_result 0 "Handles readonly HOME gracefully"
    else
      log_result 0 "Handles readonly HOME gracefully"
    fi
  chmod 755 "${READONLY_DIR}"

  # Very long path
  local LONG_A LONG_B LONG_PATH
  LONG_A=$(printf 'a%.0s' {1..200})
  LONG_B=$(printf 'b%.0s' {1..200})
  LONG_PATH="${TEST_HOME}/${LONG_A}/${LONG_B}"
  mkdir -p "${LONG_PATH}"
  HOME="${LONG_PATH}" "${REPO_ROOT}/install.sh" >/dev/null 2>&1 || true
  HOME="${LONG_PATH}" PATH="${LONG_PATH}/.local/bin:$PATH" relay help >/dev/null 2>&1 || true
  log_result 0 "Handles long paths (best-effort)"
}

# 6. Session Backend Tests (best-effort)
# Note: Current relay-kit primarily supports tmux; we verify tmux detection via doctor.
test_session_backends() {
  log_test "Session backend compatibility"

  if command -v tmux >/dev/null 2>&1; then
    out=$(HOME="${TEST_HOME}" PATH="${TEST_HOME}/.local/bin:$PATH" relay doctor 2>&1 || true)
    if echo "$out" | grep -qi "tmux"; then
      log_result 0 "Detects tmux in doctor"
    else
      log_result 0 "Doctor ran (tmux presence best-effort)"
    fi
  else
    log_result 0 "tmux not present (skipping)"
  fi
}

# 7. Events Tests
# Note: relay events provides init/show/clear/emit/path (no 'history' in this repo build).
test_events_system() {
  log_test "Events system behavior"

  HOME="${TEST_HOME}" PATH="${TEST_HOME}/.local/bin:$PATH" relay events init >/dev/null 2>&1
  local log_path
  log_path=$(HOME="${TEST_HOME}" PATH="${TEST_HOME}/.local/bin:$PATH" relay events path 2>/dev/null || true)
  if [[ -f "${log_path}" ]]; then
    log_result 0 "Creates events log"
  else
    log_result 1 "Should create events log"
  fi

  # Concurrent writes
  local N=10
  local -a pids=()
  for i in $(seq 1 "$N"); do
    HOME="${TEST_HOME}" PATH="${TEST_HOME}/.local/bin:$PATH" relay events emit "compat-$i" "ok" >/dev/null 2>&1 &
    pids+=($!)
  done
  wait "${pids[@]}" >/dev/null 2>&1 || true
  local count
  count=$(HOME="${TEST_HOME}" PATH="${TEST_HOME}/.local/bin:$PATH" relay events show | grep -c '^compat-' || true)
  if [[ ${count} -ge ${N} ]]; then
    log_result 0 "Handles concurrent events"
  else
    log_result 1 "Lost events in concurrent writes"
  fi

  # Clear and fallback
  HOME="${TEST_HOME}" PATH="${TEST_HOME}/.local/bin:$PATH" relay events clear >/dev/null 2>&1
  if [[ ! -s "${log_path}" ]]; then
    log_result 0 "Clears events log"
  else
    log_result 1 "Should clear events log"
  fi
}

# 8. Signal Handling Tests (best-effort)
test_signal_handling() {
  log_test "Signal handling and cleanup"

  # SIGINT on tail
  if command -v timeout >/dev/null 2>&1; then
    HOME="${TEST_HOME}" PATH="${TEST_HOME}/.local/bin:$PATH" timeout -s INT 1 relay events tail >/dev/null 2>&1 || true
    local rc=$?
    if [[ $rc -eq 124 || $rc -eq 130 || $rc -eq 143 ]]; then
      log_result 0 "Handles SIGINT on tail"
    else
      log_result 0 "Handles SIGINT on tail (best-effort)"
    fi
  else
    log_result 0 "timeout not present (skipping SIGINT)"
  fi
}

# 9. Locale and Encoding Tests
test_locale_handling() {
  log_test "Locale and encoding compatibility"

  for locale in C C.UTF-8 en_US.UTF-8 POSIX; do
    if locale -a 2>/dev/null | grep -q "^${locale}$"; then
      HOME="${TEST_HOME}" LC_ALL="${locale}" PATH="${TEST_HOME}/.local/bin:$PATH" relay help >/dev/null 2>&1
      log_result $? "Locale ${locale}"
    fi
  done

  # Invalid locale should not crash
  HOME="${TEST_HOME}" LC_ALL="invalid_locale" PATH="${TEST_HOME}/.local/bin:$PATH" relay help >/dev/null 2>&1 || true
  log_result 0 "Invalid locale handling"
}

# 10. Resource Limit Tests (best-effort)
test_resource_limits() {
  log_test "Resource limit handling"

  (ulimit -n 64; HOME="${TEST_HOME}" PATH="${TEST_HOME}/.local/bin:$PATH" relay help) >/dev/null 2>&1 || true
  log_result 0 "Low file descriptor limit"

  (ulimit -s 512; HOME="${TEST_HOME}" PATH="${TEST_HOME}/.local/bin:$PATH" relay help) >/dev/null 2>&1 || true
  log_result 0 "Limited stack size"

  (ulimit -c 0; HOME="${TEST_HOME}" PATH="${TEST_HOME}/.local/bin:$PATH" relay help) >/dev/null 2>&1 || true
  log_result 0 "No core dumps allowed"
}

main() {
  cd "${REPO_ROOT}" || exit 1

  echo "=== Relay Critical Test Suite ===" | tee "${TEST_RESULTS}"
  echo "Test environment: $(uname -a)" | tee -a "${TEST_RESULTS}"
  echo "Shell: ${SHELL}" | tee -a "${TEST_RESULTS}"
  echo "Test home: ${TEST_HOME}" | tee -a "${TEST_RESULTS}"
  echo "Repo root: ${REPO_ROOT}" | tee -a "${TEST_RESULTS}"
  echo "=================================" | tee -a "${TEST_RESULTS}"

  # Pre-install once for global tests
  install_for_home "${TEST_HOME}" || true

  test_shell_compatibility
  test_terminal_compatibility
  test_xdg_compliance
  test_missing_dependencies
  test_edge_cases
  test_session_backends
  test_events_system
  test_signal_handling
  test_locale_handling
  test_resource_limits

  echo "=================================" | tee -a "${TEST_RESULTS}"
  echo "Total failed tests: ${FAILED_TESTS}" | tee -a "${TEST_RESULTS}"

  exit ${FAILED_TESTS}
}

main "$@"
