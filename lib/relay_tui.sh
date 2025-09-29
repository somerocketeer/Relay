# shellcheck shell=sh
# Shared helpers for the Relay fzf-driven TUI.

RELAY_TUI_INIT_DONE=${RELAY_TUI_INIT_DONE:-0}
RELAY_TUI_COLORS_APPLIED=${RELAY_TUI_COLORS_APPLIED:-0}
RELAY_TUI_FEATURES=${RELAY_TUI_FEATURES:-}
RELAY_TUI_KITS_STATUS_READY=${RELAY_TUI_KITS_STATUS_READY:-0}
RELAY_TUI_KITS_STATUS_DATA=${RELAY_TUI_KITS_STATUS_DATA:-}
RELAY_TUI_CACHE_DISABLE=${RELAY_TUI_CACHE_DISABLE:-0}

relay_tui_root_dir() {
  if [ -n "${RELAY_TUI_ROOT_DIR:-}" ]; then
    printf '%s\n' "$RELAY_TUI_ROOT_DIR"
    return 0
  fi
  base="${RELAY_TUI_BIN_DIR:-${RELAY_TUI_RELAY_BIN:-.}}"
  if [ -f "$base" ]; then
    base_dir=$(dirname "$base")
  else
    base_dir="$base"
  fi
  RELAY_TUI_ROOT_DIR=$(CDPATH='' cd -- "$base_dir/.." && pwd -P)
  export RELAY_TUI_ROOT_DIR
  printf '%s\n' "$RELAY_TUI_ROOT_DIR"
}

relay_tui_lib_dir() {
  root=$(relay_tui_root_dir) || return 1
  printf '%s/lib\n' "$root"
}

relay_tui_state_dir() {
  if [ -n "${RELAY_STATE_DIR:-}" ]; then
    printf '%s\n' "$RELAY_STATE_DIR"
    return 0
  fi
  base="${XDG_STATE_HOME:-$HOME/.local/state}"
  printf '%s/relay\n' "$base"
}

relay_tui__feature_add() {
  name="$1"
  case " $RELAY_TUI_FEATURES " in
    *" $name "*)
      return 0
      ;;
  esac
  if [ -n "$RELAY_TUI_FEATURES" ]; then
    RELAY_TUI_FEATURES="$RELAY_TUI_FEATURES $name"
  else
    RELAY_TUI_FEATURES="$name"
  fi
  export RELAY_TUI_FEATURES
}

relay_tui_feature_enabled() {
  name="$1"
  case " $RELAY_TUI_FEATURES " in
    *" $name "*)
      return 0
      ;;
  esac
  return 1
}

relay_tui_cache_enabled() {
  [ "${RELAY_TUI_CACHE_DISABLE:-0}" != "1" ]
}

relay_tui_cache_dir() {
  state_root=$(relay_tui_state_dir) || return 1
  root="$state_root/cache"
  if [ -d "$root" ]; then
    printf '%s\n' "$root"
    return 0
  fi
  mkdir -p "$root" 2>/dev/null || return 1
  printf '%s\n' "$root"
}

relay_tui_cache_path() {
  key="$1"
  if ! relay_tui_cache_enabled; then
    return 1
  fi
  root=$(relay_tui_cache_dir 2>/dev/null) || {
    RELAY_TUI_CACHE_DISABLE=1
    return 1
  }
  printf '%s/%s.cache\n' "$root" "$key"
}

relay_tui_cache_remove() {
  key="$1"
  path=$(relay_tui_cache_path "$key" 2>/dev/null)
  [ -n "$path" ] || return 0
  rm -f "$path"
}

relay_tui_history_label() {
  token="$1"
  case "$token" in
    menu)
      printf '%s\n' 'Menu'
      ;;
    kits)
      printf '%s\n' 'Kits'
      ;;
    personas)
      printf '%s\n' 'Personas'
      ;;
    events)
      printf '%s\n' 'Events'
      ;;
    doctor)
      printf '%s\n' 'Doctor'
      ;;
    status)
      printf '%s\n' 'Status'
      ;;
    *)
      printf '%s\n' "$token"
      ;;
  esac
}

relay_tui_history_reset() {
  RELAY_TUI_HISTORY='menu'
  export RELAY_TUI_HISTORY
}

relay_tui_history_push() {
  token="$1"
  [ -n "$token" ] || return 0
  history="${RELAY_TUI_HISTORY:-menu}"
  last=${history##*|}
  if [ "$last" = "$token" ]; then
    return 0
  fi
  if [ -z "$history" ]; then
    history="$token"
  else
    history="$history|$token"
  fi
  RELAY_TUI_HISTORY="$history"
  export RELAY_TUI_HISTORY
}

relay_tui_history_pop() {
  history="${RELAY_TUI_HISTORY:-menu}"
  case "$history" in
    *'|'*)
      RELAY_TUI_HISTORY="${history%|*}"
      ;;
    *)
      relay_tui_history_reset
      return 0
      ;;
  esac
  [ -n "$RELAY_TUI_HISTORY" ] || relay_tui_history_reset
  export RELAY_TUI_HISTORY
}

