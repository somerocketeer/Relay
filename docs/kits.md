# Working with Kits

Relay kits are versioned TOML blueprints that describe how to launch a tmux session: windows, panes, commands, hooks, personas, and validation.

## Essentials

Kits live under `~/.local/share/relay/kits/<name>/` and can include:
- `session` — tmux session name to create.
- `dir` — default working directory.
- `personas` — persona overlays applied before panes start.
- Hooks such as `pre_check`, `pre`, and `post`.
- `[[windows]]` blocks describing layout and panes.

Dry run any kit to inspect what will happen (from the CLI):
```sh
relay kit start <name> --dry-run
```

Inside the Kits menu (`relay` → Kits), the most common shortcuts are shown in the header:

- **Enter** – start or attach to the selected kit.
- **Ctrl-E** – open the kit’s `kit.toml` in your editor.
- **Ctrl-S** – stop a running kit.
- **Ctrl-D** – delete a kit. Relay now opens a confirmation popup in place so you don’t lose context.
- **Ctrl-J** – from anywhere in the TUI, jump directly to Kits, Personas, Events, Doctor, or Status.

## Importing an existing tmux session

Relay can snapshot a native tmux session and turn it into a kit you can version:

```sh
relay kit import --list                   # show unmanaged sessions
relay kit import prod-debug --dry-run     # preview kit.toml without writing
relay kit import prod-debug --output monitoring --interactive --edit
```

The import workflow generates `~/.local/share/relay/kits/<name>/kit.toml` plus an
`import.log` with any warnings (inline credentials, pod-specific commands, etc.).
Use `--interactive` to accept suggested fixes (for example converting
`kubectl logs -f pod/...` into a deployment selector) and `--edit` for a quick
handoff to your `$EDITOR`.

### Validating the importer
- Run `tests/kit_import.sh` to confirm the importer captures a throwaway tmux
  session. The script spawns its own session; make sure `tmux` can create
  sockets on the host (if you see `error connecting ...`, start a local tmux
  server or loosen socket permissions).
- The test isolates its tmux server, so base-index or pane-base-index
  customisations should not matter. If you still see targeting errors, re-run
  with `RELAY_DEBUG=1 ./tests/kit_import.sh` and attach the generated kit
  directory under `/tmp` for review.
- Preserve the verbose log output and the generated kit directory under `/tmp`.
  Fixes usually involve updating `lib/relay_tmux_import.py` (parsing) or
  `bin/relay-kit` (argument handling). Keep the reproduction commands and the
  offending `kit.toml` snippet in your report so reviewers can replay it quickly.

## Example: On-call readiness kit
- Create additional panes that tail logs or run `kubectl`.
- Add `pre_check` commands for cluster availability.
- Use `post_check` and `mode = "warn"` to surface drift without blocking teardown.

Further reading:
- [Personas](personas.md)
- [Events](events.md)
- [Maintenance & testing](maintenance.md)
