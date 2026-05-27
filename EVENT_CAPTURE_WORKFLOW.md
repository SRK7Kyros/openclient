# OpenCode Event Capture Workflow

Use this workflow when live OpenCode SSE behavior is unclear and app-side guesses risk breaking streaming.

## Tool

The repo includes a standalone Swift diagnostics script:

```bash
swift scripts/opencode_event_capture.swift
```

It does two things:

- subscribes to the configured OpenCode `/global/event` SSE stream
- runs a tiny local HTTP status server for checking capture progress

Default output is `tmp/opencode-event-capture.log`. `tmp/` is git-ignored.

## Configuration

Prefer environment variables so credentials do not enter shell history:

```bash
OPENCODE_BASE_URL="http://127.0.0.1:4096" \
OPENCODE_USERNAME="opencode" \
OPENCODE_PASSWORD="..." \
swift scripts/opencode_event_capture.swift
```

Useful options:

```bash
swift scripts/opencode_event_capture.swift \
  --base-url "http://127.0.0.1:4096" \
  --event-path "/global/event" \
  --log "tmp/opencode-event-capture.log" \
  --listen "127.0.0.1:9797"
```

HTTP endpoints:

- `GET http://127.0.0.1:9797/health`
- `GET http://127.0.0.1:9797/log`
- `GET http://127.0.0.1:9797/log?tail=200`

## Recommended Debugging Pattern

1. Start the capture script before reproducing the issue.
2. Use the iOS app normally and trigger the live behavior under investigation.
3. Stop the capture script with `Ctrl-C` after reproduction.
4. Inspect `tmp/opencode-event-capture.log` before changing app event decoding.
5. Look for both projected bus events and storage sync events:
   `session.updated`, `message.updated`, `message.part.updated`, `message.part.delta`, and `payload.type: sync`.

## Rules For Future Agents

- Do not route raw `sync` message events into the visible chat reducer without proving they match the projected streaming event shape.
- Preserve existing streaming semantics: `message.part.updated` establishes typed part identity, and `message.part.delta` only appends to an existing part.
- When title updates or other session list events are missing, capture raw SSE first instead of broadening typed decoding across all event families.
- Do not commit capture logs or credentials.
