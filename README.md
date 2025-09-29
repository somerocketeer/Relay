```
 ███████████   ██████████ █████         █████████   █████ █████
░░███░░░░░███ ░░███░░░░░█░░███         ███░░░░░███ ░░███ ░░███ 
 ░███    ░███  ░███  █ ░  ░███        ░███    ░███  ░░███ ███  
 ░██████████   ░██████    ░███        ░███████████   ░░█████   
 ░███░░░░░███  ░███░░█    ░███        ░███░░░░░███    ░░███    
 ░███    ░███  ░███ ░   █ ░███      █ ░███    ░███     ░███    
 █████   █████ ██████████ ███████████ █████   █████    █████   
░░░░░   ░░░░░ ░░░░░░░░░░ ░░░░░░░░░░░ ░░░░░   ░░░░░    ░░░░░    
```

Relay is a portable tmux workflow layer with shell entrypoints and lightweight Python helpers that make complex terminal layouts reproducible, shareable, and safe for teams that live in the command line.

## Prerequisites

- Linux with `tmux` available
- `fzf` (optional, enables the interactive menu; falls back to a status board if missing)
- `python3` with `tomllib` support (built in since 3.11)

## Quick Start

Using `curl`:

```sh
curl -fsSL https://raw.githubusercontent.com/somerocketeer/relay/main/install.sh | sh
```

Using `wget`:

```sh
wget -qO- https://raw.githubusercontent.com/somerocketeer/relay/main/install.sh | sh
```

The installer fetches the `bin/*` launchers from GitHub when they aren't present locally. You can pin to a specific branch or release and choose the downloader:

```sh
RELAY_REMOTE_BASE="https://raw.githubusercontent.com/somerocketeer/relay/v0.1.0" \
  curl -fsSL https://raw.githubusercontent.com/somerocketeer/relay/main/install.sh | sh

RELAY_REMOTE_BASE="https://raw.githubusercontent.com/somerocketeer/relay/v0.1.0" \
  wget -qO- https://raw.githubusercontent.com/somerocketeer/relay/main/install.sh | sh
```

After installing, open a new shell and run `relay help`, `relay doctor`, and `relay` to explore the menu (without `fzf` you’ll see a read-only status board instead). When you’re ready to build a workflow, follow [Getting started](docs/getting-started.md) to scaffold your first kit.

## What Relay Does

- Turns multi-pane sessions into versioned kits you can recreate anywhere.
- Applies personas to swap credentials, environment variables, and CLI defaults without manual exports.
- Captures events for auditing deployments, incident response playbooks, and day-to-day activity.
- Verifies prerequisites before running workflows so broken state stays out of production.

## Who Relay Is For

- Engineers who maintain repeatable tmux setups and want them under version control.
- Consultants and SREs who juggle multiple identities, clusters, or environments every day.
- Teams that need a lightweight automation layer with guardrails but prefer staying in the shell.

Relay installs its entrypoints into `$HOME/.local/bin` by default; if that directory isn’t on your `PATH`, rerun `./install.sh` with `PREFIX` set or follow the manual copy steps in [docs/INSTALL.md](docs/INSTALL.md).

## Documentation

- [Getting started](docs/getting-started.md)
- [Working with kits](docs/kits.md)
- [Managing personas](docs/personas.md)
- [Handling events](docs/events.md)
- [Troubleshooting and maintenance](docs/troubleshooting.md)
