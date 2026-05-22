# Commerce Refactor Plan

## Goal

Move monetization, entitlement, paywall, and usage metering into a focused commerce layer independent of OpenCode sync state and legacy `AppViewModel`.

## Current Reality

- StoreKit and usage meter primitives live in `Commerce/OpenClientCommerce.swift`.
- Usage meter state, paywall reason, debug entitlement override, purchase manager, and gates live in `AppViewModel`.
- Paywall views call `AppViewModel` for purchase/restore/dismiss/debug actions.
- Prompt send and session creation call commerce gates through `AppViewModel`.

## Target Architecture

- `CommerceStore`: entitlement state, paywall reason, usage meter, debug override.
- `CommerceService`: StoreKit purchase/restore/refresh and usage persistence.
- `CommerceFacade`: view-facing paywall state and workflow-facing gates.
- Views render commerce state and call facade intent methods.
- Send/session workflows query commerce gates through facade/service.

## Characterization Tests First

- Free prompt reserve succeeds until limit.
- Failed send refunds reserved prompt.
- Pro unlock bypasses prompt/session limits.
- Debug `limitReached` forces prompt block in Debug only.
- Session creation gate blocks after free session limit and records successful creation once.
- Daily prompt count resets by local day while session count persists.

## Migration Steps

1. Extract `CommerceStore` with `usageMeter`, `paywallReason`, and debug override.
2. Move `hasProUnlock`, remaining prompt count, session count, and gate decisions into commerce layer.
3. Move purchase/restore wrappers out of `AppViewModel`.
4. Update paywall and debug entitlement views to use commerce facade.
5. Update send/session workflows to query commerce facade.
6. Delete `AppViewModel+Commerce` wrappers after call sites migrate.

## Done Criteria

- Commerce rules are not scattered through chat/session/project views.
- `AppViewModel` does not own paywall or usage state.
- Debug overrides are Debug-only.
- Tests cover gate and refund semantics.
