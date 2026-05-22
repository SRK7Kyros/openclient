# Connection Views Notes

## Responsibility

`Views/Connection/` owns SwiftUI presentation for the connection sheet, recent servers, server editor UI, connection progress overlay, Apple Intelligence entry point, and help/onboarding content.

Connection views should collect user input, render connection state, and report intent upward. They should not own connection lifecycle orchestration, bootstrap sequencing, saved-server persistence, password storage, or OpenCode API calls.

## Target Direction

The intended target is for connection views to consume `ConnectionStore`, recent-server state, and a focused connection facade directly. Current `AppViewModel` dependencies are temporary compatibility glue.

Move saved-server editing, recent-server mutation, validation, connection attempts, overlay phase management, and Apple Intelligence workspace setup toward focused stores/facades/coordinators.

## Secrets And Persistence

Passwords belong in Keychain-backed storage, not in view-local state beyond temporary text entry. Recent server metadata should remain separate from secrets.

Do not write passwords, tokens, connection URLs with credentials, or debug secrets to logs, previews, screenshots, or local metadata stores.

## Connection Semantics

Connection UI should reflect the connection/bootstrap lifecycle managed outside the view:

- health check
- global bootstrap
- interface preparation
- event stream startup
- success, cancellation, or failure

Views may show those phases, but should not decide bootstrap ordering or partially mutate workspace state.

Apple Intelligence local workspace mode is a separate backend surface. Keep its presentation entry points here, but move workspace/session state and local-model workflows toward focused Apple Intelligence stores/services during cleanup.

## Help Content

Help/onboarding views are presentation content. They may use rich native animation and local presentation state, but should not depend on live server state or mutate app data.

Keep help content deterministic for previews and screenshots.

## Do / Avoid

Do preserve accessibility identifiers for add/edit server, connect, cancel, retry, recent server, and help controls.

Do keep insecure-HTTP warnings and connection validation visible before connection attempts.

Do keep screenshot scenes deterministic and free of real credentials.

Avoid API calls, URLSession usage, bootstrap logic, Keychain writes, or event-stream start/stop logic directly in connection views.

Avoid storing canonical recent-server lists or connection phase state in view-local `@State`.

Avoid adding new `extension AppViewModel` logic in connection view files unless it is temporary migration glue with a clear target owner.
