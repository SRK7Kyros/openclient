# Widgets And Live Activity Refactor Plan

## Goal

Make widgets and Live Activities side-effect consumers of app state rather than parallel sync owners or `AppViewModel` responsibilities.

## Current Reality

- Widget publishing is triggered from `AppViewModel+Widgets`.
- Live Activity behavior is driven from `AppViewModel+LiveActivities` and `LiveActivityStore`.
- Shared widget models and stores live in `OpenCodeShared`.
- Extension renders snapshots and ActivityKit state, with narrow inline permission/question action support.

## Target Architecture

- `WidgetSnapshotPublisher` observes project/session/interaction store snapshots and writes app-group payloads.
- `LiveActivityStore` owns active ActivityKit state and task bookkeeping.
- `LiveActivityFacade` translates chat/session/interactions into ActivityKit updates.
- Extension remains render-only plus narrow inline reply intents.

## Characterization Tests First

- Widget payload contains last connected server, projects, recent sessions, pinned sessions, statuses, and no secrets.
- Removing a session removes it from widget payload for that server.
- Live Activity state updates transcript snippets for active sessions.
- Pending permission/question state appears in ActivityKit content state.
- Inline permission/question actions call correct endpoints with directory/workspace scoping.

## Migration Steps

1. Extract widget snapshot construction from `AppViewModel+Widgets`.
2. Define publisher inputs from focused stores/facades.
3. Move Live Activity update derivation out of event handling paths and into `LiveActivityFacade`.
4. Keep extension code render-only and shared-client inline actions narrow.
5. Remove widget/live activity side effects from generic event handling once facades observe reducer-applied store changes.

## Done Criteria

- Main app publishes widget snapshots as store/facade side effects.
- Extension does not import main app stores, facades, or API clients.
- ActivityKit state contains compact derived data, not large transcripts or secrets.
- Screenshot/widget UI remains deterministic.
