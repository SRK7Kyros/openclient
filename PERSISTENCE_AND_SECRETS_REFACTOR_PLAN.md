# Persistence And Secrets Refactor Plan

## Goal

Centralize local persistence and secret handling so state ownership is explicit, testable, and safe.

## Current Reality

Persistence is spread across:

- `AppViewModel+Connection` for recent servers and Apple Intelligence workspaces.
- `AppViewModel+Projects` for previews, pinned sessions, project preferences, actions, Live Activity auto-start.
- `AppViewModel+Composer` for model defaults and fun/games preferences.
- `ComposerStore` for draft persistence helpers.
- `Commerce/OpenClientCommerce.swift` for Keychain usage meter.
- `OpenCodeShared/OpenCodeServerPasswordStore.swift` for server passwords.
- `OpenCodeShared/OpenCodeWidgetStore.swift` for app-group widget snapshots.

## Target Ownership

- Server passwords: `OpenCodeServerPasswordStore` only.
- Recent server metadata: connection store/service.
- Drafts: composer store/service.
- Model defaults: model configuration store/service.
- Pinned sessions/previews/project actions/preferences: session/project preference stores.
- Commerce usage meter: commerce store/service.
- Widget snapshots: widget snapshot publisher plus `OpenCodeWidgetStore`.
- Apple Intelligence workspaces: Apple Intelligence workspace store/service.
- Debug breadcrumbs: diagnostics store/service.

## Characterization Tests First

- Password save/load/delete uses Keychain and never appears in recent server metadata.
- Recent server metadata survives relaunch and password hydration restores full config.
- Drafts persist by backend/server/workspace/session key.
- Pinned sessions preserve hidden/missing IDs.
- Widget snapshots contain no password and update per server.
- Commerce usage meter normalizes daily prompt count and persists session count.

## Migration Steps

1. Inventory every `UserDefaults`, Keychain, and app-group write.
2. Assign each key/service to a target owner.
3. Add small persistence services where direct store persistence would be noisy.
4. Inject services into stores/facades for testability.
5. Move load/save calls out of `AppViewModel`.
6. Add migration/backward compatibility only for persisted data that already shipped.
7. Redact secrets in all debug logs.

## Done Criteria

- No view writes persisted canonical data directly.
- `AppViewModel` does not own persistence workflows.
- Secrets live only in Keychain-backed stores.
- App-group payloads are safe for widgets/extensions.