relay_tui_history_render() {
  history="${RELAY_TUI_HISTORY:-menu}"
  history=${history#|}
  if [ -z "$history" ]; then
    history='menu'
  fi
  rendered=''
  tokens=$(printf '%s\n' "$history" | tr '|' ' ')
  for token in $tokens; do
    label=$(relay_tui_history_label "$token")
    if [ -z "$rendered" ]; then
      rendered="$label"
    else
      rendered="$rendered > $label"
    fi
  done
  printf '%s\n' "$rendered"
}

relay_tui_format_keybind_header() {
  prefix="$1"
  shift
  header=""
  separator=''
  while [ $# -gt 0 ]; do
    entry="$1"
    shift
    key=${entry%%:*}
    desc=${entry#*:}
    header="$header$separator$key ($desc)"
    separator='  |  '
  done
  if [ -n "$prefix" ]; then
    printf '%s %s\n' "$prefix" "$header"
  else
    printf '%s\n' "$header"
  fi
}

relay_tui_prompt_confirm() {
  message="$1"
  if [ -z "$message" ]; then
    message='Proceed?'
  fi
  printf '%s [y/N]: ' "$message" >&2
  if [ -r /dev/tty ]; then
    if ! IFS= read -r reply </dev/tty; then
      printf '\n' >&2
      return 1
    fi
  else
    if ! IFS= read -r reply; then
      printf '\n' >&2
      return 1
    fi
  fi
  if [ -z "$reply" ]; then
    printf '\n' >&2
    return 1
  fi
  normalized=$(printf '%s\n' "$reply" | tr '[:upper:]' '[:lower:]')
  printf '\n' >&2
  case "$normalized" in
    y|yes)
      return 0
      ;;
  esac
  return 1
}

relay_tui_popup_confirm() {
  prompt="$1"
  detail="$2"
  if ! command -v fzf >/dev/null 2>&1; then
    return 1
  fi
  header="$prompt"
  if [ -n "$detail" ]; then
    header=$(printf '%s\n%s' "$header" "$detail")
  fi
  selection=$(printf 'Yes\nNo\n' | fzf \
    --prompt=' Confirm > ' \
    --header "$header" \
    --pointer '>' \
    --height=30% \
    --border \
    --cycle \
    --no-multi \
    --exit-0)
  status=$?
  if [ $status -ne 0 ] || [ -z "$selection" ]; then
    return 1
  fi
  [ "$selection" = "Yes" ]
}

relay_tui_fzf_status_is_cancel() {
  status="$1"
  case "$status" in
    1|130)
      return 0
      ;;
  esac
  return 1
}

relay_tui_setup_colors() {
  if [ "${RELAY_TUI_COLORS_APPLIED:-0}" = "1" ]; then
    return 0
  fi
  RELAY_TUI_COLORS_APPLIED=1
  opts='--height=90% --layout=reverse --border'
  if relay_tui_feature_enabled ansi; then
    opts="$opts --ansi"
  fi
  if [ -n "${FZF_DEFAULT_OPTS:-}" ]; then
    FZF_DEFAULT_OPTS="$FZF_DEFAULT_OPTS $opts"
  else
    FZF_DEFAULT_OPTS="$opts"
  fi
  export FZF_DEFAULT_OPTS
  return 0
}

relay_tui_detect_colors() {
  if [ "${RELAY_TUI_PLAIN:-}" = "1" ]; then
    return 0
  fi
  colors=-1
  if command -v tput >/dev/null 2>&1; then
    colors=$(tput colors 2>/dev/null || printf '%s' '-1')
  fi
  case $colors in
    ''|*[!0-9]*)
      colors=-1
      ;;
  esac
  if [ "$colors" -ge 8 ] 2>/dev/null; then
    relay_tui__feature_add ansi
  fi
  if [ "$colors" -ge 256 ] 2>/dev/null; then
    relay_tui__feature_add ansi256
  fi
  return 0
}

relay_tui_detect_commands() {
  if command -v tmux >/dev/null 2>&1; then
    relay_tui__feature_add tmux
  fi
  if command -v bat >/dev/null 2>&1; then
    relay_tui__feature_add bat
  fi
  if command -v fzf >/dev/null 2>&1; then
    relay_tui__feature_add fzf
    if fzf --help 2>&1 | grep -q 'change-query'; then
      relay_tui__feature_add fzf_change_query
    fi
  fi
  return 0
}

relay_tui_init() {
  if [ "${RELAY_TUI_INIT_DONE:-0}" = "1" ]; then
    return 0
  fi
  RELAY_TUI_INIT_DONE=1
  RELAY_TUI_FEATURES=""
  if [ "${RELAY_TUI_PLAIN:-}" = "1" ]; then
    relay_tui__feature_add plain
  fi
  relay_tui_detect_commands
  relay_tui_detect_colors
  export RELAY_TUI_FEATURES
  relay_tui_setup_colors
  return 0
}

relay_tui_require_tmux() {
  if relay_tui_feature_enabled tmux; then
    return 0
  fi
  printf '%s\n' 'relay-tui: tmux not detected; run "relay doctor" for setup guidance or set RELAY_TUI_PLAIN=1 for reduced mode.' >&2
  return 1
}

relay_tui_kits_status_reset() {
  RELAY_TUI_KITS_STATUS_READY=0
  RELAY_TUI_KITS_STATUS_DATA=''
}

relay_tui_run() {
  if [ -n "${RELAY_TUI_RELAY_BIN:-}" ] && [ -x "$RELAY_TUI_RELAY_BIN" ]; then
    "$RELAY_TUI_RELAY_BIN" "$@"
    status=$?
    relay_tui_kits_status_reset
    return $status
  fi
  printf 'relay-tui: relay binary unavailable (%s); run from the Relay install root.\n' "${RELAY_TUI_RELAY_BIN:-unset}" >&2
  return 127
}

relay_tui_banner() {
  cat <<'EOF'
 ███████████   ██████████ █████         █████████   █████ █████
░░███░░░░░███ ░░███░░░░░█░░███         ███░░░░░███ ░░███ ░░███ 
 ░███    ░███  ░███  █ ░  ░███        ░███    ░███  ░░███ ███  
 ░██████████   ░██████    ░███        ░███████████   ░░█████   
 ░███░░░░░███  ░███░░█    ░███        ░███░░░░░███    ░░███    
 ░███    ░███  ░███ ░   █ ░███      █ ░███    ░███     ░███    
 █████   █████ ██████████ ███████████ █████   █████    █████   
░░░░░   ░░░░░ ░░░░░░░░░░ ░░░░░░░░░░░ ░░░░░   ░░░░░    ░░░░░    
EOF
}

