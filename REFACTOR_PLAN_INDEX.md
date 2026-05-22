# Refactor Plan Index

## Purpose

This index coordinates the architecture refactors implied by the repository `AGENTS.md` files. Each linked plan should be worked as a focused pass with characterization tests before broad code movement.

The shared target is pragmatic SwiftUI MVVM:

- `Models/` mirrors OpenCode domain/server types and reducer semantics.
- `API/` owns transport, bootstrap fetching, SSE framing, and the event-stream boundary.
- `Stores/` own focused observable feature state.
- `Coordinators/` own async workflow glue and request/response sequencing.
- `Views/` render state and send intent upward.
- `AppViewModel` shrinks into temporary compatibility glue and is then deleted.

## Plan Files

1. `APPVIEWMODEL_REMOVAL_PLAN.md`
   Existing plan for shrinking and deleting the legacy root facade.

2. `SYNC_PARITY_REFACTOR_PLAN.md`
   Align bootstrap, SSE, typed events, reducers, and fallback refresh behavior with upstream OpenCode web UI.

3. `STORE_OWNERSHIP_REFACTOR_PLAN.md`
   Move canonical state ownership out of `AppViewModel` and into focused stores.

4. `FEATURE_FACADES_REFACTOR_PLAN.md`
   Define feature facades that views can consume instead of `AppViewModel`.

5. `VIEWS_FACADE_MIGRATION_PLAN.md`
   Migrate SwiftUI views from `AppViewModel` to focused facades/stores.

6. `MODELS_CLEANUP_REFACTOR_PLAN.md`
   Keep `Models/` focused on OpenCode domain/server/reducer semantics and move app-only types elsewhere.

7. `PERSISTENCE_AND_SECRETS_REFACTOR_PLAN.md`
   Centralize persistence, app-group snapshots, and Keychain usage while protecting secrets.

8. `COMMERCE_REFACTOR_PLAN.md`
   Move paywall, entitlement, and usage-metering rules into a focused commerce layer.

9. `WIDGETS_LIVE_ACTIVITY_REFACTOR_PLAN.md`
   Make widgets and Live Activities side-effect consumers of app state, not parallel sync owners.

10. `TEST_CHARACTERIZATION_REFACTOR_PLAN.md`
   Add and migrate tests needed to safely execute the architecture refactors.

## Recommended Order

1. Sync parity before ownership cleanup.
2. Store ownership before view migration.
3. Facade definitions before deleting `AppViewModel` call sites.
4. Persistence and commerce cleanup before final AppViewModel deletion.
5. Widgets/Live Activities after store/facade ownership is clear.
6. Tests before every behavior-preserving extraction.

## Cross-Cutting Rules

- Prefer upstream OpenCode web behavior over local assumptions for server-backed data flow.
- Do not add new canonical state to `AppViewModel`.
- Do not move networking into stores or views.
- Do not duplicate reducer event mutation in views, stores, or coordinators.
- Keep compatibility adapters only as temporary migration aids.
- Preserve on-device behavior and compact/split-view navigation throughout.

## Completion Criteria

The full refactor family is complete when:

- Views no longer require `AppViewModel` for normal operation.
- Canonical feature state lives in focused stores.
- Feature workflows are expressed through facades/coordinators.
- OpenCode sync behavior is reducer-driven and aligned with upstream web UI.
- App-only models and persistence are owned by their features.
- Widgets and Live Activities consume published snapshots/ActivityKit state.
- Unit, UI, screenshot, and on-device smoke tests pass.
