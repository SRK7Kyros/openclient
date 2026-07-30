# Mini App Runtime Specification

## Package Layout

Each Mini App is a directory under the app-owned Documents folder:

```text
On My iPhone/
  OpenClient/
    Mini Apps/
      release-dashboard/
        miniapp.json
        screens/
          home.json
          release.json
          settings.json
        data/
          defaults.json
        assets/
          icon.png
        credentials.json
```

Source files are user-visible and portable. Runtime state, caches, revision snapshots, and credentials do not live in this directory.

## Manifest

`miniapp.json` is the package entry point.

```json
{
  "schemaVersion": 1,
  "id": "release-dashboard",
  "name": "Release Dashboard",
  "version": "0.1.0",
  "minimumRuntimeVersion": 1,
  "icon": {
    "systemName": "shippingbox.fill",
    "tint": "#7C5CFC"
  },
  "initialScreen": "home",
  "screens": [
    "home",
    "release",
    "settings"
  ],
  "capabilities": {
    "network": {
      "allowedHosts": [
        "api.github.com"
      ]
    },
    "share": true,
    "notifications": false
  },
  "credentials": [
    {
      "id": "github-token",
      "label": "GitHub Token",
      "required": false
    }
  ]
}
```

Version fields have separate meanings:

- `schemaVersion`: Mini App package format.
- `minimumRuntimeVersion`: Oldest OpenClient Mini App runtime that can render it.
- `version`: User-facing version of this Mini App.

## Component Catalog

The runtime exposes versioned component descriptors. A descriptor contains:

- Stable component ID.
- Category and description.
- Runtime version where it was introduced.
- JSON schema for props.
- Supported events.
- Supported child slots.
- Capability requirements, if any.

Example:

```json
{
  "id": "textField",
  "category": "forms",
  "description": "Editable single-line text input.",
  "sinceRuntimeVersion": 1,
  "props": {
    "label": {
      "type": "string",
      "required": true
    },
    "value": {
      "type": "binding",
      "required": true
    },
    "placeholder": {
      "type": "string"
    },
    "secure": {
      "type": "boolean",
      "default": false
    }
  },
  "events": [
    "change",
    "submit"
  ]
}
```

Catalog discovery should support query, category, component ID, and runtime-version filters. The complete catalog should not be returned when a narrower query is available.

## Initial Component Set

### Layout

- `screen`
- `scrollView`
- `stack`
- `grid`
- `section`
- `divider`
- `spacer`

### Navigation

- `navigationStack`
- `tabView`
- `navigationLink`
- `sheet`
- `alert`

### Display

- `text`
- `markdown`
- `symbol`
- `image`
- `badge`
- `progress`
- `chart`
- `map`

### Input

- `button`
- `textField`
- `secureField`
- `toggle`
- `picker`
- `datePicker`
- `slider`

### Data

- `list`
- `form`
- `emptyState`

Existing OpenClient chart and map renderers should be reused where practical.

## Screens

Each screen is a declarative component tree.

```json
{
  "schemaVersion": 1,
  "id": "home",
  "title": "Releases",
  "body": {
    "type": "navigationStack",
    "children": [
      {
        "type": "scrollView",
        "children": [
          {
            "type": "stack",
            "props": {
              "axis": "vertical",
              "spacing": 16
            },
            "children": [
              {
                "type": "text",
                "props": {
                  "value": "Latest OpenCode releases",
                  "style": "title"
                }
              },
              {
                "type": "button",
                "props": {
                  "title": "Load Releases"
                },
                "actions": {
                  "tap": [
                    {
                      "type": "request",
                      "request": "github-releases",
                      "assign": "state.releases"
                    }
                  ]
                }
              }
            ]
          }
        ]
      }
    ]
  }
}
```

Unknown components, props, actions, or bindings are validation errors. The runtime should never silently ignore behavior-bearing fields.

## Bindings

Version one should use explicit path bindings rather than a general expression language.

Supported roots can include:

- `state.*`: Mutable runtime state.
- `defaults.*`: Read-only package defaults.
- `navigation.*`: Current navigation context.
- `request.*`: Results and status for named requests.
- `environment.*`: Safe runtime values such as locale and color scheme.

Credential values are never exposed through bindings.

Examples:

```json
{
  "type": "textField",
  "props": {
    "label": "Repository",
    "value": {
      "binding": "state.repository"
    }
  }
}
```

```json
{
  "type": "text",
  "props": {
    "value": {
      "binding": "state.release.name",
      "fallback": "No release selected"
    }
  }
}
```

## Actions

The action language must remain small, explicit, ordered, and capability-aware.

Initial actions:

- `setState`
- `navigate`
- `dismiss`
- `presentSheet`
- `showAlert`
- `request`
- `copy`
- `share`
- `openURL`
- `saveLocalData`
- `resetLocalData`

Example:

```json
{
  "type": "button",
  "props": {
    "title": "Load Releases"
  },
  "actions": {
    "tap": [
      {
        "type": "request",
        "request": "github-releases",
        "assign": "state.releases"
      },
      {
        "type": "navigate",
        "screen": "release"
      }
    ]
  }
}
```

Actions execute sequentially unless a future schema explicitly introduces concurrency. Sensitive native actions remain subject to capability declarations and user confirmation.

## Requests

Network requests are named manifest resources rather than arbitrary executable expressions.

```json
{
  "id": "github-releases",
  "method": "GET",
  "url": "https://api.github.com/repos/anomalyco/opencode/releases",
  "headers": {
    "Authorization": {
      "credential": "github-token",
      "format": "Bearer {value}"
    }
  }
}
```

Rules:

- The URL host must be declared in `allowedHosts`.
- Redirects must remain within allowed hosts unless explicitly approved.
- Credential values are injected by the runtime and never enter app state.
- Request and response sizes are bounded.
- Logs redact authorization headers and credential-derived values.

## State And Persistence

Version one should provide a JSON-compatible key-value state model.

State categories:

- Ephemeral screen state.
- Session state retained while the Mini App is open.
- Persisted local state retained across launches.
- Request cache with explicit expiration.

Runtime state belongs under Application Support rather than the Files-visible source package.

## Drafts And Revisions

AI edits target a draft revision. Publication is transactional:

1. Copy or create draft source.
2. Apply edits atomically.
3. Validate the entire package.
4. Preview the draft.
5. Publish the validated revision.
6. Retain the previous active revision as last known-good.

A malformed Files-app edit should mark the source invalid without destroying the active known-good runtime snapshot.

## Validation

Validation covers:

- Manifest schema and versions.
- Package and path integrity.
- Screen and component schemas.
- Component availability for the requested runtime version.
- Binding paths and state declarations.
- Navigation destinations.
- Action definitions.
- Capability declarations.
- Request hosts and credential references.
- Asset existence, type, and size.
- Package limits.

Diagnostics are file-oriented and machine-readable:

```json
{
  "valid": false,
  "diagnostics": [
    {
      "severity": "error",
      "file": "screens/home.json",
      "path": "$.body.children[2].props.value",
      "message": "Unknown binding: state.release"
    }
  ]
}
```

## Runtime Presentation

The same runtime instance should support:

- Full launch from OpenClient Home.
- Deep-link and App Intent launch.
- Collapsed chat dock.
- Expanded chat preview sheet.
- Completed tool-result preview card.

Presentation is separate from execution. Background Mini App editing and validation should not automatically expand UI. An explicit presentation tool expands the preview and provides an instruction.
