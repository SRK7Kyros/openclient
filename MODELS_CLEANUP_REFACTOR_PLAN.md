# Models Cleanup Refactor Plan

## Goal

Keep `OpenCodeIOSClient/Models/` focused on OpenCode server/domain data shapes and reducer semantics. Move app-only preferences, stores, games, and persistence helpers to owning feature areas.

## Current Drift

App-only types currently in `Models/` include:

- `PinnedCommandStore`
- `FunAndGamesPreferencesStore`
- `NewSessionDefaultsStore`
- `FindBugGame`
- `FindPlaceGame`
- `OpenCodeSavedServer`
- possibly `OpenCodeServerConfig` depending on final connection ownership

## Target Placement

- `PinnedCommandStore` -> `Stores/` or `Stores/ProjectPreferencesStore.swift` area.
- `NewSessionDefaultsStore` -> composer/model configuration feature.
- `FunAndGamesPreferencesStore` -> fun/games feature store.
- game models -> fun/games feature directory.
- saved server metadata -> connection feature/store.
- server config -> connection model/store area unless kept as shared app config.

## Characterization Tests First

- Persist/restore pinned commands per scope.
- Persist/restore new session defaults per normalized server base URL.
- Persist/restore fun/games preferences.
- Save/load recent server metadata separately from Keychain password.
- Game model behavior remains unchanged after file moves.

## Migration Steps

1. Create feature directories or store files for app-only types.
2. Move one type family at a time.
3. Regenerate Xcode project if file paths change and project generation requires it.
4. Update imports/references.
5. Move tests to matching feature-oriented test names when practical.
6. Leave `Models/` with OpenCode DTOs, typed events, reducers, and server request/response types only.

## Done Criteria

- `Models/` no longer contains app-only stores or feature-local persistence helpers.
- App-only types live near their owning store/facade/feature.
- Server-backed model optionality remains aligned with upstream OpenCode SDK types.
