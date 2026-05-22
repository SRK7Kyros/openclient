# iOS Unit Tests Notes

## Responsibility

`OpenCodeIOSClientTests/` contains unit and integration-style tests for the iOS app target. Use these tests to lock down OpenCode API request shape, typed event decoding, reducers, stores, coordinators, saved-server behavior, and legacy `AppViewModel` compatibility while it is being removed.

## Test Priorities

Prefer characterization tests before refactors. If behavior currently lives in `AppViewModel`, add or move tests that describe the behavior before extracting it into stores, coordinators, facades, or reducers.

High-value coverage areas:

- API endpoint path/method/body/header/query shape, especially directory/workspace scoping.
- SSE parsing, managed event decoding, dropped-event diagnostics, and batching/coalescing.
- `OpenCodeTypedEvent`, `OpenCodeStateReducer`, `OpenCodeDirectorySyncState`, and `OpenCodeStreamReducer` semantics.
- Store invariants, cache behavior, optimistic updates, rollback, draft persistence, and session-local interactions.
- Coordinator request preparation, rollback metadata, selection decisions, and routing gates.
- Commerce metering reserve/refund/session-count behavior.

## Upstream Parity

When tests involve OpenCode server data, model fixtures after upstream web SDK/event payloads and observed live server behavior. Avoid inventing simplified shapes that would hide optional/defaultable-field regressions.

For typed event tests, include both valid payloads with omitted optional/defaultable fields and incomplete payloads that should produce dropped-event diagnostics rather than silent failures.

## AppViewModel Migration

`AppViewModelTests` may exist while `AppViewModel` is compatibility glue. As behavior moves out, move tests to focused store/coordinator/facade test files and reduce direct `AppViewModel` coverage to adapter behavior only.

Do not add new broad `AppViewModel` tests for behavior whose target owner is already clear.

## Do / Avoid

Do keep tests deterministic and isolated from user defaults/keychain state unless the test explicitly covers persistence.

Do clear shared storage keys in `setUp`/`tearDown` when testing persistence.

Do prefer direct model/store/coordinator tests over UI tests for state-machine behavior.

Avoid hitting live OpenCode servers from unit tests. Use mocked `URLProtocol`, fixtures, and direct reducer inputs.

Avoid relying on wall-clock sleeps unless testing batching/timing behavior; keep timing windows small and justified.