relay_tui_menu_entries() {
  cat <<'EOF'
kits	[K] Kits	Manage tmux kits and sessions
personas	[P] Personas	Inspect persona overlays
events	[E] Events	Review recent relay events
doctor	[D] Doctor	Run environment diagnostics
status	[S] Status	Show the status board
EOF
}
relay_tui_quick_jump() {
  history=$(relay_tui_history_render)
  tab_char=$(printf '\t')
  cat <<EOF | fzf \
    --prompt=' Jump > ' \
    --header="$history" \
    --delimiter="$tab_char" \
    --with-nth=2 \
    --pointer='>' \
    --exit-0 \
    --height=40%
kits${tab_char}$(relay_tui_history_label kits)
personas${tab_char}$(relay_tui_history_label personas)
events${tab_char}$(relay_tui_history_label events)
doctor${tab_char}$(relay_tui_history_label doctor)
status${tab_char}$(relay_tui_history_label status)
EOF
}
relay_tui_menu() {
  relay_tui_setup_colors
  preview_arg="${RELAY_TUI_BIN_DIR:-.}/relay-tui preview {1}"
  relay_tui_history_reset
  header=$(relay_tui_format_keybind_header '' \
    'Enter:Open' \
    'Ctrl-C:Exit')
  while :; do
    history_header=$(relay_tui_history_render)
    combined_header=$(printf '%s\n\n%s' "$history_header" "$header")
    result=$(relay_tui_menu_entries | fzf \
      --delimiter '\t' \
      --with-nth=2,3 \
      --prompt ' > ' \
      --info=hidden \
      --pointer '>' \
      --expect=ctrl-j \
      --preview "$preview_arg" \
      --preview-window=down,60%,border \
      --header "$combined_header")
    status=$?
    if [ $status -ne 0 ] || [ -z "$result" ]; then
      if relay_tui_fzf_status_is_cancel "$status"; then
        return 0
      fi
      return "$status"
    fi
    key=$(printf '%s\n' "$result" | sed -n '1p')
    selection=$(printf '%s\n' "$result" | sed -n '2p')
    if [ "$key" = 'ctrl-j' ]; then
      jump_target=$(relay_tui_quick_jump)
      [ -n "$jump_target" ] || continue
      id=$(printf '%s\n' "$jump_target" | cut -f1)
    else
      if [ -z "$selection" ]; then
        selection="$key"
      fi
      id=$(printf '%s\n' "$selection" | cut -f1)
    fi
    [ -n "$id" ] || continue
    relay_tui_history_push "$id"
    printf '\n'
    relay_tui_action "$id"
    printf '\n'
    relay_tui_history_pop
  done
}

relay_tui_preview() {
  item="$1"
  case "$item" in
    kits)
      relay_tui_preview_kits
      ;;
    personas)
      relay_tui_preview_personas
      ;;
    events)
      relay_tui_preview_events
      ;;
    doctor)
      relay_tui_preview_doctor
      ;;
    status)
      relay_tui_preview_status
      ;;
    *)
      printf '%s\n' 'Select an item to see its preview.'
      ;;
  esac
}

relay_tui_preview_kits() {
  if relay_tui_feature_enabled tmux; then
    output=$(relay_tui_run kit status 2>&1)
    status=$?
    if [ $status -ne 0 ]; then
      printf '%s\n' "$output"
      printf '\n%s\n' 'Tip: ensure tmux sessions are reachable or run relay kit list.'
      return 1
    fi
    trimmed=$(printf '%s' "$output" | tr -d '\t\r\n ')
    if [ -z "$trimmed" ]; then
      printf '%s\n' 'No kits found. Run relay kit edit <name> to create one.'
    else
      printf '%s\n' "$output"
    fi
    return 0
  fi
  printf '%s\n\n' 'tmux missing; showing available kits.'
  listing=$(relay_tui_run kit list 2>&1)
  if [ -n "$listing" ]; then
    printf '%s\n' "$listing"
  else
    printf '%s\n' 'No kits found. Run relay kit edit <name> to create one.'
  fi
}

relay_tui_preview_personas() {
  tmp=$(mktemp 2>/dev/null)
  if [ -z "$tmp" ]; then
    relay_tui_run persona list
    return 0
  fi
  if ! relay_tui_personas_rows > "$tmp"; then
    rm -f "$tmp"
    printf '%s\n' 'No personas found. Run relay persona new to create one.'
    return 0
  fi
  printf 'Personas (active marked with *):\n'
  tab_char=$(printf '\t')
  while IFS=$tab_char read -r symbol name desc; do
    printf '  %s %-24s %s\n' "$symbol" "$name" "$desc"
  done < "$tmp"
  rm -f "$tmp"
}

relay_tui_events_log_path() {
  state_dir=${RELAY_STATE_DIR:-${XDG_STATE_HOME:-$HOME/.local/state}/relay}
  log_file=${RELAY_EVENT_LOG:-$state_dir/events.log}
  printf '%s\n' "$log_file"
}

relay_tui_events_ensure_log() {
  log_path=$(relay_tui_events_log_path)
  if [ -f "$log_path" ]; then
    return 0
  fi
  relay_tui_run events init >/dev/null 2>&1 || return 1
  [ -f "$log_path" ]
}

relay_tui_events_rows() {
  limit=${1:-100}
  log_path=$(relay_tui_events_log_path)
  if [ ! -f "$log_path" ]; then
    return 1
  fi
  if ! command -v python3 >/dev/null 2>&1; then
    tab=$(printf '\t')
    tail -n "$limit" "$log_path" | awk -F'|' -v tab="$tab" '
      NF==0 { next }
      { idx += 1 }
      { type=$1 }
      { ts = (NF >= 2 ? $2 : "") }
      {
        msg=""
        if (NF > 2) {
          for (i=3; i<=NF; i++) {
            if (i>3) msg = msg "|"
            msg = msg $i
          }
        }
      }
      {
        print idx tab type tab ts tab msg tab $0
      }
    '
    return 0
  fi
  python3 - "$log_path" "$limit" <<'PY'
import os
import sys
from datetime import datetime

path = sys.argv[1]
limit = int(sys.argv[2]) if len(sys.argv) > 2 else 100
if not os.path.exists(path):
    sys.exit(1)

with open(path, 'r', encoding='utf-8', errors='replace') as fh:
    lines = [line.rstrip('\n') for line in fh]

if not lines:
    sys.exit(1)

selected = lines[-limit:]
tab = '\t'

def format_ts(value):
    try:
        ts = int(value)
        return datetime.fromtimestamp(ts).strftime('%Y-%m-%d %H:%M:%S')
    except Exception:
        return value

for idx, raw in enumerate(reversed(selected), 1):
    parts = raw.split('|')
    if len(parts) >= 2:
        event_type = parts[0]
        timestamp = format_ts(parts[1])
        message = '|'.join(parts[2:]) if len(parts) > 2 else ''
    else:
        event_type = raw
        timestamp = ''
        message = ''
    print(f"{idx}{tab}{event_type}{tab}{timestamp}{tab}{message}{tab}{raw}")
PY
}

