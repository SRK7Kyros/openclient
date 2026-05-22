# Root Views Notes

## Responsibility

`Views/Root/` owns top-level SwiftUI composition: app shell navigation, project/session/detail column routing, root previews, screenshot scene routing, and root-level screenshot/widget demo surfaces.

Root views coordinate presentation layout, not domain ownership. They should decide which feature surface is visible from existing observable state, but should not own canonical projects, sessions, chat, connection, files, MCP, commerce, or widget state.

## Navigation

Preserve the product navigation shape:

1. Projects/sidebar
2. Project content: sessions, files, or MCP
3. Detail: chat, file content, diff, or unavailable placeholder

Use `NavigationSplitView` adaptation intentionally. Compact iPhone navigation and wider split-view behavior are both first-class. Changes to selected project/session/file routing must be tested in compact and regular layouts.

## Target Direction

The intended target is for root views to consume a small app shell facade plus focused feature stores/facades. Passing the legacy `AppViewModel` through root routing is temporary compatibility glue.

Keep root routing thin. If selecting a route requires state mutation, bootstrap, network calls, cache reconciliation, or feature business logic, move that work into stores/coordinators/facades and call intent methods from root views.

## Screenshots And Previews

Screenshot scene routing and widget/live-activity demo views must remain deterministic. They should use seeded data and screenshot-only environment flags, not live backend state.

Keep screenshot-only and preview-only code wrapped in `#if DEBUG` where required so release archives do not depend on debug fixtures.

## Do / Avoid

Do keep navigation column preferences and animation state local to root views when they are presentation-only.

Do preserve accessibility identifiers used by screenshot/UI tests.

Do avoid broad root-level dependencies when a child feature can consume its own focused facade/store.

Avoid API calls, bootstrap sequencing, event stream control, reducer mutation, or persistence writes directly in root views.

Avoid making root views responsible for repairing inconsistent feature state. Fix invariants in stores/coordinators/facades instead.
