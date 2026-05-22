# AppViewModel Notes

## Responsibility

`AppViewModel` is legacy root compatibility glue from the original large view model. It currently bridges SwiftUI views to focused stores, coordinators, API/bootstrap flows, event sync, navigation selection, diagnostics, and feature surfaces.

The intended architecture is to shrink this directory over time. Do not treat `AppViewModel` as the canonical model layer or the preferred home for new feature state.

## Target Direction

New canonical state should move into focused stores. New procedural workflow logic should move into coordinators, API/bootstrap helpers, reducers, or feature-specific services depending on the responsibility.

Use `AppViewModel` only as a temporary facade when existing view call sites still depend on it. Compatibility accessors are acceptable during migration, but they should point toward store-owned state rather than creating new `@Published` state here.

## State And Data Flow

Keep OpenCode data consumption aligned with upstream web UI behavior. `AppViewModel` should not invent local interpretations of bootstrap data, SSE events, permissions/questions, todos, sessions, or message streaming.

When applying server-backed state, prefer this flow:

1. API/bootstrap/event-stream types fetch or stream server data.
2. Models and reducers decode and apply OpenCode domain semantics.
3. Stores own the resulting observable state.
4. `AppViewModel` bridges existing views to those stores while migration continues.

## Extension Files

The `AppViewModel+Feature.swift` extension split is an organization aid, not an ownership boundary. Adding another extension can make legacy code easier to navigate, but it does not by itself complete the refactor.

When adding or editing an extension, ask whether the logic belongs in a focused store, coordinator, API/bootstrap type, reducer, or feature service instead.

## Do / Avoid

Do keep changes here small and extraction-friendly.

Do route new feature state through focused stores whenever practical.

Do route request preparation, async sequencing, rollback metadata, and response interpretation through coordinators when practical.

Do preserve existing compatibility behavior while migrating call sites; avoid breaking views just to make the architecture look cleaner.

Avoid adding new broad `@Published` properties here unless they are temporary compatibility glue and there is a clear target owner.

Avoid adding new direct event mutation logic here. Extend typed models and reducers instead.

Avoid adding raw `URLSession` or endpoint construction here. Use `OpenCodeAPIClient`, bootstrap helpers, or coordinators.

Avoid treating fallback refreshes, polling, or post-send reloads as the long-term sync model. They should be temporary until bootstrap plus live reducer paths are trusted.