relay_tui_events_detail() {
  event_id="$1"
  if [ -z "$event_id" ]; then
    printf '%s\n' 'No event selected.'
    return 0
  fi
  if ! command -v python3 >/dev/null 2>&1; then
    relay_tui_events_rows "$event_id" | sed -n "1p"
    return 0
  fi
  log_path=$(relay_tui_events_log_path)
  if [ ! -f "$log_path" ]; then
    printf '%s\n' 'Event log not available.'
    return 1
  fi
  python3 - "$log_path" "$event_id" <<'PY'
import os
import sys
from datetime import datetime

path = sys.argv[1]
target_index = int(sys.argv[2])

if not os.path.exists(path):
    sys.exit(1)

with open(path, 'r', encoding='utf-8', errors='replace') as fh:
    lines = [line.rstrip('\n') for line in fh]

if not lines:
    sys.exit(1)

selected = lines[-200:]
selected.reverse()

if target_index < 1 or target_index > len(selected):
    print('Event no longer available (refresh).')
    sys.exit(0)

raw = selected[target_index - 1]
parts = raw.split('|')

print(f'Raw: {raw}')

if len(parts) >= 2:
    event_type = parts[0]
    timestamp = parts[1]
    try:
        stamp = datetime.fromtimestamp(int(timestamp)).strftime('%Y-%m-%d %H:%M:%S')
    except Exception:
        stamp = timestamp
    message = '|'.join(parts[2:]) if len(parts) > 2 else ''
    print(f'Type: {event_type}')
    print(f'Time: {stamp}')
    print(f'Seconds: {timestamp}')
    if message:
        print('\nMessage:')
        print(f'  {message}')
else:
    print('Unable to parse event payload.')
PY
}

relay_tui_events_emit_prompt() {
  printf 'Event type: ' >&2
  if ! IFS= read -r ev_type; then
    return 1
  fi
  ev_type=$(printf '%s\n' "$ev_type" | sed 's/^[[:space:]]*//;s/[[:space:]]*$//')
  if [ -z "$ev_type" ]; then
    printf '%s\n' 'No event type provided.' >&2
    return 1
  fi
  printf 'Message (optional): ' >&2
  if ! IFS= read -r ev_msg; then
    ev_msg=""
  fi
  if [ -n "$ev_msg" ]; then
    relay_tui_run events emit "$ev_type" "$ev_msg"
  else
    relay_tui_run events emit "$ev_type"
  fi
}

relay_tui_events_clear_prompt() {
  printf 'Clear event log? [y/N]: ' >&2
  if ! IFS= read -r answer; then
    return 1
  fi
  case $(printf '%s\n' "$answer" | tr '[:upper:]' '[:lower:]') in
    y|yes)
      relay_tui_run events clear
      ;;
    *)
      printf '%s\n' 'Aborted.' >&2
      ;;
  esac
}

relay_tui_events_tail() {
  relay_tui_run events tail
}

relay_tui_events() {
  relay_tui_setup_colors
  relay_tui_events_ensure_log || {
    printf '%s\n' 'Event log unavailable and could not be initialized.'
    return 1
  }
  while :; do
    rows=$(relay_tui_events_rows 200 2>/dev/null)
    if [ -z "$rows" ]; then
      printf '%s\n' 'No events recorded yet. Use ctrl-e to emit a test event.'
      return 0
    fi
    selection=$(printf '%s\n' "$rows" | fzf \
      --delimiter '\t' \
      --with-nth=2,3,4 \
      --prompt 'Events > ' \
      --preview "${RELAY_TUI_BIN_DIR:-.}/relay-tui events-preview {1}" \
      --preview-window=down,60% \
      --expect=enter,ctrl-e,ctrl-t,ctrl-c,ctrl-r)
    status=$?
    if [ $status -ne 0 ]; then
      return "$status"
    fi
    key=$(printf '%s\n' "$selection" | sed -n '1p')
    choice=$(printf '%s\n' "$selection" | sed -n '2p')
    case "$key" in
      ctrl-e)
        relay_tui_events_emit_prompt
        continue
        ;;
      ctrl-t)
        relay_tui_events_tail
        continue
        ;;
      ctrl-c)
        relay_tui_events_clear_prompt
        continue
        ;;
      ctrl-r)
        continue
        ;;
    esac
    if [ -z "$choice" ]; then
      return 1
    fi
    event_id=$(printf '%s\n' "$choice" | cut -f1)
    relay_tui_events_detail "$event_id"
    printf '\n'
  done
}
relay_tui_preview_events() {
  if ! relay_tui_events_rows 10 >/dev/null 2>&1; then
    printf '%s\n' 'No events recorded yet.'
    printf '%s\n' 'Run relay events emit info "Hello" to add an entry.'
    return 0
  fi
  relay_tui_events_rows 10
}

relay_tui_preview_doctor() {
  relay_tui_run doctor 2>&1
}

relay_tui_preview_status() {
  relay_tui_banner
  printf '\n'
  relay_tui_run status 2>&1
}

relay_tui_action() {
  item="$1"
  case "$item" in
    kits)
      relay_tui_kits
      ;;
    personas)
      relay_tui_personas
      ;;
    events)
      relay_tui_events
      ;;
    doctor)
      relay_tui_run doctor
      ;;
    status)
      relay_tui_run status
      ;;
    *)
      printf 'relay-tui: unknown selection "%s"\n' "$item" >&2
      return 2
      ;;
  esac
}

relay_tui_kits_dir() {
  if [ -n "${RELAY_KITS_DIR:-}" ]; then
    printf '%s\n' "${RELAY_KITS_DIR%/}"
    return
  fi
  printf '%s\n' "$HOME/.local/share/relay/kits"
}

relay_tui_kits_status_data_load() {
  if [ "${RELAY_TUI_KITS_STATUS_READY:-0}" = "1" ]; then
    return 0
  fi
  RELAY_TUI_KITS_STATUS_DATA=$(relay_tui_run kit status 2>/dev/null || printf '')
  RELAY_TUI_KITS_STATUS_READY=1
  return 0
}

