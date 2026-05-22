# iOS UI Tests Notes

## Responsibility

`OpenCodeIOSClientUITests/` validates full-app user flows, screenshot scenes, and selected live-backend smoke tests.

UI tests should cover navigation and user-visible behavior, not internal state machines that can be tested faster in unit tests.

## Screenshot Tests

Screenshot scenes must remain deterministic and seeded in-app through `OPENCLIENT_SCREENSHOT_SCENE`. Do not make screenshot output depend on a live backend, StoreKit product loading, current date-sensitive copy beyond intentional relative labels, or local user secrets.

When adding a screenshot scene, add a stable accessibility marker using the `screenshot.scene.<name>` convention so capture automation can wait for readiness.

## Live Backend Smoke Tests

Live backend tests may use `OPENCODE_UI_TEST_*` environment variables. Keep these tests focused on end-to-end flows that unit tests cannot validate, such as connect -> project -> session -> chat rendering.

Avoid broad assertions that are brittle to copy/layout changes. Prefer accessibility identifiers and unique prompt/reply tokens.

## AppViewModel Migration

As views move off `AppViewModel`, keep UI tests focused on behavior: navigation survives, drafts persist, messages stream, permissions/questions appear, and reconnection works. UI tests should not care which facade/store backs a view.

## Do / Avoid

Do keep `continueAfterFailure = false` for flows where later steps are meaningless after a navigation failure.

Do attach debug logs/backend context when live-backend tests fail and the app exposes those diagnostics.

Avoid storing real credentials in code. Use environment variables.

Avoid adding slow UI tests for pure reducer/store behavior.
