# Localization

OpenClient uses Xcode String Catalogs for the app, App Shortcuts, widgets and Live Activities, the share extension, and Info.plist privacy copy.

## Required Languages

- English (`en`) is the source language.
- Brazilian Portuguese (`pt-BR`) is required for every catalog entry.

Update `REQUIRED_LANGUAGES` in `scripts/lint-localizations.rb` when another language becomes mandatory.

## Writing Localizable UI

- Pass fixed SwiftUI literals directly to localization-aware APIs such as `Text`, `Label`, `Button`, and `navigationTitle`.
- Use `LocalizedStringResource` when fixed copy passes through a helper, model, facade, or ternary.
- Use `String(localized:)` when UIKit, AppKit, errors, snapshots, or another String-only API requires a concrete value.
- Keep user, server, file, path, code, model, agent, and command data verbatim.
- Localize complete interpolated phrases rather than joining translated fragments.
- Handle singular and plural grammar explicitly.

## Validation

Run the fast check directly:

```bash
ruby scripts/lint-localizations.rb
```

Run the full compiler-extraction check through Fastlane:

```bash
fastlane ios lint_localizations
```

The check rejects:

- Missing required-language translations
- Incomplete translations
- Stale catalog entries
- Placeholder mismatches
- New direct UIKit/AppKit UI string literals

Normal app builds also compare Swift compiler `.stringsdata` with the tracked catalogs. A localization-aware source string that is not in its target's catalog fails the build with the missing key.

After changing source copy, synchronize the affected catalog from compiler output, translate every required language, and rerun the build.