relay_tui_kits_status_of() {
  name="$1"
  relay_tui_kits_status_data_load
  if [ -z "${RELAY_TUI_KITS_STATUS_DATA:-}" ]; then
    return 1
  fi
  printf '%s\n' "$RELAY_TUI_KITS_STATUS_DATA" | awk -F': ' -v n="$name" 'index($1, n) == 1 && $1 == n { print $2; exit }'
}

relay_tui_kits_status_symbol() {
  status="$1"
  case "$status" in
    running|active|attached)
      printf '*'
      ;;
    stopped|inactive|'')
      printf '-'
      ;;
    *)
      printf '!'
      ;;
  esac
}

relay_tui_kit_description() {
  kit_path="$1"
  kit_file="$kit_path/kit.toml"
  if [ -f "$kit_file" ]; then
    desc=$(sed -n 's/^[[:space:]]*description[[:space:]]*=[[:space:]]*"\(.*\)"[[:space:]]*$/\1/p' "$kit_file" | sed -n '1p')
    if [ -n "$desc" ]; then
      printf '%s\n' "$desc"
      return 0
    fi
  fi
  printf 'Kit directory: %s\n' "$kit_path"
}

relay_tui_kits_cache_valid() {
  cache_file="$1"
  dir=$(relay_tui_kits_dir)
  [ -s "$cache_file" ] || return 1
  [ -d "$dir" ] || return 1
  if find "$dir" -mindepth 1 -maxdepth 1 -type d -newer "$cache_file" 2>/dev/null | head -n 1 | read -r _; then
    return 1
  fi
  if find "$dir" -name 'kit.toml' -type f -newer "$cache_file" 2>/dev/null | head -n 1 | read -r _; then
    return 1
  fi
  tab_char=$(printf '\t')
  while IFS=$tab_char read -r name _; do
    [ -n "$name" ] || continue
    if [ ! -d "$dir/$name" ]; then
      return 1
    fi
  done < "$cache_file"
  return 0
}

relay_tui_kits_listing_generate() {
  dir=$(relay_tui_kits_dir)
  if [ ! -d "$dir" ]; then
    return 1
  fi
  set -- "$dir"/*
  if [ "$1" = "$dir/*" ]; then
    return 1
  fi
  tab_char=$(printf '\t')
  for kit_path in "$@"; do
    [ -d "$kit_path" ] || continue
    name=${kit_path##*/}
    desc=$(relay_tui_kit_description "$kit_path")
    desc=$(printf '%s\n' "$desc" | tr '\t' ' ')
    printf '%s\t%s\n' "$name" "$desc"
  done | sort -t "$tab_char" -k1,1
}

relay_tui_kits_listing() {
  if ! relay_tui_cache_enabled; then
    relay_tui_kits_listing_generate
    return $?
  fi
  cache_path=$(relay_tui_cache_path 'kits-listing')
  if [ -z "$cache_path" ]; then
    relay_tui_kits_listing_generate
    return $?
  fi
  if [ -f "$cache_path" ] && relay_tui_kits_cache_valid "$cache_path"; then
    cat "$cache_path"
    return 0
  fi
  listing=$(relay_tui_kits_listing_generate 2>/dev/null)
  status=$?
  [ $status -eq 0 ] || return $status
  if [ -z "$listing" ]; then
    rm -f "$cache_path"
    return 1
  fi
  printf '%s\n' "$listing"
  printf '%s\n' "$listing" > "$cache_path" 2>/dev/null || true
  return 0
}

relay_tui_kits_rows() {
  listing=$(relay_tui_kits_listing 2>/dev/null)
  [ -n "$listing" ] || return 1
  tab_char=$(printf '\t')
  printf '%s\n' "$listing" | while IFS=$tab_char read -r name desc; do
    [ -n "$name" ] || continue
    status=$(relay_tui_kits_status_of "$name")
    symbol=$(relay_tui_kits_status_symbol "$status")
    printf '%s\t%-24s\t%s\n' "$symbol" "$name" "$desc"
  done
}

relay_tui_kits_create() {
  printf 'Enter new kit name: ' >&2
  if ! IFS= read -r name; then
    return 1
  fi
  name=$(printf '%s\n' "$name" | sed 's/^[[:space:]]*//;s/[[:space:]]*$//')
  if [ -z "$name" ]; then
    printf '%s\n' 'No kit name provided.' >&2
    return 1
  fi
  relay_tui_run kit edit "$name"
  relay_tui_cache_remove 'kits-listing'
}

relay_tui_kits_delete() {
  kit="$1"
  if [ -z "$kit" ]; then
    printf '%s\n' 'relay-tui: no kit selected for deletion.' >&2
    return 1
  fi
  dir=$(relay_tui_kits_dir)/$kit
  if [ ! -d "$dir" ]; then
    printf 'relay-tui: kit directory missing: %s\n' "$dir" >&2
    return 1
  fi
  if ! relay_tui_popup_confirm "Delete kit \"$kit\"?" "$dir"; then
    printf '%s\n' 'relay-tui: kit deletion cancelled.' >&2
    return 1
  fi
  if ! rm -rf -- "$dir"; then
    printf 'relay-tui: failed to delete kit "%s".\n' "$kit" >&2
    return 1
  fi
  relay_tui_kits_status_reset
  relay_tui_cache_remove 'kits-listing'
  printf 'relay-tui: deleted kit "%s".\n' "$kit" >&2
  return 0
}

relay_tui_kit_session_name() {
  printf 'relay-%s\n' "$1"
}

relay_kit_smart_action() {
  kit="$1"
  status=$(relay_tui_kits_status_of "$kit")
  if [ "$status" = "running" ] || [ "$status" = "active" ]; then
    if ! command -v tmux >/dev/null 2>&1; then
      relay_tui_require_tmux
      return 1
    fi
    session=$(relay_tui_kit_session_name "$kit")
    if [ -n "${TMUX:-}" ]; then
      tmux switch-client -t "$session"
    else
      tmux attach -t "$session"
    fi
    return $?
  fi
  relay_tui_run kit start "$kit"
}

