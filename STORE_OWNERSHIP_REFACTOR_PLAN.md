# Store Ownership Refactor Plan

## Goal

Move canonical observable state from legacy `AppViewModel` into focused stores that act as feature view-model state surfaces.

## Current Reality

Focused stores exist, but `AppViewModel` still owns or bridges many state slices:

- connection config and overlay state
- Apple Intelligence workspace state
- create-session form state
- selected files workspace directory
- debug probe and diagnostics state
- paywall and usage meter state
- sheet presentation state
- large compatibility accessors over store fields

## Target Store Map

- `ConnectionStore`: backend mode, connection phase, server health/version, recent server metadata, connection overlay/editor state.
- `ProjectStore`: projects, current project, selected directory, project picker/create-project UI state.
- `DirectoryStore`: directory sync state, sessions, selected session, commands, statuses.
- `SessionListStore`: previews, pinned IDs, workspace session caches, pending project action runs.
- `ChatStore`: active transcript, cached transcripts, tool details, transcript buffering/coalescing.
- `SessionInteractionStore`: session-local todos, permissions, questions.
- `ComposerStore`: drafts, agent mentions, attachments, focus/reset tokens.
- `ModelConfigurationStore`: providers, agents, selected models/agents/variants/defaults.
- `ProjectFilesStore`: VCS, file tree, diffs, selected file, workspace file state.
- `MCPStore`: MCP status/loading/toggling/errors.
- `CommerceStore`: entitlement, paywall, usage meter, debug entitlement override.
- `LiveActivityStore`: active activities and side-effect state.
- `DiagnosticsStore`: debug probe logs, event breadcrumbs, stream diagnostics.
- Feature stores for Apple Intelligence, widgets, fun/games, project preferences/actions.

## Characterization Tests First

- Store reset clears only owned state.
- Store mutations preserve invariants and deduplicate IDs.
- AppViewModel compatibility accessors reflect store state before and after migration.
- Drafts, pins, project preferences, and usage meters persist across new store instances.
- Selected session change restores transcript, todos, permissions, questions, and draft from stores.

## Migration Steps

1. Inventory every `@Published` property in `AppViewModel` and assign a target store.
2. Move one state slice at a time into the target store.
3. Replace direct `AppViewModel` storage with delegating accessors only where views still require them.
4. Add focused store methods for multi-field invariants.
5. Move persistence load/save methods into target stores or persistence services.
6. Update tests to target stores directly.
7. Delete compatibility accessors once all call sites use stores/facades.

## Extraction Order

1. Sheet/presentation state that already has clear feature owners.
2. Commerce state.
3. Connection/recent server editor state.
4. Project/create-project/settings state.
5. Session create form and workspace selection state.
6. Diagnostics/debug probe state.
7. Apple Intelligence state.
8. Widget/Live Activity side-effect state.

## Done Criteria

- `AppViewModel` contains no canonical `@Published` domain state.
- Store methods own feature invariants.
- Views and facades can observe stores directly.
- Tests cover stores independently of `AppViewModel`.
