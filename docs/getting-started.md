# Getting Started with Relay

Relay keeps complex Linux shell workflows reproducible without touching system-managed paths. It bundles a fast launcher, reusable kit definitions, persona overlays, and an events bus so you can rebuild an environment with a single command.

## TL;DR
- `relay` launches an fzf-powered TUI (falls back to a status board when fzf is missing).
- Kits live under `~/.local/share/relay/kits/` and spin up tmux sessions.
- Personas live under `~/.local/share/relay/personas/` and layer environment variables and PATH tweaks.
- Relay writes **only** to `~/.local/share/relay` (data) and `~/.local/state/relay` (state/FIFO).

## 1. Prepare your machine

### Supported platform
- Linux (tested on Fedora, Ubuntu, Arch, and Nix shells). WSL works if tmux is available.

### Dependencies
- **fzf** (enables the interactive TUI; otherwise Relay prints a text status board).
- **tmux** (required)
- **python3** with `tomllib` (built in since Python 3.11, otherwise install `tomli`).

Quick check:
```sh
command -v fzf tmux python3
```
Install anything missing via your distro before continuing.

## 2. Install Relay locally

From the repository root:
```sh
./install.sh
```
This installs all entrypoints into `~/.local/bin`. Ensure that directory is on your `PATH`:
```sh
echo "$PATH" | tr ':' '\n' | grep "\.local/bin"
```
Prefer a manual copy? Relay ships shell entrypoints plus helper libraries:
```sh
PREFIX=${PREFIX:-$HOME/.local}
mkdir -p "$PREFIX/bin" "$PREFIX/lib"
install -m 0755 bin/relay bin/relay-tui bin/relay-kit \
  bin/relay-persona bin/relay-events bin/relay-doctor "$PREFIX/bin/"
cp -R lib/* "$PREFIX/lib/"
```

### Smoke test the dispatcher
```sh
relay help
relay doctor
```
`relay doctor` verifies core tools (fzf, tmux, python) and reports anything missing before your kits fail mid-run. If those checks pass, continue to Step 3 to launch the interface.

## 3. First launch: explore the TUI

```sh
relay              # opens the main menu
relay status       # prints the status board without fzf
```
If `fzf` is missing, `relay` automatically falls back to the read-only status board so you can still inspect kits, personas, and recent events.
You should see:
- A breadcrumb header that tracks where you are in the UI.
- A Kits menu with shortcuts to create or edit definitions.
- Personas and Events menus with contextual actions.
- A system pane showing doctor status and quick tips.

Helpful keys inside the menu:
- **Type to search** – the list is live-filtered; hit `Esc` to clear.
- **`Ctrl-J`** – open the quick-jump palette (Kits / Personas / Events / Doctor / Status) without backing out of the current view.
- **`Ctrl-S`** – stop a running kit from the Kits list.
- **`Ctrl-D`** – delete the highlighted kit or persona. Relay now shows an inline confirmation popup inside the TUI so you’re not thrown into a separate prompt.

## 4. Create your first kit

Kits are versioned TOML blueprints for sessions. They live under `~/.local/share/relay/kits/<name>/`.

### Scaffold
```sh
mkdir -p ~/.local/share/relay/kits/web
${EDITOR:-nvim} ~/.local/share/relay/kits/web/kit.toml
```
Copy in the starter kit below (adapt paths to your project):

```toml
version = 1
session = "web"
dir = "~/Code/web"
attach = true
personas = ["work"]
backend = "tmux"
requires = ["tmux"]

pre_check = [
  { run = "git status --short", timeout = 5 },
]

pre = ["echo Pre-flight checks complete"]
post = ["echo Shutting down session"]

[[windows]]
name = "dev"
dir = "~/Code/web"
layout = "tiled"
panes = [
  "nvim",                               # editor pane
  { split = "h", run = "npm run dev" },
  { split = "v", run = "rg -n TODO" }
]
```

### Dry run and launch
```sh
relay kit list
relay kit start web --dry-run   # inspect the plan
relay kit start web             # tmux session with panes and hooks
```
Inside tmux, press `prefix + d` to detach. Reattach with `tmux attach -t web`.

## Where Relay stores data

Relay keeps its footprint under user-scoped XDG directories:
- Kits and personas live in `~/.local/share/relay`
- Events and transient state live in `~/.local/state/relay`

To undo changes without removing the binaries, run the factory reset command described in [Maintenance & testing](maintenance.md).

Next steps:
- [Master kit workflows](kits.md)
- [Layer personas](personas.md)
- [Watch events](events.md)
