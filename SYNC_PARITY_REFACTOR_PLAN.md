# Sync Parity Refactor Plan

## Goal

Make iOS OpenCode data consumption match upstream web UI semantics for bootstrap, SSE, typed events, reducers, source-of-truth boundaries, and fallback refresh behavior.

The upstream web UI is the default reference because its maintainers have better visibility into server behavior and future changes.

## Current Reality

- `OpenCodeEventManager` owns one global stream, which matches the desired direction.
- `OpenCodeTypedEvent`, `OpenCodeStateReducer`, and `OpenCodeDirectorySyncState` exist but do not own every state transition.
- `AppViewModel+Events` still owns event stream lifecycle, buffering, reducer application, debug logging, fallback reload scheduling, widget updates, and Live Activity cache updates.
- Fallback refreshes remain in `scheduleReload`, post-action `reloadSessions`, and global-event refresh paths.
- Some bootstrap/session/todo/permission/question hydration still happens directly in `AppViewModel`.
- Intentional iOS divergence: live message parts preserve arrival order rather than sorting by part id. This has been validated on-device; sorting parts by id can prevent active streaming text from rendering until completion or abandonment.

## Upstream References

Inspect these before changing semantics:

- `~/opencode/packages/app/src/context/global-sdk.tsx`
- `~/opencode/packages/app/src/context/global-sync.tsx`
- `~/opencode/packages/app/src/context/global-sync/bootstrap.ts`
- `~/opencode/packages/app/src/context/global-sync/event-reducer.ts`
- `~/opencode/packages/app/src/context/sync.tsx`
- `~/opencode/packages/sdk/js/src/v2/gen/types.gen.ts`

## Target Architecture

- One shared `/global/event` stream owner.
- Events decoded into typed Swift events matching upstream generated SDK types.
- Global events routed to global/project stores.
- Directory events routed by `directory`, with missing directory treated as `global`.
- Bootstrap split into global and directory phases.
- Session-local state, including todos/messages/permissions/questions, reduced into directory/session stores.
- Views consume store/facade snapshots and never apply raw events.

## Characterization Tests First

- Decode global event envelopes with `payload` and flat `type/properties` forms.
- Decode `question.asked` with omitted `multiple` and `custom` defaults.
- Decode `permission.asked` with actual server shape including `patterns`, `always`, `metadata`, `tool.messageID`, and `tool.callID`.
- Verify dropped invalid live events surface diagnostics.
- Apply `session.created`, `session.updated`, `session.deleted`, `session.status`, `todo.updated`, `message.removed`, and `message.part.removed` through reducers.
- Verify `message.part.delta` only appends to existing typed parts.
- Verify `message.part.updated` preserves accumulated text when a stale empty update arrives.
- Verify missing event directory routes as `global`.

## Migration Steps

1. Audit upstream reducer coverage against `OpenCodeTypedEvent` and `OpenCodeStateReducer`.
2. Add missing typed event fields to `OpenCodeEventProperties` using upstream generated SDK optionality.
3. Extend reducer coverage for currently modeled but partially applied events.
4. Move event application result handling out of `AppViewModel+Events` into a sync coordinator/facade that updates stores explicitly.
5. Split bootstrap application into global store application and directory store application.
6. Replace broad post-event reloads with reducer-driven state updates where tests prove parity.
7. Keep fallback reloads only with comments identifying the missing trusted event path.
8. Remove fallback reloads once equivalent reducer/store updates are covered by tests.

## Fallback Refresh Audit

Audit and either remove or justify:

- `scheduleReload(for:)`
- `reloadTask`
- global `server.connected`/`global.disposed` refresh handling
- post-send reloads
- post-command reloads
- post-fork/compact/delete/rename reloads
- permission/question/todo hydration fallbacks after actions

## Done Criteria

- Server-backed state changes are applied through bootstrap plus typed reducers.
- Fallback refreshes are removed or documented as temporary.
- Typed event decode failures are diagnosable.
- Tests cover optional/defaultable upstream payload fields.
- Chat, permissions, questions, todos, sessions, and project state stay live without broad polling.
