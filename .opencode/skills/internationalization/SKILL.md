---
name: internationalization
description: Implement and review OpenClient internationalization, localization, String Catalogs, user-facing copy, plurals, App Shortcuts, widgets, Live Activities, share UI, and Info.plist strings. Use whenever adding or changing visible text, adding a language, fixing untranslated UI, or validating localization completeness.
---

# OpenClient Internationalization

Use this skill whenever a feature adds or changes user-facing text. Localization is part of the feature implementation, not follow-up work.

## Sources Of Truth

- English (`en`) is the source language.
- Read `REQUIRED_LANGUAGES` in `scripts/lint-localizations.rb` for the languages every catalog entry must include. Brazilian Portuguese (`pt-BR`) and Italian (`it`) are currently required.
- Read `LOCALIZATION.md` for the repository workflow and conventions.
- Use the Swift compiler's emitted `.stringsdata` as the authoritative inventory of localization-aware Swift strings.
- Keep `project.yml` authoritative for target resources and Info.plist values. Regenerate the project after adding or removing catalog or source files.

## Required Catalog Coverage

Keep these target-specific catalogs complete:

- `OpenCodeIOSClient/Localizable.xcstrings`: main iOS/macOS UI, dialogs, errors, accessibility copy, and AppIntent metadata.
- `OpenCodeIOSClient/AppShortcuts.xcstrings`: App Shortcut invocation phrases.
- `OpenCodeIOSClient/InfoPlist.xcstrings`: app display name and privacy usage descriptions.
- `OpenCodeChatActivityExtension/Localizable.xcstrings`: widgets, controls, and Live Activity UI.
- `OpenCodeChatActivityExtension/InfoPlist.xcstrings`: extension display name.
- `OpenCodeShareExtension/Localizable.xcstrings`: share-extension UI and accessibility copy.
- `OpenCodeShareExtension/InfoPlist.xcstrings`: share-extension display name.

Do not put extension UI strings only in the app catalog. Each extension resolves strings from its own bundle.

## Choose The Correct API

### SwiftUI literals

Pass fixed literals directly to localization-aware SwiftUI APIs:

```swift
Text("Projects")
Button("Save") { save() }
Label("Delete", systemImage: "trash")
```

### Fixed copy carried through helpers or state

Use `LocalizedStringResource` rather than `String`:

```swift
struct EmptyState {
    let title: LocalizedStringResource
}
```

This applies to fixed titles in helper views, stores, facades, models, menus, ternaries, widget views, and AppIntent declarations.

### String-only APIs

Use `String(localized:)` at UIKit, AppKit, `LocalizedError`, snapshot, or persistence boundaries that require a concrete `String`:

```swift
label.text = String(localized: "Preparing share...")
```

Do not call `String(localized:)` with arbitrary runtime user or server values.

### Dynamic content

Keep these verbatim unless they are wrapped by a complete localized phrase:

- User and assistant messages
- Server-provided session, project, model, agent, command, tool, provider, and MCP names
- File names, paths, branches, code, terminal output, URLs, JSON, and API values
- Protocol tokens, status raw values, identifiers, and persisted semantic values

Localize presentation derived from semantic values, not the raw value used for logic. Never make protocol output, cache keys, filesystem paths, or status comparisons locale-dependent.

## Interpolation And Grammar

- Localize one complete phrase so translators can reorder arguments.
- Never assemble sentences from separately translated fragments.
- Preserve every placeholder and its argument type.
- Handle singular and plural grammar explicitly. Do not append an English `s`.
- Prefer locale-aware date, number, percent, currency, byte-count, list, and relative-time formatting.
- Add translator comments for ambiguous labels and interpolated arguments.

Example:

```swift
if count == 1 {
    Text("1 task")
} else {
    Text("\(count) tasks")
}
```

## Feature Workflow

1. Inventory every new visible string across the app, widgets, Live Activities, share extension, App Shortcuts, accessibility, errors, and Info.plist prompts.
2. Refactor fixed `String` values to localization-aware types before translating.
3. Build with `SWIFT_EMIT_LOC_STRINGS=YES` so the compiler emits the authoritative keys.
4. Synchronize the affected target catalog from its `.stringsdata` files.
5. Add every language listed in `REQUIRED_LANGUAGES`.
6. Review translations in context, including singular counts, completed/in-progress states, tool headers, menus, and accessibility labels.
7. Run both localization checks below.
8. For user-visible work, install on the iPhone and test with a persistent per-app language selection when system-owned UI such as Shortcuts is involved.

## Validation Commands

Run the fast catalog and source check:

```bash
ruby scripts/lint-localizations.rb
```

Run the full compiler-extraction check:

```bash
LANG=en_US.UTF-8 LC_ALL=en_US.UTF-8 fastlane ios lint_localizations
```

The full check regenerates the Xcode project, builds all shipping iOS bundles, and fails when compiler-emitted keys are absent from a tracked catalog.

Normal app builds also run compiler-extraction localization lint as an Xcode post-build phase.

## Project Generation

After adding or removing source/catalog files, regenerate with the local signing override on this machine:

```bash
INCLUDE_PROJECT_LOCAL_YAML=1 /Users/mininic/.local/bin/xcodegen generate
```

Do not hand-edit the generated project to add catalog membership.

## Device And System UI Testing

- Set a persistent language at `Settings -> Apps -> OpenClient -> Preferred Language`.
- Launch arguments such as `-AppleLanguages` affect the app process but do not reliably update system-owned App Shortcuts metadata.
- After changing AppIntent or App Shortcut translations, open OpenClient once, then force-quit and reopen Shortcuts. iOS may cache action metadata until the app language or build changes.
- Verify the app, widgets, Live Activity, share sheet, privacy prompts, and Shortcuts separately because they use different bundles or system caches.

## Completion Checklist

- Every fixed user-facing string uses a localization-aware API.
- Every catalog entry includes every required language with `translated` state.
- No catalog entry is stale or blank.
- Placeholders retain their argument indexes and types.
- Counts are grammatically correct for one and many.
- Dynamic server/user content remains verbatim.
- Semantic protocol and persistence values remain locale-independent.
- `ruby scripts/lint-localizations.rb` passes.
- `fastlane ios lint_localizations` passes.
- Relevant on-device surfaces have been checked in the target language.
