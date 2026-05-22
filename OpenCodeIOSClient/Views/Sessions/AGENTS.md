# Session Views Notes

## Responsibility

`Views/Sessions/` owns SwiftUI presentation for session lists, rows, avatars, create-session UI, workspace sections, pinned sessions, and session-adjacent menus such as Live Activity controls.

Session views should render prepared session-list state and report user intent upward. They should not own canonical sessions, selected-session state, previews, pin storage, workspace session caches, paywall gating, or session API workflows.

## Target Direction

The intended target is for session views to consume `SessionListStore`, related focused stores, or a future `SessionListFacade` directly. Current `AppViewModel` dependencies are temporary compatibility glue.

Move row snapshot derivation, pinned/unpinned/workspace section assembly, draft/permission badges, action-session filtering, and session preview composition out of view files and into stores/facades as the `AppViewModel` migration continues.

## Session Semantics

Keep session list semantics aligned with upstream OpenCode and server behavior:

- Session lists are scoped by directory unless using the special global project behavior.
- Root sessions and child/forked sessions have different presentation and navigation roles.
- Workspace session sections are derived from project/worktree state, not independent view state.
- Pinned sessions are local preferences scoped by server/project/directory and should tolerate temporarily missing session records.
- Pending permissions, drafts, busy status, and Live Activity badges are derived indicators, not alternate session sources of truth.

## Create Session UI

Create-session views should collect presentation input and send intent upward. Worktree creation, paywall/session-limit checks, session creation requests, selection, metering, and rollback/error behavior belong outside the view.

Workspace selection UI should preserve directory/workspace scoping rules from coordinators and stores rather than reconstructing request semantics locally.

## Do / Avoid

Do keep rows pure and snapshot-driven when practical. `SessionRow` should stay a render component over explicit inputs.

Do preserve accessibility identifiers for create-session controls, row actions, and Live Activity controls.

Do check compact and split-view navigation after changes that affect row selection or create-session presentation.

Avoid adding API calls, UserDefaults persistence, Keychain writes, SSE/reducer handling, or paywall metering directly in session views.

Avoid adding new `extension AppViewModel` logic in session view files unless it is temporary migration glue with a clear target owner.

Avoid storing duplicated session arrays, pinned IDs, workspace sections, or previews in view-local `@State` except as explicit render caches derived from immutable snapshots.
