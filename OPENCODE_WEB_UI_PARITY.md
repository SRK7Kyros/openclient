# OpenCode Web UI Parity

This iOS client should mirror OpenCode's upstream web UI behavior as closely as practical, translating the TypeScript app's concepts into native Swift rather than inventing iOS-specific semantics first.

## Core Principle

When implementation details are ambiguous, prefer the upstream OpenCode web app's behavior and architecture over a locally invented approach.

The upstream OpenCode team owns both the web UI and the server, so their frontend choices are usually more informed by server behavior, planned API direction, and edge cases than this client can infer independently. Treat those choices as the default source of truth unless native platform constraints or explicit product feedback require a different path.

## Translation Guidance

- Mirror TypeScript state and event semantics in Swift models, reducers, and stores.
- Prefer porting upstream concepts directly before creating new abstractions.
- For each new feature request, first decide whether it likely exists in the upstream web UI. If it does, inspect the upstream implementation and model the Swift work after it.
- If it is unclear whether the feature exists upstream, ask the user whether this should mirror an existing web UI feature or become new app-only behavior that we model ourselves.
- Keep event handling reducer-driven, matching upstream event application patterns.
- Treat generated TypeScript SDK types as the reference for Swift typed models.
- Preserve upstream bootstrap phases and source-of-truth boundaries.
- Prefer upstream session, message, todo, permission, and question lifecycle behavior.
- Avoid fallback polling, ad hoc refreshes, or UI-local mutations when upstream relies on bootstrap plus live events.
- When upstream behavior and current iOS behavior differ, investigate upstream first and document any intentional divergence.

## Native Adaptation

Native iOS UI should still feel at home on Apple platforms, but product semantics should remain aligned with OpenCode web. SwiftUI presentation, navigation, animation, and platform integrations may differ, while the underlying data flow and behavior should conceptually map back to the TypeScript implementation.

If an upstream web UI process appears shaped primarily by JavaScript or browser runtime constraints, the assistant may propose a more Swift-native implementation instead. This is especially relevant when the TypeScript design is influenced by JavaScript's single-threaded execution model, browser event-loop behavior, or React-specific rendering constraints, and Swift concurrency or native platform APIs can express the same product semantics more safely or cleanly.

Any such divergence should be explicit: explain which upstream behavior is being preserved, which implementation detail is being changed, and why the Swift-native approach is better for this client.

## Reference Priority

Use this priority order when making decisions:

1. Live OpenCode server behavior.
2. Upstream OpenCode web UI implementation.
3. Existing iOS client architecture and product feedback.
4. New local assumptions.

New local assumptions should be temporary and replaced with verified upstream/server behavior when possible.
