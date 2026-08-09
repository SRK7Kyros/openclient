# App Icon Customization

OpenClient lets people select an app icon from **Configurations > Appearance > App Icon**. The picker reads the icon names and generated image files from the built app's `CFBundleIcons` dictionary, so Swift code does not need to be updated when icon designs change.

## How It Works

- `AppIcon.icon` is the primary Icon Composer document.
- Every selectable alternate icon is a separate `.icon` document.
- `ASSETCATALOG_COMPILER_APPICON_NAME` identifies the primary icon.
- `ASSETCATALOG_COMPILER_ALTERNATE_APPICON_NAMES` identifies the alternate icons.
- Xcode generates `CFBundlePrimaryIcon` and `CFBundleAlternateIcons` in the built app's `Info.plist`.
- `AppIconStore` discovers those generated entries and changes the icon with `UIApplication.setAlternateIconName`.
- iOS persists the selected icon. OpenClient does not duplicate that selection in `UserDefaults`.

Light, dark, and tinted appearances inside one Icon Composer document are system appearances of the same icon. They do not become separate choices in the app.

## Add An Alternate Icon

1. Create the design in Icon Composer.
2. Save it in the repository with a stable, descriptive filename such as `AppIcon-Blue.icon`.
3. Add the Icon Composer document to the `OpenCodeIOSClient` target sources in `project.yml`, beside `AppIcon.icon`:

```yaml
- path: AppIcon.icon
  buildPhase: resources
- path: AppIcon-Blue.icon
  buildPhase: resources
```

4. Add the filename without `.icon` to `ASSETCATALOG_COMPILER_ALTERNATE_APPICON_NAMES` under the `OpenCodeIOSClient` target's base settings:

```yaml
ASSETCATALOG_COMPILER_APPICON_NAME: AppIcon
ASSETCATALOG_COMPILER_ALTERNATE_APPICON_NAMES: "AppIcon-Blue"
ASSETCATALOG_COMPILER_INCLUDE_ALL_APPICON_ASSETS: NO
```

Explicit alternate icon names and `ASSETCATALOG_COMPILER_INCLUDE_ALL_APPICON_ASSETS` are alternative asset-catalog modes. Keep the latter set to `NO` when listing alternates explicitly; enabling both can produce `No applicable app icon found` warnings and unreliable icon switching.

Use a space-separated list when adding more than one icon:

```yaml
ASSETCATALOG_COMPILER_ALTERNATE_APPICON_NAMES: "AppIcon-Blue AppIcon-Orange AppIcon-Mono"
```

5. Regenerate the Xcode project:

```bash
INCLUDE_PROJECT_LOCAL_YAML=1 xcodegen generate
```

The configured XcodeGen post-generation script updates `.icon` file references to Xcode 26's `folder.iconcomposer.icon` type. This is required for alternate Icon Composer documents to compile; the current XcodeGen release otherwise emits the older `wrapper.icon` type.

6. Build and open **Configurations > Appearance > App Icon**. The new icon should appear automatically.

Do not manually add or edit `CFBundleIcons`, `CFBundlePrimaryIcon`, or `CFBundleAlternateIcons` in `Generated-Info.plist`. Apple expects Xcode to generate those entries from the app icon build settings.

## Customize Display Names

By default, the picker turns an icon name such as `midnightGlow` into `Midnight Glow`. To provide an explicit title, add `OpenClientAlternateIconDisplayNames` to the app target's `info.properties` in `project.yml`:

```yaml
OpenClientAlternateIconDisplayNames:
  AppIcon-Blue: Ocean
  AppIcon-Orange: Sunset
  AppIcon-Mono: Monochrome
```

The dictionary keys must match the names in `ASSETCATALOG_COMPILER_ALTERNATE_APPICON_NAMES` exactly.

## Add Picker Preview Images

Icon Composer app-icon renditions aren't safely loadable through `UIImage(named:)`. Export a flattened PNG for each alternate icon and add it as an ordinary app resource:

```yaml
- path: AppIcon-Blue.png
  buildPhase: resources
  group: OpenCodeIOSClient
```

Map the alternate icon name to its preview filename in the app target's `info.properties`:

```yaml
OpenClientAlternateIconPreviewFiles:
  AppIcon-Blue: AppIcon-Blue.png
```

OpenClient loads these files directly from the app bundle. The dictionary key must match the alternate icon name exactly.

## Verify The Built App

Build for a simulator:

```bash
xcodebuild -quiet \
  -project OpenCodeIOSClient.xcodeproj \
  -scheme OpenCodeIOSClient \
  -sdk iphonesimulator \
  build
```

Inspect the built app's generated plist:

```bash
plutil -p "<derived-data>/Build/Products/Debug-iphonesimulator/OpenClient.app/Info.plist"
```

Confirm that:

- `CFBundleIcons.CFBundlePrimaryIcon` contains `AppIcon`.
- `CFBundleIcons.CFBundleAlternateIcons` contains every configured alternate name.
- `Assets.car` contains a `MultiSized Image` entry for every Icon Composer name.
- `UIApplication.shared.supportsAlternateIcons` is true on the test device.

Inspect the compiled asset catalog when needed:

```bash
xcrun assetutil --info "<derived-data>/Build/Products/Debug-iphonesimulator/OpenClient.app/Assets.car"
```

The system displays its own confirmation alert after a successful icon change. That alert is expected.

## Rename Or Remove An Icon

Icon names are persisted by iOS, so keep names stable after shipping when possible.

To rename an icon:

1. Rename the `.icon` document.
2. Update its `path` in `project.yml`.
3. Update `ASSETCATALOG_COMPILER_ALTERNATE_APPICON_NAMES`.
4. Update `OpenClientAlternateIconDisplayNames` if present.
5. Regenerate and rebuild the project.

Before removing a shipped alternate icon, switch test devices back to the primary icon and verify upgrade behavior from the previous release.

## Troubleshooting

### Only Default Appears

- Confirm the alternate `.icon` document is included in `project.yml` with `buildPhase: resources`.
- Confirm its extension-free name is in `ASSETCATALOG_COMPILER_ALTERNATE_APPICON_NAMES`.
- Regenerate the Xcode project after editing `project.yml`.
- Confirm the generated project identifies each `.icon` file as `folder.iconcomposer.icon`.
- Inspect the built app's `Info.plist`, not the source `Generated-Info.plist`.

### The Picker Shows An Icon But Changing It Fails

- Test on iOS or iPadOS rather than the macOS target.
- Confirm `UIApplication.shared.supportsAlternateIcons` is true.
- Confirm the picker name exactly matches a key under generated `CFBundleAlternateIcons`.
- Delete and reinstall the app after changing icon build settings if an old development build is cached.

### The Preview Is Missing

- Icon Composer alternates are compiled as `MultiSized Image` entries in `Assets.car` and may omit `CFBundleIconFiles`.
- Confirm the flattened PNG is included as a resource in `project.yml`.
- Confirm `OpenClientAlternateIconPreviewFiles` maps the alternate name to the exact PNG filename.
- OpenClient shows a labeled fallback tile when no ordinary preview file is available.
- Confirm `Assets.car` contains the affected icon name.
- Verify the Icon Composer document supports iOS square icons.
