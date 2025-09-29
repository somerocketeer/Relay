# Installation and Packaging Guide

Relay ships as portable POSIX `sh` scripts. The installer copies the entrypoints into your preferred prefix and makes sure the PATH hook is in place; no additional tooling is bundled.

## TL;DR
- Local clone + install (recommended during development):
  ```sh
  ./install.sh                # installs into ~/.local/bin by default
  PREFIX=/usr/local ./install.sh
  ```
- Manual copy:
  ```sh
  mkdir -p "$HOME/.local/bin"
  install -m 0755 bin/relay bin/relay-tui bin/relay-kit \
    bin/relay-persona bin/relay-events bin/relay-doctor "$HOME/.local/bin/"
  ```
- After installation make sure `$PREFIX/bin` is on your `PATH`.

## Installer behaviour
- Copies the Relay executables into `$PREFIX/bin` (default: `~/.local/bin`).
- Updates a shell profile (`.zshrc`, `.bashrc`, or Fish config) when possible so the prefix is added to `PATH` on the next shell startup.
- Exits with a short summary so you can verify the location.

## Verification
```sh
relay doctor          # confirms required tools such as fzf and tmux
relay kit list        # should print your available kits (or nothing yet)
relay tui             # launches the fzf-powered menu
```

## Packaging options
- **Tarball releases** – Publish archives per OS/arch that contain the `bin/` scripts. Users can unpack into any prefix and run the verification steps above.
- **System packages** – Wrap the scripts in distro packages (deb/rpm/apk). Installation simply places the files in `/usr/bin` (or an equivalent) and marks the commands executable.
- **Container image** – Embed Relay in a minimal base image (e.g., `ghcr.io/<org>/relay:<tag>`) so CI or workstations can run Relay without touching the host filesystem beyond the mounted data/state paths.
- **npm/pnpm distribution** – If Node tooling is desirable, publish a package whose `postinstall` step copies the scripts into the package bin directory. Make sure the wrapper respects POSIX `sh`.

## Uninstall
Remove the installed executables from your chosen prefix:
```sh
BIN_DIR="${PREFIX:-$HOME/.local}/bin"
rm -f "$BIN_DIR/relay" "$BIN_DIR/relay-tui" "$BIN_DIR/relay-kit" \
      "$BIN_DIR/relay-persona" "$BIN_DIR/relay-events" "$BIN_DIR/relay-doctor"
```
If you added a `PATH` hook manually, delete it from the relevant shell profile.

## Data locations
Relay keeps its footprint inside user-scoped XDG directories:
- Data: `~/.local/share/relay/{kits,personas}`
- State: `~/.local/state/relay/{events,events.log}`
