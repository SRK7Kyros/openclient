---
name: simulator-device-policy
description: Enforce the project's Xcode and simulator device policy for every iOS Simulator build, test, UI test, screenshot, preview, install, launch, or manual verification. Use whenever xcodes, Xcode selection, any simulator, simctl, xcodebuild iphonesimulator destination, or simulated-device workflow is involved.
---

# Simulator Device Policy

Use only these two simulator classes for all simulator work in this project:

- The newest available 6.9-inch iPhone Pro Max on the newest installed iOS runtime.
- The newest available 13-inch iPad Pro on the newest installed iOS runtime.

Every simulator validation must cover both classes unless the user explicitly requests only one of them. Never substitute a smaller iPhone, iPhone Air, iPad Air, iPad mini, generic simulator, currently booted simulator, or an older device merely because it is already available or booted.

This policy applies to all simulator usage, including builds, unit tests, UI tests, screenshots, app installation and launch, accessibility inspection, performance checks, and manual interaction.

## Select The Latest Xcode First

Before inspecting runtimes or running the first simulator command in a task, use `xcodes` to inspect and select the newest installed Xcode:

```bash
xcodes installed
xcodes select <newest-installed-xcode-version-or-absolute-app-path>
```

Use an explicit version or absolute app path so the command never opens an interactive picker. Include beta or release-candidate Xcode versions when they are the newest installed version and are required for the newest installed iOS runtime. Prefer the highest version, not whichever Xcode happens to be selected already.

At the time this skill was written, the newest installed Xcode is selected with:

```bash
xcodes select /Applications/Xcode-beta.app
```

Treat that path as a current example. Resolve it again from `xcodes installed` rather than permanently assuming it.

Verify that selection succeeded before proceeding:

```bash
xcodes select --print-path
xcode-select -p
xcodebuild -version
```

The selected developer directory must belong to the intended newest Xcode. Do not work around this policy by setting `DEVELOPER_DIR`, calling `sudo xcode-select` directly, or continuing with an older Xcode when `xcodes` is available.

If `xcodes select` requires administrator authorization that cannot be completed non-interactively, stop and report the exact command the user must authorize. Do not expose, request, or embed an administrator password. If the necessary Xcode is not installed, report the missing version; do not start a large Xcode installation unless the user explicitly requests it.

## Resolve The Current Devices

After selecting Xcode, do not permanently assume model names or UDIDs. Inspect the devices available to that Xcode:

```bash
xcrun simctl list devices available
```

Select devices using these rules:

1. Choose the highest installed iOS runtime version that contains both required device classes.
2. For iPhone, choose the newest `iPhone ... Pro Max` model with a 6.9-inch display.
3. For iPad, choose the newest `iPad Pro 13-inch (...)` model.
4. Use names with `OS=latest` for `xcodebuild` when both selected devices exist on the latest installed runtime.
5. Use the resolved UDIDs for `simctl` commands to avoid ambiguity across runtimes.

At the time this skill was written, the installed targets resolve to:

- `iPhone 17 Pro Max`, iOS 27.0
- `iPad Pro 13-inch (M5)`, iOS 27.0

Treat these as examples of the current resolution, not permanent hard-coded choices.

## Xcodebuild Destinations

Pass explicit destinations. Do not rely on `-sdk iphonesimulator` alone, `platform=iOS Simulator` alone, a generic destination, or Xcode's default device.

For work that supports a destination matrix, use both resolved destinations:

```bash
xcodebuild \
  -project OpenCodeIOSClient.xcodeproj \
  -scheme OpenCodeIOSClient \
  -destination 'platform=iOS Simulator,name=iPhone 17 Pro Max,OS=latest' \
  -destination 'platform=iOS Simulator,name=iPad Pro 13-inch (M5),OS=latest' \
  test
```

Replace the example names when discovery identifies newer qualifying models. If a command can target only one device at a time, run it once for each resolved device.

## Boot, Install, And Launch

Use the resolved UDID, not `booted`, because another simulator may already be running:

```bash
xcrun simctl boot <resolved-udid>
xcrun simctl install <resolved-udid> <app-path>
xcrun simctl launch <resolved-udid> com.ntoporcov.openclient
```

Repeat device-specific operations for both required devices. It is acceptable to leave both simulators booted when the workflow benefits from it.

## Existing Commands And Automation

When a repository command, script, lane, or test configuration chooses a disallowed simulator:

- Override its destination when the tool supports an override.
- Otherwise update the project automation to follow this policy if doing so is within the user's requested scope.
- Do not silently run the disallowed destination.
- If the destination cannot be overridden or updated, stop and report the exact blocker.

## Availability Failure

If either required simulator class is unavailable on a common latest runtime, do not substitute another form factor. Report which runtime or device is missing and ask the user to install the required simulator runtime or device support.

## Final Report

State which iOS runtime and exact iPhone and iPad model were used. Report results for both devices separately when validation was performed on both.
