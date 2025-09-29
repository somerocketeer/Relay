# Troubleshooting

- **fzf colors too loud**: run `relay tui --plain` or clear colour flags from `FZF_DEFAULT_OPTS`.
- **Missing tmux**: kits still `cd` into the working directory and run pre/post hooks, but interactive panes require tmux. Install tmux before launching kits.
- **Importer warnings**: review `import.log` under the generated kit directory; warnings flag inline credentials, ephemeral pod IDs, or hard-coded IPs that may need manual fixes.
- **Hermetic tests failing**: re-run with `RELAY_DEBUG=1` and capture the `/tmp` artefacts so you can inspect generated TOML and warning logs.

Need more? Open an issue with the command you ran, full stderr/stdout, and any kit/persona snippets involved.
