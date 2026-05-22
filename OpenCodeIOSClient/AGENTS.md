# OpenCodeIOSClient Notes

## Architecture Direction

This app's intended architecture is focused SwiftUI-friendly MVVM with state stores and coordinators. The existing large `AppViewModel` is legacy compatibility glue to shrink over time.

Use this mental model for new work:

- `Models/` defines OpenCode/domain/server types and reducer semantics. These files describe server truth and should stay aligned with upstream OpenCode concepts and server payloads. App-only preference, game, persistence, or feature-local models should move toward their owning feature/store rather than accumulating here.
- `Stores/` contains focused observable state containers. These adapt models into `@Published` state, derived values, and invariant-preserving mutations that SwiftUI can consume.
- `Coordinators/` are glue for async workflows. They prepare outgoing network intent, call API clients when sequencing feature actions, interpret responses, route events, and hand results back to stores or the app facade.
- `Views/` contains SwiftUI presentation. Views render observable state and send user intent upward; they should not become canonical state owners.
- `API/` owns transport, event streams, and bootstrap fetching. Keep request encoding, SSE parsing, and raw server communication here rather than in views or stores.
- `ViewModels/AppViewModel/` is legacy compatibility glue from the original large app view model. Do not expand it as a model layer; shrink it over time by moving canonical state into focused stores and procedural workflow logic into coordinators.

## Guiding Principle

New canonical state should usually live in a focused store, not in `AppViewModel`. New network orchestration should usually live in a coordinator or API/bootstrap type, not in a view or store.

Reducers in `Models/` are allowed to contain domain state transition logic because they encode OpenCode sync semantics. Prefer extending reducers over duplicating event mutation rules in stores, coordinators, or views.

Keep the mental model for consuming API data close to the upstream OpenCode web UI. The upstream web app is maintained by the team with the best visibility into server behavior and future API changes, so its bootstrap phases, event flow, reducer semantics, and source-of-truth boundaries should be treated as the default reference before inventing iOS-only data handling.

## Practical MVVM Shape

This is pragmatic SwiftUI MVVM, not textbook MVVM. Stores are the app's feature view-model state surfaces, coordinators are application/service orchestrators, and `AppViewModel` is temporary root facade glue while call sites migrate.

When in doubt, preserve this flow:

1. Views render store/facade state and report user intent.
2. `AppViewModel` bridges existing call sites and invokes coordinators or store methods.
3. Coordinators prepare requests, sequence async work, and return explicit results.
4. API/bootstrap/event-stream types communicate with the OpenCode server.
5. Reducers and stores apply canonical state changes.

When this flow is ambiguous, inspect upstream OpenCode web code before adding a local interpretation of server data.
