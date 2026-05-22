# API Notes

## Responsibility

`API/` owns raw communication with the OpenCode server: endpoint wrappers, request construction, response decoding, bootstrap fetches, SSE parsing, and the shared global event stream owner.

Keep this directory focused on transport and server-boundary concerns. It should know how to talk to OpenCode, but it should not become the app's canonical state owner or view-model layer.

## Patterns

`OpenCodeAPIClient` is the typed endpoint surface. Prefer adding small endpoint methods that return decoded model values or complete without content. Keep request bodies private when they are only transport details.

`OpenCodeBootstrap` groups initial server reads into global and directory bootstrap phases. Preserve the upstream-aligned split between global bootstrap and directory bootstrap.

`OpenCodeEventStream` owns low-level SSE consumption and framing. `OpenCodeEventManager` owns the shared `/global/event` stream, typed event decoding, event drop diagnostics, reconnect behavior, and batching/coalescing before handing managed events to the rest of the app.

## State And Data Flow

The server is canonical, but API types should only fetch, decode, and stream that server truth. Stores, reducers, and coordinators decide how returned data changes app state.

Do not add `@Published` app state, selected sessions, UI flags, or cache ownership here. If an API call needs to be sequenced with state changes, put the sequencing in a coordinator and keep the endpoint wrapper here.

## OpenCode Parity

Prefer live server behavior and upstream OpenCode web semantics when endpoint details are ambiguous. The web UI team has the best visibility into server internals and future changes, so API consumption should mirror upstream bootstrap, event, and source-of-truth patterns unless there is an explicit native reason to diverge.

Canonical conventions include:

- Use one shared global event stream owner instead of per-view listeners.
- Treat missing event directory as `global`.
- Keep permissions and questions on `/permission` and `/question` endpoints, not old `/tui/control/*` paths.
- Preserve directory and workspace scoping through query items and `x-opencode-directory` headers where server behavior requires it.

Before adding a new interpretation of an endpoint response, event envelope, bootstrap phase, or stream lifecycle, check the upstream web implementation and model the Swift boundary after it where practical.

## Do / Avoid

Do keep endpoint methods explicit about path, method, query items, body, and directory/workspace scoping.

Do redact credentials and keep debug logging bounded.

Do surface dropped or undecodable SSE events through diagnostics rather than failing silently.

Avoid putting feature decisions, optimistic UI behavior, rollback handling, navigation, or store mutation in API files.

Avoid creating additional SSE owners unless the upstream/server model changes. Route new live behavior through the shared event manager and typed reducers when possible.
