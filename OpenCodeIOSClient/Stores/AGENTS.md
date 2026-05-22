# Stores Notes

## Responsibility

Stores should own focused observable app state slices. They are the intended direction for feature view-model/state ownership as the original large `AppViewModel` is retired. Keep them small, `@MainActor`, and aligned with upstream OpenCode boundaries: global connection state, project state, directory sync state, session lists, chat transcripts, composer drafts, interactions, and feature-specific surfaces.

## Patterns

Prefer explicit mutation methods on stores over mutating related fields directly from views. Stores may expose simple derived values, guard methods, cache helpers, and invariant-preserving mutations.

Networking and orchestration should stay outside stores by default. Use API clients for transport and bootstrap/coordinator types for sequencing. During migration, `AppViewModel` may bridge store access for existing call sites, but new code should not require `AppViewModel` to be the state owner.

## State And Data Flow

The OpenCode server remains canonical. Stores may hold bootstrap results, reducer-applied live events, optimistic UI state, local preferences, and read-through caches, but should not invent independent sources of truth.

For OpenCode sync data, prefer reducer-driven updates and directory/session scoping over broad refreshes, polling, or view-local mutation. Fallback refreshes should be temporary migration aids, kept outside stores when practical, and removed once the matching bootstrap/event/reducer path is trusted.

Keep store semantics close to upstream OpenCode web UI state consumption. When deciding how a store should hydrate, cache, apply events, or reconcile server responses, inspect upstream bootstrap/sync/reducer behavior before adding an iOS-only interpretation. Native presentation can differ, but source-of-truth boundaries should stay aligned with upstream unless the divergence is explicit.

## AppViewModel Relationship

`AppViewModel` is legacy compatibility glue over many stores. New work should move canonical state ownership into focused stores instead of adding more raw state to `AppViewModel`.

Compatibility accessors on `AppViewModel` are acceptable only while call sites are being migrated. Treat direct store ownership and focused store methods as the target architecture.

## Do / Avoid

Do add narrow store methods that preserve invariants, deduplicate IDs, cancel tasks, update related fields together, or expose feature-specific derived state.

Do keep stores UI-framework-light. `ObservableObject` and `@Published` are expected, but SwiftUI layout and presentation decisions belong in views or view-facing facades.

Avoid adding `URLSession`, direct API calls, SSE ownership, bootstrap sequencing, or retry policies to stores unless the architecture is explicitly changed to introduce a repository/sync-store layer.

Avoid adding fallback polling, broad reload flags, or cross-feature coordination here. Those belong in coordinators or the app facade until reducer/store ownership is made more explicit.
