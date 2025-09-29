# Maintenance & Testing

Keep Relay healthy with a quick set of checks:

- `relay doctor` surfaces missing dependencies and environment drift.
- `./tests/noreg.sh` snapshots the protected directories to prove Relay stayed read-only.
- After editing shell scripts, run `shellcheck bin/*` to match CI.

Factory reset (removes only Relay-managed data):
```sh
rm -rf ~/.local/share/relay ~/.local/state/relay
```

Importer specific check:
- Run `tests/kit_import.sh` after changing import logic. It spawns an isolated tmux session, so base-index customisations do not interfere. If the test fails, re-run with
  `RELAY_DEBUG=1 ./tests/kit_import.sh` and attach the generated kit directory under `/tmp`.

Related docs:
- [Working with kits](kits.md)
- [Events](events.md)
