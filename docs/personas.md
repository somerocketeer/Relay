# Personas

Personas encapsulate environment overrides so multiple kits can share the same identity settings.

## Create a persona
```sh
mkdir -p ~/.local/share/relay/personas/work
${EDITOR:-nvim} ~/.local/share/relay/personas/work/persona.toml
```
Populate it with:
```toml
version = 1
[env]
PS1_TAG = "[WORK]"
GIT_AUTHOR_NAME = "Alice Ops"
GIT_AUTHOR_EMAIL = "alice@example.com"

[path]
prepend = ["~/.local/bin"]
```

## Use personas
```sh
relay persona list
relay persona use work -p          # prints export lines
relay persona exec work -- env | grep PS1_TAG
```
To keep a shell overlay active, eval the exports:
```sh
eval "$(relay persona use work -p)"
```

Link personas to kits with `personas = ["work"]` in `kit.toml`. At launch, Relay layers each persona before creating panes so the environment is consistent everywhere. Add temporary overlays per run with `--persona`:
```sh
relay kit start web --persona staging
```

Pane-level persona overlays live in `pane-personas.json` inside each kit directory. Apply or clear them on demand:
```sh
relay kit persona assign web dev:1 staging
relay kit persona clear web dev:1
```

When browsing personas in the TUI:
- **Type to filter** the list.
- Use **Ctrl-J** to bounce between menus without closing the current view.
- **Ctrl-E** edits the highlighted persona, **Ctrl-A** assigns it to a kit pane, **Ctrl-U** prints its exports, and **Ctrl-D** deletes it after confirming via an inline popup.
- The preview pane renders persona environments in a padded table so long keys stay aligned.

## Use case: Safe pair-programming context
- Create `personas/pair` with shared Git authorship and feature flags.
- Launch your kit with `--persona pair` for one-off sessions without touching the base config.

Next steps: [Working with kits](kits.md)