relay_tui_kits_preview_file() {
  file="$1"
  if relay_tui_feature_enabled bat && command -v bat >/dev/null 2>&1; then
    color_flag='--color=never'
    if relay_tui_feature_enabled ansi; then
      color_flag='--color=always'
    fi
    bat --style=plain --paging=never $color_flag --language=toml "$file"
  else
    sed 's/^/  /' "$file"
  fi
}

relay_tui_kits_preview() {
  kit="$1"
  if [ -z "$kit" ]; then
    printf '%s\n' 'No kit selected.'
    return 0
  fi
  dir=$(relay_tui_kits_dir)/$kit
  status=$(relay_tui_kits_status_of "$kit")
  [ -n "$status" ] || status='unknown'
  printf 'Kit: %s\n' "$kit"
  printf 'Status: %s\n' "$status"
  printf 'Directory: %s\n' "$dir"
  if [ "$status" = "running" ] && command -v tmux >/dev/null 2>&1; then
    session=$(relay_tui_kit_session_name "$kit")
    windows=$(tmux list-windows -t "$session" -F '#{window_index}\t#{window_name}\t#{window_panes}' 2>/dev/null || printf '')
    if [ -n "$windows" ]; then
      printf '\nWindows:\n'
      printf '%s\n' "$windows" | while IFS=$(printf '\t') read -r idx label panes; do
        [ -n "$idx" ] || continue
        if [ -z "$label" ]; then
          label="window$idx"
        fi
        printf '  %s (%s panes)\n' "$label" "${panes:-0}"
      done
    fi
  fi
  kit_file="$dir/kit.toml"
  if [ -f "$kit_file" ]; then
    printf '\nkit.toml:\n'
    relay_tui_kits_preview_file "$kit_file"
  else
    printf '\n%s\n' 'kit.toml not found.'
  fi
}

relay_tui_kits() {
  relay_tui_setup_colors
  while :; do
    rows=$(relay_tui_kits_rows 2>/dev/null)
    if [ -z "$rows" ]; then
      printf '%s\n' 'No kits found.'
      if relay_tui_popup_confirm 'Create a new kit now?' 'This opens "relay kit edit".'; then
        relay_tui_kits_create
        relay_tui_kits_status_reset
        continue
      fi
      printf '%s\n' 'Tip: run relay kit edit <name> to create one later.'
      return 0
    fi
    header=$(relay_tui_format_keybind_header '' \
      'Enter:Start/Attach' \
      'Ctrl-E:Edit' \
      'Ctrl-D:Delete' \
      'Ctrl-S:Stop' \
      'Ctrl-N:New')
    selection=$(printf '%s\n' "$rows" | fzf \
      --delimiter '\t' \
      --with-nth=2,3 \
      --prompt 'Kits > ' \
      --preview "${RELAY_TUI_BIN_DIR:-.}/relay-tui kits-preview {2}" \
      --preview-window=down,60% \
      --header "$header" \
      --expect=enter,ctrl-e,ctrl-s,ctrl-n,ctrl-d)
    status=$?
    if [ $status -ne 0 ]; then
      if relay_tui_fzf_status_is_cancel "$status"; then
        return 0
      fi
      return "$status"
    fi
    key=$(printf '%s\n' "$selection" | sed -n '1p')
    choice=$(printf '%s\n' "$selection" | sed -n '2p')
    if [ -z "$choice" ]; then
      return 1
    fi
    kit=$(printf '%s\n' "$choice" | cut -f2 | sed 's/[[:space:]]*$//')
    if [ -z "$kit" ]; then
      continue
    fi
    case "$key" in
      ctrl-e)
        relay_tui_run kit edit "$kit"
        relay_tui_kits_status_reset
        relay_tui_cache_remove 'kits-listing'
        continue
        ;;
      ctrl-d)
        if ! relay_tui_kits_delete "$kit"; then
          continue
        fi
        continue
        ;;
      ctrl-s)
        relay_tui_run kit stop "$kit"
        relay_tui_kits_status_reset
        continue
        ;;
      ctrl-n)
        relay_tui_kits_create
        relay_tui_kits_status_reset
        continue
        ;;
      ''|enter)
        if ! relay_kit_smart_action "$kit"; then
          printf '%s\n' 'relay-tui: kit action failed.' >&2
        fi
        relay_tui_kits_status_reset
        continue
        ;;
      *)
        if ! relay_kit_smart_action "$kit"; then
          printf '%s\n' 'relay-tui: kit action failed.' >&2
        fi
        relay_tui_kits_status_reset
        continue
        ;;
    esac
  done
}

relay_tui_personas_dir() {
  if [ -n "${RELAY_PERSONAS_DIR:-}" ]; then
    printf '%s\n' "${RELAY_PERSONAS_DIR%/}"
    return
  fi
  printf '%s\n' "$HOME/.local/share/relay/personas"
}

relay_tui_personas_active_tokens() {
  combined=""
  for value in "${RELAY_TUI_ACTIVE_PERSONAS:-}" "${RELAY_ACTIVE_PERSONAS:-}" "${RELAY_ACTIVE_PERSONA:-}" "${RELAY_PERSONA:-}"; do
    [ -n "$value" ] || continue
    normalized=$(printf '%s' "$value" | tr ',:' ' ')
    for token in $normalized; do
      [ -n "$token" ] || continue
      if [ -z "$combined" ]; then
        combined="$token"
      else
        combined="$combined $token"
      fi
    done
  done
  printf '%s\n' "$combined"
}

relay_tui_persona_is_active() {
  name="$1"
  active_list=$(relay_tui_personas_active_tokens)
  for item in $active_list; do
    if [ "$item" = "$name" ]; then
      return 0
    fi
  done
  return 1
}

relay_tui_persona_description() {
  dir="$1"
  file="$dir/persona.toml"
  if [ -f "$file" ]; then
    desc=$(sed -n 's/^[[:space:]]*#[[:space:]]*\(.*\)$/\1/p' "$file" | sed -n '1p')
    if [ -n "$desc" ]; then
      printf '%s\n' "$desc"
      return 0
    fi
  fi
  printf 'Persona directory: %s\n' "$dir"
}

