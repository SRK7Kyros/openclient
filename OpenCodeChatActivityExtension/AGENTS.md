# Live Activity And Widget Extension Notes

## Responsibility

`OpenCodeChatActivityExtension/` owns WidgetKit and ActivityKit presentation for recent/pinned session widgets and chat Live Activities.

The extension should render shared snapshots and ActivityKit state. It should not become a second full OpenCode client, own canonical app state, or duplicate main-app sync behavior.

## Data Flow

Widgets read `OpenCodeWidgetSnapshotPayload` from `OpenCodeWidgetStore`. The main app publishes those snapshots as a side effect of app state changes.

Live Activities render `OpenCodeChatActivityAttributes` and `ContentState` provided by the main app. The extension may offer limited inline actions for permissions/questions through shared action clients.

Do not add live SSE listeners, broad bootstrap calls, session list fetching, or message transcript hydration to the extension.

## Inline Actions

Inline permission/question actions should remain narrow and explicit. Use the shared `OpenCodeLiveActivityActionClient` for the correct `/permission` and `/question` reply endpoints with directory/workspace scoping.

The extension may read credentials from the shared Keychain access group through `OpenCodeServerPasswordStore`, but must never persist or log passwords itself.

## Rendering

Keep widget and Live Activity UI compact, deterministic, and resilient to stale/missing snapshots. Empty states should tell the user to open the app to sync rather than attempting network recovery from the extension.

Deep links should route users back to the main app with session, directory, workspace, and action context when needed.

## Do / Avoid

Do keep preview/placeholder data deterministic and safe for screenshots.

Do keep widget timelines simple and based on app-published snapshots.

Do preserve app group and keychain access group compatibility with the main app target.

Avoid importing main app view models, stores, coordinators, or API client types into the extension.

Avoid adding secrets, raw server responses, or large transcripts to widget snapshots or ActivityKit state.

Avoid changing OpenCode data semantics here. Derive display state in the main app before publishing snapshots when possible.
