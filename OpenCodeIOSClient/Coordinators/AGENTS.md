# Coordinators Notes

## Responsibility

Coordinators are glue between focused stores, API clients, bootstrap helpers, reducers, and the shrinking legacy app facade. They manage data going out to the network and coming back into state without becoming long-lived state owners themselves.

In the intended architecture, focused stores are the feature view-model/state layer and SwiftUI files are the views. `AppViewModel` remains only as legacy root compatibility glue while call sites migrate. Coordinators sit between those layers when work needs sequencing, request preparation, response interpretation, or reducer routing.

Use coordinators for connection phases, project/session action preparation, directory/workspace scoping decisions, optimistic metadata, rollback values, and live-event routing.

## Patterns

Prefer small value structs for coordinator inputs and outputs. This keeps coordinators easy to test and lets callers or focused stores apply side effects explicitly instead of hiding state changes inside orchestration code.

Coordinators may call `OpenCodeAPIClient` when they are sequencing a feature action. Keep transport details, request encoding, SSE parsing, and raw persistence out of coordinators.

## State And Data Flow

Avoid adding long-lived canonical state to coordinators. Stores own state, API clients fetch data, bootstrap helpers define hydration phases, and reducers apply typed sync events. Coordinators decide when and how those pieces should be invoked.

When handling OpenCode sync behavior, prefer routing to `OpenCodeStateReducer` through `EventSyncCoordinator` rather than duplicating event mutation logic.

## AppViewModel Relationship

`AppViewModel` is compatibility glue that invokes coordinators, applies results to stores, and bridges existing view call sites. Treat it as legacy glue to shrink over time, not as the long-term model or view-model layer.

New procedural logic should usually move from `AppViewModel` into a coordinator when it is not pure store mutation and not view presentation. New canonical state should usually move into a focused store instead of `AppViewModel`.

Prefer store methods or explicit returned results for store mutation. Coordinators should not silently mutate broad app state; if a coordinator is temporarily coupled to a store during migration, keep that coupling narrow and move toward returned results or focused store APIs over time.

## Do / Avoid

Do centralize directory/session/workspace scoping rules here, especially request directory decisions for session actions.

Do return rollback and optimistic-update metadata from coordinators instead of recomputing it in multiple call sites.

Do keep network-facing coordinator methods explicit about which API call they make and which state result they expect callers to apply.

Avoid storing active tasks, caches, selected entities, or published UI state in coordinators unless a future refactor explicitly creates a stateful controller for that purpose.

Avoid adding reducer-like event mutation outside `OpenCodeStateReducer`.
