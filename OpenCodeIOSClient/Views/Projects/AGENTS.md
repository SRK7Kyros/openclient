# Project Views Notes

## Responsibility

`Views/Projects/` owns SwiftUI presentation for project navigation, project rows, create-project UI, project settings, configuration sheets, project actions, workspace display settings, and project-adjacent MCP presentation.

Project views should render prepared project state and report user intent upward. They should not own canonical projects, selected directory, workspace caches, project preferences, action persistence, MCP status, or OpenCode project discovery semantics.

## Target Direction

The intended target is for project views to consume `ProjectStore`, project preference/action stores, `MCPStore`, and focused facades directly. Current `AppViewModel` dependencies are temporary compatibility glue.

Move project row snapshots, project selection effects, create-project search results, project preference mutations, workspace toggles, and action configuration logic toward stores/facades/coordinators.

## Project Semantics

Keep project behavior aligned with known OpenCode server behavior:

- `global` is special and should not be treated as an ordinary directory-scoped project.
- Non-global project selection establishes a directory/worktree scope for sessions, commands, permissions/questions, files, MCP, and workspace state.
- Project discovery can be implicit through directory/session warm-up and current-project queries.
- Local fallback projects are app-side navigation affordances, not server-created projects.

Do not invent new project creation semantics in views. Directory search, warm-up, current-project resolution, and server update behavior belong in coordinators/API/facades.

## Settings, Actions, And MCP

Project settings views should collect presentation input only. Live Activity auto-start, project workspace visibility, project action configuration, and project icon/color persistence should be owned by focused stores/facades.

MCP presentation may live here while it is project-adjacent, but MCP status loading/toggling/error state belongs in `MCPStore` or a future MCP facade, not in view-local state.

Commerce-gated action UI should render entitlement state and report upgrade intent upward. Paywall gating and usage/entitlement decisions belong in commerce/facade code.

## Do / Avoid

Do preserve accessibility identifiers for disconnect, create project, configurations, settings, project rows, and MCP controls.

Do keep create-project and settings sheets deterministic for screenshot/UI tests.

Do check compact and split-view navigation after project selection changes.

Avoid API calls, directory warm-up logic, current-project reconciliation, persistence writes, MCP toggling implementation, or paywall rules directly in project views.

Avoid adding new `extension AppViewModel` logic in project view files unless it is temporary migration glue with a clear target owner.

Avoid duplicating project arrays, selected directory, search results, workspace state, or MCP status in view-local `@State` except for transient UI controls such as sheet item selection or search text.
