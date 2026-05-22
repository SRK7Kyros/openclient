# Chat Views Notes

## Responsibility

`Views/Chat/` owns native SwiftUI presentation for the chat surface: transcript rows, markdown/code rendering, tool activity, reasoning blocks, the composer, attachments, permissions, questions, todos, debug probes, and chat-specific sheets.

Chat views should render prepared chat state and report user intent upward. They should not own canonical transcript state, event application, send workflows, permission/question lifecycle, todo truth, or OpenCode streaming semantics.

## Target Direction

The intended target is for chat views to consume a focused chat facade/store rather than the legacy `AppViewModel`. Passing `AppViewModel` through chat views is temporary compatibility glue.

Move large derived snapshots, transcript grouping, forkable-message derivation, busy-state decisions, interaction filtering, and composer state adaptation toward `ChatStore`, `SessionInteractionStore`, `ComposerStore`, or a future `ChatFacade`.

## Transcript And Streaming

Transcript rendering must respect model/reducer semantics. Do not infer reasoning, answer text, or tool state by parsing streamed text. Use server-provided part types and reducer-applied message/part state.

Do not create provisional text UI for deltas that arrive before their typed part. Early deltas should remain ignored or buffered according to the existing reducer/store path, so reasoning is never misclassified as answer text.

Keep expensive render preparation out of hot `body` paths where possible. Large message chunking, markdown rendering, and syntax highlighting should remain deterministic and isolated from canonical state mutation.

## Composer

The composer may own short-lived presentation state such as picker visibility, sheet navigation, focus, selected photos, import progress, and local text-field binding glue.

Canonical draft text, agent mentions, attachments, command selection effects, send/stop behavior, MCP toggles, compact/fork actions, and rollback behavior should be owned by stores/facades/coordinators rather than the composer view itself.

Attachment import UI may live here, but keep payload size limits, deduplication, and final attachment mutation explicit and testable through the upward intent callbacks or a focused composer store.

## Permissions, Questions, And Todos

Permission, question, and todo views should be first-class UI surfaces over hydrated/live state. They should not poll or fetch directly.

Use `permission.asked`, `question.asked`, `todo.updated`, bootstrap hydration, and reducer/store state as the source of truth. Reply/reject/allow actions should be sent upward to API/coordinator/facade code that uses the correct `/permission` and `/question` endpoints.

Question local answer selection and custom text are presentation state. The pending question request itself is canonical store state.

## OpenCode Parity

Keep chat product semantics close to upstream OpenCode web UI: session-local todos, first-class permissions/questions, typed tool activity, streaming part identity, and bootstrap plus live event sync. Native layout, glass styling, keyboard behavior, and split-view adaptation can differ.

If behavior is ambiguous, inspect upstream chat/sync code before inventing iOS-specific semantics.

## Do / Avoid

Do keep chat subviews focused on one presentation job: bubble, markdown text, activity row, permission card, question panel, todo strip, composer, or sheet.

Do preserve accessibility labels/identifiers for send, stop, permission, question, attachment, command, and debug actions.

Do test compact keyboard behavior and split-view behavior after changing composer or navigation-affecting chat UI.

Avoid API calls, SSE parsing, reducer mutation, broad reloads, usage metering, or navigation ownership inside chat views.

Avoid adding new `extension AppViewModel` logic in chat view files. If compatibility glue is unavoidable, keep it small and give it a clear target owner.

Avoid duplicating canonical messages, todos, permissions, or questions in `@State`; use local state only for transient presentation and render caches derived from immutable snapshots.
