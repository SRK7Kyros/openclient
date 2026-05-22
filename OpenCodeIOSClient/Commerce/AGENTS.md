# Commerce Notes

## Responsibility

`Commerce/` owns app-only business rules for OpenClient monetization: StoreKit product IDs, entitlements, paywall reasons, free usage limits, usage metering, and purchase/restore flows.

Commerce is not part of the OpenCode server/domain model. Keep it separate from OpenCode sync state, API payload interpretation, reducers, sessions, messages, permissions, questions, and project/workspace semantics.

## Target Direction

The intended architecture is a focused commerce store/service/facade that views and send/session workflows can query. `AppViewModel+Commerce` is legacy compatibility glue and should shrink over time.

Entitlement and usage decisions should be centralized here or in a dedicated commerce store, not scattered through chat, session, project, or view code.

## State And Persistence

StoreKit entitlement state should come from `OpenClientPurchaseManager` or its future replacement. Usage metering should remain explicit, deterministic, and testable.

Use secure/local persistence only for app commerce state that must survive launches, such as free usage metering. Do not store OpenCode server data or server credentials here.

When changing metering, preserve clear reserve/commit/refund semantics so failed sends do not consume free prompt quota and successful session creation is counted once.

## Views

Paywall views should render commerce state and report purchase/restore/debug intent upward. Keep product lookup, entitlement refresh, usage metering, and paywall gating outside SwiftUI views.

Debug entitlement controls must stay behind `#if DEBUG` and should not affect release behavior.

## Do / Avoid

Do keep product identifiers, limits, entitlement overrides, paywall reasons, and usage-meter types easy to audit.

Do add tests before changing gating behavior for prompt sends, session creation, project actions, purchases, restores, daily reset, and refunds.

Do keep commerce independent from upstream OpenCode behavior. Commerce gates app usage, but should not change how OpenCode data is decoded or reduced.

Avoid adding StoreKit calls, Keychain usage-meter writes, or paywall decisions directly in views or unrelated stores.

Avoid coupling commerce logic to `AppViewModel` beyond temporary compatibility wrappers.

Avoid making debug entitlement overrides available in release builds.
