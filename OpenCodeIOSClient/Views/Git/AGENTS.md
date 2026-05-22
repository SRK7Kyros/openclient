# Git And Files Views Notes

## Responsibility

`Views/Git/` owns SwiftUI presentation for project files, VCS status, changed-file summaries, file trees, file content previews, and unified diffs.

These views should render prepared file/VCS snapshots and report user intent upward. They should not own canonical VCS info, file statuses, diff caches, file tree caches, selected workspace directory, or file loading workflows.

## Target Direction

The intended target is for Git/files views to consume `ProjectFilesStore` or a focused `ProjectFilesFacade` directly. Current `AppViewModel` dependencies and `AppViewModel.ProjectFilesSnapshot` are migration shims.

Move snapshot construction, relative path logic, workspace directory selection, file-tree expansion state, VCS mode selection, and file/diff loading orchestration toward `ProjectFilesStore`, coordinators, or a feature facade.

## Data And Loading

File/VCS data comes from OpenCode file and VCS endpoints through API/coordinator/facade code. Views may trigger thin load intents with `.task`, but request decisions, cache checks, error handling, and store mutation belong outside views.

Keep file tree and diff state scoped to the effective project/workspace directory. Switching workspaces should not leak selected files, expanded directories, cached contents, or diffs across scopes unless an explicit cache layer owns that behavior.

## Rendering

Diff and file-content rendering can be view-local presentation work. Parsing patches for display, syntax highlighting, row layout, and scroll behavior may live here as long as they do not mutate canonical state.

Keep large file, binary file, loading, and error states explicit in UI. Avoid hiding failed loads behind empty lists or stale content.

## Do / Avoid

Do keep file rows and diff rows snapshot-driven and deterministic.

Do preserve selection behavior across compact and split-view navigation.

Do keep expensive rendering isolated from repeated canonical state mutation.

Avoid API calls, direct file loading, diff cache mutation, VCS refresh orchestration, or workspace-scope decisions directly in views.

Avoid adding new `extension AppViewModel` logic in Git view files unless it is temporary migration glue with a clear target owner.

Avoid duplicating file status arrays, tree nodes, diffs, selected file paths, or loaded file contents in view-local `@State` except for transient presentation state.
