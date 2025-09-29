# Contributor Reference

Repository layout:
- `bin/relay` — main dispatcher and TUI entrypoint (`relay tui` launches directly).
- `bin/relay-kit` — kit lifecycle commands (`list`, `start`, `edit`, persona helpers).
- `bin/relay-persona` — persona creation, inspection, and export plumbing.
- `bin/relay-events` — FIFO init/tail/emit/history/stats interfaces.
- `bin/relay-doctor` — system and dependency diagnostics.
- `lib/` — shared helper modules (Python utilities backing the shell entrypoints).
- `scripts/` — contributor utilities (not installed).
- `tests/` — non-regression suite; `tests/noreg.sh` exercises the read-only contract.

For walkthroughs and feature detail, start with:
- [Getting started](getting-started.md)
- [Working with kits](kits.md)
- [Personas](personas.md)
- [Events](events.md)
- [Maintenance](maintenance.md)
