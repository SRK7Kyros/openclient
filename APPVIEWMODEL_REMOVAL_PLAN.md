# AppViewModel Removal Plan

## Goal

Remove `AppViewModel` as a canonical state owner and business-logic hub without changing user-visible behavior.

The safe target is not a single giant deletion. The target is first to reduce `AppViewModel` to a thin compatibility adapter with no canonical state and no business logic. Once views no longer depend on that adapter, delete it in a final cleanup pass.

## Architecture Target

Use the app-level `OpenCodeIOSClient/AGENTS.md` architecture as canon:

- `Models/` owns OpenCode domain/server types and reducer semantics.
- `API/` owns transport, bootstrap fetching, SSE framing, and the shared event stream boundary.
- `Stores/` own focused observable feature state.
- `Coordinators/` own async workflow glue, request preparation, response interpretation, and routing between API/reducers/stores.
- `Views/` render state and send user intent upward.
- `AppViewModel` is temporary compatibility glue only.

## Non-Goals

- Do not rewrite UI design during this migration.
- Do not change OpenCode server semantics or iOS-specific product behavior unless tests prove current behavior is wrong.
- Do not replace reducer-driven sync with polling or broad reloads.
- Do not move networking into stores as a shortcut.
- Do not delete `AppViewModel` before views have a stable replacement facade or direct store access.

## Required Characterization Tests First

Before moving substantial code, add tests that describe the behavior we must preserve. These tests should fail if extraction changes user-visible behavior.

### Connection And Bootstrap

- Test that a successful connection applies global bootstrap in order: recent server persistence, projects, current selection reset, directory reset, composer option loading, event stream start.
- Test that connection cancellation resets connection state, stops event streaming, clears loading state, and does not leave a partial workspace loaded.
- Test that connection failure stops event streaming, resets directory state, surfaces the error, and keeps saved-server prompt behavior unchanged.
- Test that disconnect stops active workspace state, event stream, Apple Intelligence tasks where relevant, and resets global app state without deleting saved server metadata.

### Project And Directory Selection

- Test selecting a project/directory preserves the current draft, clears selected session, clears active chat transcript, resets todos/permissions/questions, resets MCP/files state, and sets session loading state.
- Test global project selection uses global session semantics and does not accidentally send `directory=/`.
- Test directory-scoped project selection uses the project worktree as the effective directory.
- Test create-project flow preserves local project fallback behavior when the server returns `global` for a directory.

### Session List And Selection

- Test directory reload applies sessions, commands, permissions, questions, and session statuses from bootstrap without losing selected workspace sessions unnecessarily.
- Test selecting a session uses synced messages when available, falls back to cached messages, restores todos/permissions/questions for that session, preserves the outgoing draft, restores the incoming draft, and sets `streamDirectory`.
- Test deleting a selected session clears selected session, messages, todos, status, cached sync state, and pinned-session references.
- Test pinned sessions stay scoped by server and directory and tolerate temporarily missing session records.

### Chat Transcript And Streaming

- Test `message.updated`, `message.part.updated`, `message.part.delta`, `message.removed`, and `message.part.removed` update active messages and cached session messages through reducers.
- Test deltas for inactive selected sessions update caches only when they should, and active Live Activity sessions still receive relevant updates.
- Test bursty transcript deltas are coalesced without reordering user-visible text.
- Test reasoning parts remain reasoning parts and are never created as provisional text parts from early deltas.
- Test canonical message reload does not wipe accumulated streamed text with empty stale server payloads.

### Composer And Drafts

- Test drafts persist by backend/server/workspace/session key and restore across session navigation.
- Test attachments deduplicate by ID, clear on successful send, and restore correctly on rollback where current behavior requires it.
- Test agent mentions are saved/restored with draft text and encoded as agent parts during send.
- Test composer focus/streaming blur flushes buffered transcript events.

### Send, Commands, Rollback, And Paywall

- Test prompt send prepares optimistic user message, marks session busy, calls `prompt_async`, clears/retains draft according to current behavior, and restores rollback state on failure.
- Test command send builds the expected slash-command draft text, marks status busy, calls the command endpoint, and restores command draft on failure.
- Test compact, fork, abort, rename, and delete use the same directory/workspace scoping as current `SessionCoordinator` behavior.
- Test free prompt metering reserves before send, refunds on failed send, and does not double-count when optimistic send is skipped.
- Test session creation checks the paywall/session limit before hitting the server and records successful session creation once.

### Permissions, Questions, And Todos

- Test bootstrap hydration for permissions/questions populates session-local stores before live events arrive.
- Test `permission.asked`, `permission.replied`, `question.asked`, `question.replied`, `question.rejected`, and `todo.updated` update both directory sync state and active session interaction state.
- Test replying/rejecting permissions and questions uses `/permission/:id/reply`, `/question/:id/reply`, and `/question/:id/reject` with correct directory/workspace scoping.
- Test todo strip state hides when all todos are completed and uses `GET /session/:id/todo` as canonical hydration.

### Git, Files, MCP, Widgets, Live Activities

- Test Git/files presentation derives its snapshot from `ProjectFilesStore` and preserves selected workspace directory behavior.
- Test MCP load/toggle sets loading/toggling/error state and refreshes status without mutating unrelated project/session/chat state.
- Test Live Activity message cache updates from reducer-applied transcript events for active Live Activity sessions.
- Test widget snapshot publishing observes session/preview changes without owning canonical session state.