relay_tui_personas_cache_valid() {
  cache_file="$1"
  dir=$(relay_tui_personas_dir)
  [ -s "$cache_file" ] || return 1
  [ -d "$dir" ] || return 1
  if find "$dir" -mindepth 1 -maxdepth 1 -type d -newer "$cache_file" 2>/dev/null | head -n 1 | read -r _; then
    return 1
  fi
  if find "$dir" -name 'persona.toml' -type f -newer "$cache_file" 2>/dev/null | head -n 1 | read -r _; then
    return 1
  fi
  tab_char=$(printf '\t')
  while IFS=$tab_char read -r name _; do
    [ -n "$name" ] || continue
    if [ ! -d "$dir/$name" ]; then
      return 1
    fi
  done < "$cache_file"
  return 0
}

relay_tui_personas_listing_generate() {
  dir=$(relay_tui_personas_dir)
  if [ ! -d "$dir" ]; then
    return 1
  fi
  set -- "$dir"/*
  if [ "$1" = "$dir/*" ]; then
    return 1
  fi
  tab_char=$(printf '\t')
  for persona_path in "$@"; do
    [ -d "$persona_path" ] || continue
    name=${persona_path##*/}
    desc=$(relay_tui_persona_description "$persona_path")
    desc=$(printf '%s\n' "$desc" | tr '\t' ' ')
    printf '%s\t%s\n' "$name" "$desc"
  done | sort -t "$tab_char" -k1,1
}

relay_tui_personas_listing() {
  if ! relay_tui_cache_enabled; then
    relay_tui_personas_listing_generate
    return $?
  fi
  cache_path=$(relay_tui_cache_path 'personas-listing')
  if [ -z "$cache_path" ]; then
    relay_tui_personas_listing_generate
    return $?
  fi
  if [ -f "$cache_path" ] && relay_tui_personas_cache_valid "$cache_path"; then
    cat "$cache_path"
    return 0
  fi
  listing=$(relay_tui_personas_listing_generate 2>/dev/null)
  status=$?
  [ $status -eq 0 ] || return $status
  if [ -z "$listing" ]; then
    rm -f "$cache_path"
    return 1
  fi
  printf '%s\n' "$listing"
  printf '%s\n' "$listing" > "$cache_path" 2>/dev/null || true
  return 0
}

relay_tui_personas_rows() {
  listing=$(relay_tui_personas_listing 2>/dev/null)
  [ -n "$listing" ] || return 1
  active_list=$(relay_tui_personas_active_tokens)
  tab_char=$(printf '\t')
  printf '%s\n' "$listing" | while IFS=$tab_char read -r name desc; do
    [ -n "$name" ] || continue
    symbol='-'
    for active in $active_list; do
      if [ "$active" = "$name" ]; then
        symbol='*'
        break
      fi
    done
    printf '%s\t%-24s\t%s\n' "$symbol" "$name" "$desc"
  done
}

relay_tui_personas_create() {
  printf 'Enter new persona name: ' >&2
  if ! IFS= read -r name; then
    return 1
  fi
  name=$(printf '%s\n' "$name" | sed 's/^[[:space:]]*//;s/[[:space:]]*$//')
  if [ -z "$name" ]; then
    printf '%s\n' 'No persona name provided.' >&2
    return 1
  fi
  relay_tui_run persona edit "$name"
  relay_tui_cache_remove 'personas-listing'
}

relay_tui_persona_assign() {
  persona="$1"
  relay_tui_require_tmux || return 1
  printf 'Kit name: ' >&2
  if ! IFS= read -r kit; then
    return 1
  fi
  kit=$(printf '%s\n' "$kit" | sed 's/^[[:space:]]*//;s/[[:space:]]*$//')
  [ -n "$kit" ] || {
    printf '%s\n' 'No kit provided.' >&2
    return 1
  }
  printf 'Target window:pane (e.g. main:1): ' >&2
  if ! IFS= read -r target; then
    return 1
  fi
  target=$(printf '%s\n' "$target" | sed 's/^[[:space:]]*//;s/[[:space:]]*$//')
  [ -n "$target" ] || {
    printf '%s\n' 'No target provided.' >&2
    return 1
  }
  printf 'Mode (append/replace) [append]: ' >&2
  if ! IFS= read -r mode; then
    mode=""
  fi
  mode=$(printf '%s\n' "$mode" | tr '[:upper:]' '[:lower:]' | sed 's/^[[:space:]]*//;s/[[:space:]]*$//')
  case "$mode" in
    replace)
      relay_tui_run kit persona assign --replace "$kit" "$target" "$persona"
      ;;
    append|'' )
      relay_tui_run kit persona assign "$kit" "$target" "$persona"
      ;;
    *)
      printf '%s\n' 'Unknown mode; expected append or replace.' >&2
      return 1
      ;;
  esac
}

relay_tui_persona_exec() {
  persona="$1"
  printf 'Command to run (exec): ' >&2
  if ! IFS= read -r command; then
    return 1
  fi
  command=$(printf '%s\n' "$command" | sed 's/^[[:space:]]*//;s/[[:space:]]*$//')
  [ -n "$command" ] || {
    printf '%s\n' 'No command provided.' >&2
    return 1
  }
  relay_tui_run persona exec "$persona" -- sh -c "$command"
}

relay_tui_persona_use_print() {
  persona="$1"
  relay_tui_run persona use "$persona"
}

relay_tui_personas_delete() {
  persona="$1"
  if [ -z "$persona" ]; then
    printf '%s\n' 'relay-tui: no persona selected for deletion.' >&2
    return 1
  fi
  dir=$(relay_tui_personas_dir)/$persona
  if [ ! -d "$dir" ]; then
    printf 'relay-tui: persona directory missing: %s\n' "$dir" >&2
    return 1
  fi
  prompt="Delete persona \"$persona\" and its files?"
  if relay_tui_persona_is_active "$persona"; then
    prompt="Persona \"$persona\" is active. Delete anyway?"
  fi
  if ! relay_tui_popup_confirm "$prompt" "$dir"; then
    printf '%s\n' 'relay-tui: persona deletion cancelled.' >&2
    return 1
  fi
  if ! rm -rf -- "$dir"; then
    printf 'relay-tui: failed to delete persona "%s".\n' "$persona" >&2
    return 1
  fi
  relay_tui_cache_remove 'personas-listing'
  printf 'relay-tui: deleted persona "%s".\n' "$persona" >&2
  return 0
}

