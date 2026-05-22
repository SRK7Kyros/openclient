# Feature Facades Refactor Plan

## Goal

Introduce focused view-facing facades so SwiftUI views can stop depending on `AppViewModel` while stores remain focused state owners and coordinators remain workflow glue.

## Why Facades

Views currently call `AppViewModel` for derived snapshots, user actions, navigation effects, async workflows, and feature state. Directly injecting many stores into every view would make views noisy. Facades provide small feature-specific APIs.

## Target Facades

- `ConnectionFacade`: server editor, recent servers, connect/disconnect, connection overlay, Apple Intelligence entry.
- `ProjectFacade`: projects, selection, create-project search, settings, project preferences/actions.
- `SessionListFacade`: session rows, pinned/workspace sections, create/delete/rename, Live Activity menu state.
- `ChatFacade`: selected transcript, composer overlays, send/stop/command/fork/compact, interactions, debug probe.
- `ProjectFilesFacade`: Git/files snapshots, workspace selection, mode selection, file/diff loading.
- `MCPFacade`: status list, search snapshot, load/toggle actions.
- `CommerceFacade`: paywall presentation, entitlement, usage meter gates, purchase/restore.
- `DiagnosticsFacade`: event/debug probe logs and copy/export actions.
- `WidgetSnapshotPublisher`: widget payload publishing from store snapshots.
- `AppleIntelligenceWorkspaceFacade`: local workspace session/chat workflows.

## Design Rules

- Facades can compose stores, coordinators, API clients, and side-effect services.
- Facades should expose immutable snapshots and intent methods.
- Facades should not duplicate canonical state already owned by stores.
- Facades should be testable without SwiftUI views.
- Facades may be `@MainActor ObservableObject` when views need direct observation.

## Characterization Tests First

- Existing AppViewModel behavior reproduced through facade snapshots/actions.
- Facade actions call expected coordinators/API clients with correct directory/workspace scoping.
- Facade snapshots remain stable when unrelated store state changes.
- Facade methods preserve draft/session/navigation side effects.

## Migration Steps

1. Define facade protocols or concrete classes for one feature at a time.
2. Initialize facades from the app root while still keeping `AppViewModel` alive.
3. Move snapshot derivation from `AppViewModel` extensions into facades.
4. Move view actions from `AppViewModel` wrappers into facades.
5. Update views to consume facades.
6. Keep `AppViewModel` wrappers delegating to facades until all call sites migrate.
7. Delete wrappers and obsolete state.

## Suggested Order

1. `MCPFacade`, because the surface is small.
2. `ProjectFilesFacade`, because `ProjectFilesStore` is already focused.
3. `CommerceFacade`, because it is app-only and isolated.
4. `ConnectionFacade`.
5. `ProjectFacade`.
6. `SessionListFacade`.
7. `ChatFacade`.
8. Diagnostics, widgets, Live Activities, Apple Intelligence.

## Done Criteria

- Views use focused facades/stores instead of `AppViewModel` for normal operation.
- `AppViewModel` methods are wrappers or gone.
- Facade tests cover view-facing behavior.
