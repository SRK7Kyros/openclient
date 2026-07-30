# Mini Apps Roadmap

## Phase 0: Runtime Decisions

Resolve the foundational choices before implementation:

- Final package and screen schema shape.
- Runtime and package versioning policy.
- Initial component catalog.
- Binding syntax.
- Initial action set.
- Draft, revision, and publication model.
- Files app integration behavior.
- Maximum package limits.
- Local Home navigation placement.

Deliverables:

- JSON schemas checked into the repository.
- Example packages covering navigation, forms, lists, and local state.
- Validator fixtures for valid and invalid packages.

## Phase 1: Local Offline Runtime

Build the complete authoring and execution loop without networking or credentials.

Scope:

- App-owned Mini Apps Documents directory.
- Manifest and screen parsing.
- Approximately 15 core native components.
- Explicit bindings and local state.
- Multi-screen navigation.
- Scoped read, write, search, and patch tools.
- Component discovery tool.
- Full-package validator.
- Draft and last-known-good revisions.
- Dockable in-chat preview.
- Local Mini Apps Home available without server connection.
- Package import and export.

Acceptance criteria:

- AI can create a multi-screen checklist app through tools.
- The user can preview and publish it.
- The app remains available after OpenCode disconnects and OpenClient relaunches.
- Invalid source edits do not break the active known-good revision.
- VoiceOver can navigate all shipped components.

## Phase 2: Native Data And Capabilities

Scope:

- Host-allowlisted HTTP requests.
- Keychain credential declarations and native credential-entry UI.
- Request loading, error, and cache state.
- Chart and map components.
- Share sheet.
- Clipboard write.
- File and photo picker handoff.
- Optional local notifications.

Acceptance criteria:

- A release dashboard can call GitHub using an optional Keychain token.
- Credential values never appear in package source, tool output, logs, or state.
- Network requests fail safely outside declared hosts.
- Capability use is visible and user-controlled.

## Phase 3: System Launch Surfaces

Scope:

- `Open Mini App` App Intent.
- Deep-link routing.
- Configurable Mini Apps widget.
- Shortcuts actions for opening apps and invoking approved actions.
- Recent Mini Apps suggestions.

Acceptance criteria:

- A user can add a Shortcut for one Mini App to the iOS Home Screen.
- The Mini App opens directly without requiring a server connection.
- Invalid or deleted app IDs show a safe recovery screen.

## Phase 4: Advanced Runtime

Potential scope:

- More component categories.
- Local database collections.
- Background refresh for narrowly approved use cases.
- Camera, scanner, OCR, and location components.
- Mini App widgets.
- Richer conditional rendering without a general executable language.
- Package signing and trusted imports.

These features should follow real Mini App use cases rather than being added speculatively.

## Deferred Decisions

- Public package sharing or marketplace.
- Remote package installation.
- Collaboration and source synchronization.
- Monetization.
- Arbitrary HTML or JavaScript components.
- Third-party native component plugins.
- General expression or scripting language.
- Background jobs.

## Open Product Questions

1. Does publishing always require explicit user confirmation, or can a remembered permission allow AI publication for one Mini App?
2. Should Files edits automatically create drafts, or should the app treat the Files package as the draft itself?
3. How many known-good revisions should remain locally?
4. Should runtime state be included when exporting a package?
5. Can one Mini App deep-link into another?
6. Should Mini Apps have per-app color schemes and typography, or only semantic native styling?
7. Which capabilities should remain unavailable even with user consent?
8. Should a Mini App be scoped globally, per server, or optionally per project?
9. How should package migrations work when runtime schemas evolve?
10. Should AI tools edit JSON directly or optionally use a higher-level document format compiled into JSON?

## Suggested First Examples

Build these fixtures early because they exercise different runtime boundaries:

- Offline packing checklist: Local state, forms, and persistence.
- Standup tracker: Multi-screen navigation and editable lists.
- Release dashboard: Network requests, optional credential, and list/detail navigation.
- Workout logger: Dates, numeric input, charts, and local persistence.
- Nearby places: Location permission and map rendering.

The packing checklist should be the first end-to-end implementation because it proves the runtime without introducing networking or credential complexity.
