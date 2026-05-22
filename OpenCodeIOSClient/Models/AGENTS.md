# Models Notes

## Responsibility

`Models/` should define OpenCode domain/server data shapes and domain state transition semantics. These types describe the server truth the rest of the app consumes, and they should stay close to upstream OpenCode server payloads and generated web SDK types.

The intended canon is that OpenCode server/domain models live here, while app-only preference, persistence, game, commerce, or feature-local state models live with their owning feature/store when practical. Some local app-only models may still exist here from earlier iterations; do not treat that as the desired pattern for new code.

If a type is not upstream-derived, prefer moving it toward the owning feature area during cleanup rather than adding more unrelated local models here.

## OpenCode Parity

Treat upstream OpenCode web UI and generated SDK types as the default reference for model shape and event semantics. The upstream team has better visibility into server internals and future API changes, so avoid inventing iOS-specific payload interpretations unless the divergence is explicit and necessary.

When updating server-backed models, compare against upstream generated types, especially optional fields, default values, event names, and nested payload shape. Be tolerant where the server or upstream web client treats fields as optional/defaultable.

## Reducers And Sync Semantics

Reducers in this directory are domain logic, not view logic. `OpenCodeStateReducer`, `OpenCodeDirectorySyncState`, and `OpenCodeStreamReducer` encode how bootstrap data and typed live events become canonical app state.

Prefer extending reducers over duplicating event mutation rules in stores, coordinators, or views. Stores should hold state and expose mutations; reducers should define OpenCode event application semantics.

For streaming, preserve upstream behavior unless proven otherwise by live server testing:

- `message.part.updated` establishes canonical part identity and type.
- iOS intentionally preserves live `message.part.updated` arrival order for parts. This is a tested native-client divergence from upstream's id-ordered insertion: on-device streaming can stop visibly updating when live parts are sorted by id because the active text part moves under the UI.
- `message.part.delta` appends to an existing part and should not create a placeholder text part before the full part is known.
- Reasoning vs answer text comes from the server-provided part `type`, not parsing streamed text.
- The current iOS guard that avoids wiping accumulated text with a later empty `part.updated` is intentional unless upstream/server behavior proves it can be removed.

## Typed Events

`OpenCodeTypedEvent` should model known OpenCode event names explicitly. If a live SSE payload is visible but UI state does not update, suspect typed-event decoding before view logic.

When adding or changing typed events, update the event envelope properties, typed event reconstruction, and reducer handling together. Missing event-specific fields in `OpenCodeEventProperties` are a common cause of silently dropped live behavior.

## Do / Avoid

Do keep server-backed model names, fields, and optionality aligned with upstream payloads where practical.

Do keep request/response DTOs simple and `Codable`/`Sendable` when appropriate.

Do document intentional local-only assumptions through naming or nearby code comments when a model is not upstream-derived.

Avoid adding SwiftUI presentation state, `@Published`, networking, or API sequencing here.

Avoid making strict decoding assumptions for payloads that upstream treats as optional or defaultable.

Avoid putting local app-only behavior into OpenCode server models unless it is clearly separated from decoded server truth.
