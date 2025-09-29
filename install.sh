#!/usr/bin/env sh
set -e
check_prereqs() {
  missing=""
  for cmd in python3 tmux base64; do
    if ! command -v "$cmd" >/dev/null 2>&1; then
      missing="$missing $cmd"
    fi
  done
  if [ -n "$missing" ]; then
    printf 'Missing required tool(s):%s\n' "$missing" >&2
    printf 'Install the missing dependencies and re-run install.sh\n' >&2
    exit 1
  fi
}

check_prereqs


ensure_toml_support() {
  python3 - <<'PY' >/dev/null 2>&1 && return
import sys
try:
    import tomllib  # noqa: F401
except ModuleNotFoundError:
    try:
        import tomli  # noqa: F401
    except ModuleNotFoundError:
        sys.exit(1)
sys.exit(0)
PY
  printf '%s\n' 'Missing TOML parser: install tomli with "pip install --user tomli" or upgrade to Python 3.11+.' >&2
  exit 1
}

ensure_toml_support

PREFIX="${PREFIX:-$HOME/.local}"
mkdir -p "$PREFIX/bin"
RELAY_REMOTE_BASE="${RELAY_REMOTE_BASE:-https://raw.githubusercontent.com/somerocketeer/relay/main}"
SCRIPT_DIR=""
case "$0" in
  /*)
    SCRIPT_DIR=$(dirname "$0")
    ;;
  */*)
    SCRIPT_DIR=$(cd "$(dirname "$0")" && pwd)
    ;;
esac

fetch_remote() {
  name="$1"
  url="$RELAY_REMOTE_BASE/bin/$name"
  tmp=$(mktemp)
  if command -v curl >/dev/null 2>&1; then
    if curl -fsSL "$url" -o "$tmp"; then
      install -m 0755 "$tmp" "$PREFIX/bin/$name"
      rm -f "$tmp"
      echo "Installed bin/$name -> $PREFIX/bin/"
      return 0
    fi
  fi
  if command -v wget >/dev/null 2>&1; then
    if wget -qO "$tmp" "$url"; then
      install -m 0755 "$tmp" "$PREFIX/bin/$name"
      rm -f "$tmp"
      echo "Installed bin/$name -> $PREFIX/bin/"
      return 0
    fi
  fi
  rm -f "$tmp"
  return 1
}

fetch_remote_lib() {
  name="$1"
  url="$RELAY_REMOTE_BASE/lib/$name"
  tmp=$(mktemp)
  if command -v curl >/dev/null 2>&1; then
    if curl -fsSL "$url" -o "$tmp"; then
      install -m 0644 "$tmp" "$PREFIX/lib/$name"
      rm -f "$tmp"
      echo "Installed lib/$name -> $PREFIX/lib/"
      return 0
    fi
  fi
  if command -v wget >/dev/null 2>&1; then
    if wget -qO "$tmp" "$url"; then
      install -m 0644 "$tmp" "$PREFIX/lib/$name"
      rm -f "$tmp"
      echo "Installed lib/$name -> $PREFIX/lib/"
      return 0
    fi
  fi
  rm -f "$tmp"
  return 1
}

for name in relay relay-events relay-doctor relay-kit relay-persona relay-tui; do
  if [ -n "$SCRIPT_DIR" ] && [ -f "$SCRIPT_DIR/bin/$name" ]; then
    install -m 0755 "$SCRIPT_DIR/bin/$name" "$PREFIX/bin/"
    echo "Installed bin/$name -> $PREFIX/bin/"
    continue
  fi
  if [ -f "bin/$name" ]; then
    install -m 0755 "bin/$name" "$PREFIX/bin/"
    echo "Installed bin/$name -> $PREFIX/bin/"
    continue
  fi
  if ! fetch_remote "$name"; then
    echo "Failed to install $name; ensure bin/$name exists locally or set RELAY_REMOTE_BASE." >&2
    exit 1
  fi
done

mkdir -p "$PREFIX/lib"
copy_local_libs() {
  src_dir="$1"
  for src in "$src_dir"/*; do
    [ -e "$src" ] || continue
    base=$(basename "$src")
    case "$base" in
      __pycache__)
        continue
        ;;
    esac
    if [ -f "$src" ]; then
      install -m 0644 "$src" "$PREFIX/lib/$base"
      echo "Installed lib/$base -> $PREFIX/lib/"
    fi
  done
}

if [ -n "$SCRIPT_DIR" ] && [ -d "$SCRIPT_DIR/lib" ]; then
  copy_local_libs "$SCRIPT_DIR/lib"
elif [ -d "lib" ]; then
  copy_local_libs "lib"
else
  for name in relay_toml.py relay_kit_config.py relay_tmux_import.py relay_tui.sh; do
    if ! fetch_remote_lib "$name"; then
      echo "Failed to install lib/$name; ensure lib/$name exists locally or set RELAY_REMOTE_BASE." >&2
      exit 1
    fi
  done
fi
profile_hook() {
  dest="$1"
  hook="\n# Added by relay install\nif [ -d \"$PREFIX/bin\" ] && ! printf '%s\n' \"$PATH\" | tr ':' '\n' | grep -F -q \"$PREFIX/bin\"; then\n  export PATH=\"$PREFIX/bin:$PATH\"\nfi\n"
  if [ -f "$dest" ]; then
    if grep -F "Added by relay install" "$dest" >/dev/null 2>&1; then
      return
    fi
  else
    if ! touch "$dest" >/dev/null 2>&1; then
      echo "Warning: unable to create $dest; add $PREFIX/bin to PATH manually" >&2
      return
    fi
  fi
  if ! printf '%s\n' "$hook" >> "$dest"; then
    echo "Warning: unable to update $dest; add $PREFIX/bin to PATH manually" >&2
    return
  fi
  echo "Updated $dest to include $PREFIX/bin"
}
case "${SHELL:-}" in
  */zsh)
    profile_hook "$HOME/.zshrc"
    ;;
  */bash)
    profile_hook "$HOME/.bashrc"
    ;;
  */fish)
    dest="$HOME/.config/fish/config.fish"
    if [ -f "$dest" ]; then
      if grep -F "Added by relay install" "$dest" >/dev/null 2>&1; then
        :
      else
        if ! printf '\n# Added by relay install\nset -gx PATH %s $PATH\n' "$PREFIX/bin" >> "$dest"; then
          echo "Warning: unable to update $dest; add $PREFIX/bin to PATH manually" >&2
        else
          echo "Updated $dest to include $PREFIX/bin"
        fi
      fi
    else
      if ! mkdir -p "$(dirname "$dest")" >/dev/null 2>&1; then
        echo "Warning: unable to create $(dirname "$dest"); add $PREFIX/bin to PATH manually" >&2
      else
        # shellcheck disable=SC2016
        if ! printf '# Added by relay install\nset -gx PATH %s $PATH\n' "$PREFIX/bin" > "$dest"; then
          echo "Warning: unable to write $dest; add $PREFIX/bin to PATH manually" >&2
        else
          echo "Created $dest with PATH update"
        fi
      fi
    fi
    ;;
  *)
    echo "SHELL not recognised; add $PREFIX/bin to PATH manually"
    ;;
esac
echo "Done. Ensure $PREFIX/bin is on your PATH (update applied when possible)."
