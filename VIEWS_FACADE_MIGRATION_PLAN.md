# Views Facade Migration Plan

## Goal

Move SwiftUI views away from direct `AppViewModel` dependency and toward focused feature facades/stores while preserving UI behavior.

## Current Reality

At least 40 view declarations take `AppViewModel` directly across root, connection, projects, sessions, chat, git, commerce, and configuration screens.

`SessionListView.swift` also contains `extension AppViewModel` snapshot derivation inside a view file.

## Target Pattern

- Root views receive an app shell/navigation facade.
- Feature views receive the smallest focused facade or snapshot/action closure set they need.
- Leaf views render explicit inputs and callbacks.
- Views use local `@State` only for presentation concerns.

## Characterization Tests First

- UI smoke test for Projects -> Sessions -> Chat -> Files -> MCP -> Chat preserving session/draft.
- Screenshot scenes for connection, projects, sessions, chat, permission, question, paywall, widgets, and Live Activity.
- Unit tests for facade snapshots replacing view-file `AppViewModel` extensions.

## Migration Order

1. `Views/Commerce`: replace `AppViewModel` with `CommerceFacade` and purchase manager/store.
2. `Views/Git`: replace with `ProjectFilesFacade` snapshots/actions.
3. `Views/Projects/MCPListView`: replace with `MCPFacade`.
4. `Views/Sessions`: move session list snapshot derivation out, inject `SessionListFacade`.
5. `Views/Connection`: inject `ConnectionFacade`.
6. `Views/Projects`: inject `ProjectFacade`.
7. `Views/Chat`: inject `ChatFacade`, `ComposerStore`, and interaction snapshots.
8. `Views/Root`: wire facades and remove `AppViewModel` routing.

## Per-View Checklist

- Replace `@ObservedObject var viewModel: AppViewModel` with focused dependency.
- Move derived snapshot logic out of view files.
- Replace direct state mutation with intent methods.
- Keep local presentation state local.
- Preserve accessibility identifiers.
- Run relevant previews/screenshot scenes.

## Done Criteria

- No production view requires `AppViewModel`.
- View files contain no `extension AppViewModel` blocks.
- Leaf views are snapshot/callback driven.
- UI tests and screenshot generation still pass.
