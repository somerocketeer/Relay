# Events Bus

Relay emits structured events to a FIFO under `~/.local/state/relay`. Use it to keep deployment and automation history observable.

## Initialise and tail
```sh
relay events init
relay events tail &            # watch in another pane, Ctrl+C to stop
```

## Emit custom events
```sh
relay events emit -t kit-start -p web
relay events emit -t deploy -p "prod" --data '{"status":"ok"}'
```

## Query history and stats
```sh
relay events history
relay events stats
```

Integrate the bus into your own tooling by reading from the FIFO or the rotating `events.log` fallback.

### Use case: Deployment activity log
- Emit a `deploy` event per release window.
- Pipe `relay events tail` into `jq` or `fzf` to filter by owner, status, or timestamp.

See also: [Maintenance & testing](maintenance.md)
