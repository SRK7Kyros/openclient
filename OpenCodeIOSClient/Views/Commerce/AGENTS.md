# Commerce Views Notes

## Responsibility

`Views/Commerce/` owns SwiftUI presentation for paywalls, purchase/restore controls, commerce error display, and debug entitlement controls.

Commerce views should render commerce state and report purchase, restore, dismiss, and debug intent upward. They should not own StoreKit flows, usage metering, entitlement checks, paywall gating, or persistence.

## Target Direction

The intended target is for paywall views to consume a commerce store/facade directly. Current `AppViewModel` dependencies are temporary compatibility glue.

Move purchase/restore orchestration, unlock state, debug overrides, and prompt/session/action gating out of views and into `Commerce/` services/stores/facades.

## Screenshot And Debug Behavior

Paywall screenshot output must be deterministic. Use screenshot-only environment checks for fixed marketing copy/pricing when needed, and never depend on live StoreKit product loading for screenshot scenes.

Debug entitlement controls must remain behind `#if DEBUG` and should not appear in screenshot scenes unless explicitly requested for a debug screenshot.

## Do / Avoid

Do keep paywall copy, benefits, and action buttons clear and testable.

Do render StoreKit loading and error state without hiding purchase/restore affordances unexpectedly.

Avoid StoreKit calls, Keychain usage-meter writes, entitlement decisions, or paywall gating rules directly in views.

Avoid making commerce views depend on OpenCode server state or session/chat internals.