### UI Smoke Tests

- Add or preserve UI tests for connection, recent servers, projects, sessions, chat, permission, question, and screenshot scenes.
- Add one navigation smoke test that moves Projects -> Sessions -> Chat -> Files -> MCP -> back to Chat and verifies the selected session draft/transcript survives.
- Add one compact-width smoke test for selecting a session, sending a prompt, receiving a streamed response, and handling a permission/question panel.

## Migration Phases

### Phase 0: Freeze The Contract

Add the characterization tests above before broad movement. Existing tests in `OpenCodeIOSClientTests` already cover parts of API request shape, coordinator routing, streaming reducers, and some stores; extend those rather than creating a parallel suite unless a new focused test file is clearer.

Run after this phase:

```bash
xcodebuild -quiet -project OpenCodeIOSClient.xcodeproj -scheme OpenCodeIOSClient -sdk iphonesimulator test
```

### Phase 1: Define Replacement Facades

Create focused view-facing facades or store compositions for the main surfaces:

- `ConnectionFacade` or direct `ConnectionStore` usage for connection views.
- `ProjectFacade` for project list, project picker, project settings, and directory selection.
- `SessionListFacade` for session rows, pinning, previews, workspace session lists, and create/delete/rename actions.
- `ChatFacade` for selected session transcript, composer overlays, interactions, sends, commands, fork/compact/abort, and debug diagnostics.
- `ProjectFilesFacade`, `MCPFacade`, `CommerceFacade`, `LiveActivityFacade`, and `WidgetSnapshotPublisher` for feature surfaces.

Do not move all call sites yet. First define the target seams and keep them testable without SwiftUI views.

### Phase 2: Move Canonical State Out

Move remaining canonical `AppViewModel` state into focused stores. Prioritize in this order:

1. Connection/app shell state.
2. Project and selected-directory state.
3. Directory/session list state.
4. Chat transcript and session interaction state.
5. Composer draft/model/agent selection state.
6. VCS/files and MCP state.
7. Live Activities, widgets, commerce, diagnostics, Apple Intelligence, and games.

After each slice, leave compatibility accessors on `AppViewModel` only when existing views still need them. Accessors should delegate to stores and should not own state themselves.

### Phase 3: Move Workflow Logic Out

Move procedural logic from `AppViewModel+*.swift` into the appropriate owner:

- Request preparation and rollback metadata into coordinators.
- Server transport into `OpenCodeAPIClient` or bootstrap helpers.
- Event application into `OpenCodeStateReducer` and typed event models.
- Store invariants into store methods.
- Feature-specific side effects into feature services/facades.

Keep `AppViewModel` methods as wrappers only while views still call them.

### Phase 4: Migrate Views

Move SwiftUI views off `AppViewModel` one surface at a time. Prefer injecting the smallest focused observable object or facade needed by that view.

Suggested order:

1. Connection views.
2. Project list and project settings.
3. Session list and session rows.
4. Chat composer and interaction panels.
5. Chat transcript.
6. Files/Git and MCP surfaces.
7. Commerce, Live Activities, widgets, debug, screenshots.

After each view surface migrates, remove the corresponding compatibility accessor or wrapper from `AppViewModel` if no call sites remain.

### Phase 5: Thin Adapter Checkpoint

At this checkpoint, `AppViewModel` may still exist but should satisfy all of these constraints:

- No canonical `@Published` domain state.
- No direct endpoint construction or raw networking.
- No reducer-like event mutation.
- No feature-specific business rules that cannot be tested through stores/coordinators/facades.
- Methods are either compatibility wrappers or app startup wiring.

If it fails any of these constraints, keep extracting before attempting deletion.

### Phase 6: Delete The Adapter

Only delete `AppViewModel` after all views and tests use focused stores/facades directly.

Deletion checklist:

- No Swift files reference `AppViewModel` except deleted previews/tests being migrated.
- `AppViewModelTests` have been split into focused store/coordinator/facade tests.
- Screenshot mode and UI tests still launch and seed deterministic scenes.
- Simulator test suite passes.
- A device build/install smoke test passes before TestFlight work.

## Verification Commands

Run frequently during extraction:

```bash
xcodebuild -quiet -project OpenCodeIOSClient.xcodeproj -scheme OpenCodeIOSClient -sdk iphonesimulator test
```

Run after structural file moves or target changes:

```bash
xcodegen generate
xcodebuild -quiet -project OpenCodeIOSClient.xcodeproj -scheme OpenCodeIOSClient -sdk iphonesimulator build
```

Run before considering the migration complete:

```bash
xcodebuild -quiet -project OpenCodeIOSClient.xcodeproj -scheme OpenCodeIOSClient -sdk iphonesimulator test
xcodebuild -quiet -project OpenCodeIOSClient.xcodeproj -scheme OpenCodeIOSClient -sdk iphoneos build
fastlane ios screenshots
```

## Stop Conditions

Stop and investigate before continuing if any of these happen:

- A live SSE event is visible in raw logs but does not reduce into state.
- Session selection loses drafts, cached messages, todos, permissions, or questions.
- A prompt send requires a post-send broad reload to show expected text.
- Permissions/questions regress to old `/tui/control/*` behavior.
- Reasoning text appears as answer text during streaming.
- App state begins depending on view-local mutation or store-owned networking.
- A refactor requires changing more than one feature surface at once without characterization tests.
