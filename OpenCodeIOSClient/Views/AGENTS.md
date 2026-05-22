# Views Notes

## Responsibility

`Views/` contains SwiftUI presentation. Views should render observable state, own short-lived presentation state, and send user intent upward through focused stores, facades, or temporary `AppViewModel` compatibility methods.

Views should not be canonical state owners. They should not interpret OpenCode server payloads, apply SSE events, perform bootstrap reconciliation, or encode business rules that belong in stores, coordinators, reducers, or API clients.

## Target Direction

The intended direction is for views to consume focused feature stores or view-facing facades directly. Passing the legacy `AppViewModel` through view hierarchies is acceptable during migration, but new view code should avoid deepening that dependency.

If a view needs a large derived snapshot, prefer moving snapshot construction into a store/facade. AppViewModel extensions inside view files are legacy organization aids and should not be the target pattern for new code.

## Local View State

Use SwiftUI local state for presentation-only concerns such as sheet visibility, focus, scroll position, temporary text fields, selection affordances, animation phases, and navigation column preferences.

Do not put server-backed sessions, messages, todos, permissions, questions, projects, file status, MCP status, commerce state, or live sync state into `@State` as a source of truth. Those belong in focused stores and should flow into views as observable state or immutable snapshots.

## User Intent

Views should report intent rather than orchestrate workflows. Button actions may call a focused facade/store method or temporary `AppViewModel` method, but request preparation, rollback handling, endpoint calls, and reducer application should live outside views.

Async `Task` blocks in views should stay thin. If a task needs branching business logic or multiple state mutations, move that logic into a coordinator/facade/store method and call that method from the view.

## UI Patterns

Keep native SwiftUI behavior and platform adaptation. Preserve the established navigation shape: Projects -> Sessions/Files/MCP -> Chat or detail.

Design for compact and regular layouts. When changing shared views, check both iPhone-style compact navigation and wider split-view behavior.

Prefer stable, testable snapshots for complex lists and chat rendering. Keep expensive render preparation out of repeatedly recomputed `body` code when possible.

Use accessibility labels/identifiers for important controls, navigation actions, screenshot scenes, permission/question actions, and other UI-test touch points.

## OpenCode Parity

Native presentation can differ from upstream web, but product semantics should stay aligned. If a UI decision depends on how OpenCode treats sessions, todos, permissions, questions, streaming parts, tool activity, or project/workspace scope, check upstream web behavior before inventing local semantics.

## Do / Avoid

Do keep views small enough to read and preview. Extract subviews for presentation complexity, not to hide business logic.

Do keep previews and screenshot fixtures deterministic.

Do keep animations local to presentation and avoid using animation blocks as the only place state invariants are maintained.

Avoid adding `URLSession`, `OpenCodeAPIClient` calls, SSE parsing, reducer logic, or persistence writes directly in views.

Avoid adding new `extension AppViewModel` blocks in view files unless they are temporary migration shims with a clear target owner.

Avoid storing duplicated copies of store state in view-local `@State` except for render caches that are explicitly derived and updated from immutable snapshots.
