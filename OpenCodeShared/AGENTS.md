# OpenCodeShared Notes

## Responsibility

`OpenCodeShared/` contains code shared by the main app, widgets, and Live Activity extension: keychain helpers, widget snapshot models/storage, Live Activity attributes/action clients, preview text helpers, and stable hashing.

Shared code must remain small, platform-safe, and independent from main-app-only state owners like `AppViewModel`.

## Secrets

Server passwords belong in `OpenCodeServerPasswordStore` and Keychain-backed storage. Recent server metadata and widget snapshots must not contain passwords or other secrets.

Do not log secrets, write secrets into app group `UserDefaults`, include secrets in widget payloads, or add secrets to screenshot/preview fixtures.

When changing keychain access groups, keep the main app and extension entitlements aligned and preserve migration behavior between local and shared access groups.

## Widget And Live Activity Data

Widget and Live Activity models are derived snapshots, not canonical app state. The main app should publish snapshots as a side effect of store/facade state changes; widgets/extensions read those snapshots and render them.

Keep snapshot payloads Codable, Sendable where practical, compact, and stable across app/extension boundaries. Avoid adding fields that require live OpenCode API access from widgets.

## Dependencies

Do not import SwiftUI, StoreKit, app view models, app stores, or API clients into shared code unless a specific shared target requires it and the dependency is safe for every consumer.

Prefer Foundation-only value types and small helpers.

## Do / Avoid

Do keep app group identifiers, keychain services, widget kind identifiers, and ActivityKit attributes easy to audit.

Do consider backward compatibility for persisted shared payloads and keychain records.

Avoid making shared code depend on current main-app navigation, selected session, or in-memory stores.

Avoid putting OpenCode server sync reducers or endpoint logic here unless it is truly shared by app and extensions.
