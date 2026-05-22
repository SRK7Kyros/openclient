# Test Characterization Refactor Plan

## Goal

Add and migrate tests so architecture refactors preserve behavior while moving state and workflow ownership out of `AppViewModel`.

## Current Reality

- Unit tests cover parts of stores, coordinators, streaming, API request shape, saved servers, and identifiers.
- `AppViewModelTests` still covers behavior that should eventually belong to stores/facades/coordinators.
- UI tests cover screenshots and selected live-backend flows.
- Mac tests cover Apple Intelligence integration when platform support exists.

## Test Ownership Target

- API request/response shape -> `OpenCodeAPIClientTests`.
- SSE/typed events/reducers -> `OpenCodeStreamingTests` or new reducer tests.
- Coordinators -> `CoordinatorTests`.
- Stores -> focused store test files.
- Facades -> focused facade test files.
- AppViewModel -> compatibility adapter tests only, then delete.
- UI tests -> navigation and user-visible end-to-end behavior.

## Required New Test Groups

- `StoreOwnershipTests`
- `SyncReducerParityTests`
- `FeatureFacadeTests`
- `CommerceStoreTests`
- `PersistenceServiceTests`
- `WidgetSnapshotPublisherTests`
- `LiveActivityFacadeTests`
- `ViewSnapshotDerivationTests` for complex immutable snapshots before view migration

## Characterization Before Each Refactor

For every extraction:

1. Write tests against current behavior.
2. Move implementation.
3. Keep tests green.
4. Move tests from `AppViewModelTests` to the new owner.
5. Delete obsolete AppViewModel coverage.

## UI Test Policy

Keep UI tests for:

- screenshot scenes
- connect/project/session/chat smoke flows
- second prompt after streaming
- reconnect and follow-up prompt
- permission/question rendering
- compact navigation/draft survival after view migration

Avoid UI tests for pure state-machine behavior covered by unit tests.

## Done Criteria

- Every architecture plan has pre-refactor characterization tests.
- `AppViewModelTests` shrinks as ownership moves.
- New stores/facades/coordinators have direct tests.
- UI tests remain behavior-focused and resilient to internal ownership changes.
