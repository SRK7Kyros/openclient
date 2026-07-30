# OpenClient Mini Apps

## Vision

Mini Apps are local, AI-authored utilities rendered natively by OpenClient. They can be created while connected to OpenCode, then launched and used without a server connection.

Mini Apps should feel like small applications rather than chat artifacts:

- Native SwiftUI presentation and accessibility.
- Local-first storage and offline execution.
- Multi-screen navigation and persistent local state.
- Versioned, inspectable source files in the Files app.
- Safe access to approved native and network capabilities.
- Launchable from OpenClient Home, chat previews, deep links, Shortcuts, and widgets.

Mini Apps are declarative. OpenClient renders a versioned component tree using first-party runtime components. Mini Apps do not contain downloaded Swift, arbitrary JavaScript, shell scripts, or dynamically executable code.

## Product Principles

1. Local source, native runtime.
2. The OpenClient app remains in control of capabilities and side effects.
3. Credentials never live as plaintext in Mini App source.
4. AI edits happen in drafts and cannot corrupt the last known-good revision.
5. Validation precedes preview or publication.
6. The user can inspect, export, duplicate, repair, or delete every Mini App.
7. A Mini App created through chat remains useful after OpenCode disconnects.
8. Source files are portable, but runtime state and secrets remain separate.

## Core Architecture

OpenClient provides four layers:

- **Component catalog:** Versioned SwiftUI components and their JSON schemas.
- **Mini App source package:** Manifest, screens, actions, assets, and defaults.
- **Runtime:** Parsing, validation, bindings, navigation, state, capabilities, and rendering.
- **Authoring tools:** Scoped tools for component discovery, file editing, validation, preview, and publication.

The OpenCode server helps author Mini Apps but is not required to run them.

## User Surfaces

### OpenClient Home

Mini Apps should be available before server connection. The local Home surface should provide:

- Recently opened Mini Apps.
- Installed Mini Apps.
- Draft and validation indicators.
- Create and import actions.
- Duplicate, export, edit, and delete actions.

### Chat

The browser interaction model should be reused:

- AI edits a Mini App in the background.
- A collapsed dock appears when Mini App activity begins.
- An explicit presentation tool expands the Mini App.
- The presentation tool can show a user instruction.
- Tool activity is visible near the Mini App controls.
- The user can collapse, close, or reopen the preview.
- The AI can clear its instruction when the user step is complete.
- Completed tool parts can retain an Open Mini App card.

### iOS Home Screen

iOS cannot dynamically install independent application icons. Practical launch integrations are:

- An `Open Mini App` App Intent.
- User-created Shortcuts added to the Home Screen.
- Deep links such as `openclient://miniapp/release-dashboard`.
- A configurable Mini Apps widget.

## Authoring Lifecycle

1. Discover runtime components and capabilities.
2. Create or open a Mini App draft.
3. Read, search, write, or patch files inside that package.
4. Validate the complete package.
5. Present the draft in a dockable preview.
6. Test local state, navigation, and actions.
7. Publish the validated draft as the active revision.
8. Preserve the previous known-good revision for recovery.

## Documentation

- [Runtime specification](SPEC.md)
- [Tooling and security](TOOLS_AND_SECURITY.md)
- [Implementation roadmap](ROADMAP.md)

## Initial Product Decision

Mini Apps should be a native declarative runtime, not a second HTML browser. This gives them a clear purpose alongside the in-app browser and provides stronger native UX, accessibility, offline behavior, validation, and security.