relay_tui_personas_preview() {
  persona="$1"
  if [ -z "$persona" ]; then
    printf '%s\n' 'No persona selected.'
    return 0
  fi
  dir=$(relay_tui_personas_dir)/$persona
  file="$dir/persona.toml"
  active='no'
  if relay_tui_persona_is_active "$persona"; then
    active='yes'
  fi
  printf 'Persona: %s\n' "$persona"
  printf 'Active: %s\n' "$active"
  printf 'Directory: %s\n' "$dir"
  if [ ! -f "$file" ]; then
    printf '\npersona.toml not found. Use relay persona edit %s to create it.\n' "$persona"
    return 0
  fi
  if ! command -v python3 >/dev/null 2>&1; then
    printf '\npython3 not available; showing raw file.\n'
    sed 's/^/  /' "$file"
    return 0
  fi
  show_secrets=0
  if [ "${RELAY_TUI_SHOW_SECRETS:-}" = "1" ]; then
    show_secrets=1
  fi
  lib_dir=$(relay_tui_lib_dir 2>/dev/null)
  if [ -z "$lib_dir" ]; then
    printf '\nTOML preview unavailable; could not resolve Relay lib directory.\n'
    sed 's/^/  /' "$file"
    return 0
  fi
  PYTHONPATH="$lib_dir${PYTHONPATH:+:$PYTHONPATH}" python3 - "$file" "$show_secrets" <<'PY'
import re
import sys

from relay_toml import TomlMissingError, load_path

path = sys.argv[1]
show_secrets = sys.argv[2] == '1'

try:
    data = load_path(path) or {}
except TomlMissingError as exc:
    print(exc, file=sys.stderr)
    sys.exit(2)

env = dict((data.get('env') or {}))
path_cfg = data.get('path') or {}
prepend = [str(x) for x in (path_cfg.get('prepend') or [])]
append = [str(x) for x in (path_cfg.get('append') or [])]

sensitive_pattern = re.compile(r'(secret|token|pass|key)', re.I)
has_sensitive = any(
    sensitive_pattern.search(str(key)) or sensitive_pattern.search(str(value))
    for key, value in env.items()
)

def render_value(key, value):
    if show_secrets or not has_sensitive:
        return str(value)
    if sensitive_pattern.search(str(key)) or sensitive_pattern.search(str(value)):
        return '*** hidden ***'
    return str(value)

print('\nEnvironment:')
if env:
    print('  {0:<20} {1}'.format('Key', 'Value'))
    print('  {0:<20} {1}'.format('-' * 20, '-' * 32))
    for key in sorted(env):
        print('  {0:<20} {1}'.format(key, render_value(key, env[key])))
else:
    print('  (none)')

print('\nPATH adjustments:')
if prepend:
    print('  prepend:')
    for item in prepend:
        print(f'    - {item}')
if append:
    print('  append:')
    for item in append:
        print(f'    - {item}')
if not prepend and not append:
    print('  (none)')

metadata = {k: v for k, v in data.items() if k not in {'env', 'path'}}
if metadata:
    print('\nAdditional sections:')
    for key in sorted(metadata):
        value = metadata[key]
        if isinstance(value, dict):
            print(f'  [{key}]')
            if value:
                for sub_key in sorted(value):
                    print('    {0:<18} {1}'.format(sub_key, value[sub_key]))
            else:
                print('    (empty)')
        else:
            print('  {0:<20} {1}'.format(key, value))
else:
    print('\nAdditional sections: (none)')

if has_sensitive and not show_secrets:
    print('\n(Secrets hidden. Set RELAY_TUI_SHOW_SECRETS=1 to reveal.)')
PY
}

relay_tui_personas() {
  relay_tui_setup_colors
  while :; do
    rows=$(relay_tui_personas_rows 2>/dev/null)
    if [ -z "$rows" ]; then
      printf '%s\n' 'No personas found.'
      if relay_tui_popup_confirm 'Create a new persona now?' 'This opens "relay persona edit".'; then
        relay_tui_personas_create
        continue
      fi
      printf '%s\n' 'Tip: run relay persona new to create one later.'
      return 0
    fi
    header=$(relay_tui_format_keybind_header '' \
      'Ctrl-E:Edit' \
      'Ctrl-D:Delete' \
      'Ctrl-A:Assign' \
      'Ctrl-X:Exec' \
      'Ctrl-N:New' \
      'Ctrl-U:Use')
    selection=$(printf '%s\n' "$rows" | fzf \
      --delimiter '\t' \
      --with-nth=2,3 \
      --prompt 'Personas > ' \
      --preview "${RELAY_TUI_BIN_DIR:-.}/relay-tui personas-preview {2}" \
      --preview-window=down,60% \
      --header "$header" \
      --expect=enter,ctrl-e,ctrl-a,ctrl-x,ctrl-n,ctrl-u,ctrl-d)
    status=$?
    if [ $status -ne 0 ]; then
      if relay_tui_fzf_status_is_cancel "$status"; then
        return 0
      fi
      return "$status"
    fi
    key=$(printf '%s\n' "$selection" | sed -n '1p')
    choice=$(printf '%s\n' "$selection" | sed -n '2p')
    if [ -z "$choice" ]; then
      return 1
    fi
    persona=$(printf '%s\n' "$choice" | cut -f2 | sed 's/[[:space:]]*$//')
    if [ -z "$persona" ]; then
      continue
    fi
    case "$key" in
      ctrl-e)
        relay_tui_run persona edit "$persona"
        relay_tui_cache_remove 'personas-listing'
        continue
        ;;
      ctrl-a)
        relay_tui_persona_assign "$persona"
        continue
        ;;
      ctrl-x)
        relay_tui_persona_exec "$persona"
        continue
        ;;
      ctrl-n)
        relay_tui_personas_create
        continue
        ;;
      ctrl-u)
        relay_tui_persona_use_print "$persona"
        continue
        ;;
      ctrl-d)
        if ! relay_tui_personas_delete "$persona"; then
          continue
        fi
        continue
        ;;
      ''|enter)
        continue
        ;;
      *)
        continue
        ;;
    esac
  done
}
