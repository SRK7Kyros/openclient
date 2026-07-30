# Mini App Tooling And Security

## Tooling Strategy

Prefer a small set of broad, package-scoped tools over one insertion tool per component. Component-specific mutation tools would grow quickly, couple authoring to the current schema, and make complex edits cumbersome.

The component catalog, scoped file operations, validator, and preview runtime provide enough structure for reliable AI authoring.

## Proposed Tools

### Component Discovery

`openclient_list_miniapp_components`

Filters:

- `query`
- `component_id`
- `category`
- `runtime_version`
- `limit`

Returns component IDs, descriptions, prop schemas, events, slots, capabilities, and runtime-version information.

### Package Management

`openclient_list_miniapps`

Returns installed apps, drafts, versions, validation status, and last-opened metadata.

`openclient_create_miniapp`

Creates a draft package with normalized identity and metadata. It does not accept credential values.

Suggested input:

```json
{
  "id": "release-dashboard",
  "name": "Release Dashboard",
  "version": "0.1.0",
  "schemaVersion": 1,
  "minimumRuntimeVersion": 1,
  "description": "Track recent releases for selected repositories."
}
```

`openclient_duplicate_miniapp`

Creates a new draft from an existing active or draft revision.

`openclient_delete_miniapp`

Requires explicit confirmation and supports deleting a draft separately from the active app.

### Source Editing

`openclient_read_miniapp_file`

Reads one UTF-8 source file from one Mini App package.

`openclient_write_miniapp_file`

Atomically replaces one source file after path and size validation.

`openclient_apply_miniapp_patch`

Applies a structured patch to source files and returns changed files plus validation diagnostics.

`openclient_search_miniapp`

Searches source files by text or regular expression with bounded results.

Avoid exposing unrestricted shell, `sed`, arbitrary filesystem paths, or symlink-following operations.

### Validation And Publication

`openclient_validate_miniapp`

Validates a draft or active package and returns structured diagnostics.

`openclient_publish_miniapp_draft`

Promotes a valid draft to the active revision. Invalid drafts cannot publish.

`openclient_restore_miniapp_revision`

Restores a known-good revision after explicit user confirmation.

### Presentation

`openclient_present_miniapp`

Shows a draft or active Mini App in the dockable chat runtime with a user-facing instruction.

`openclient_clear_miniapp_instruction`

Removes the instruction after the user review or input step is complete.

Presentation should follow the browser behavior:

- Activity creates a collapsed dock if no Mini App surface is visible.
- Background edits do not expand the runtime.
- Only explicit presentation expands it.
- Expanded runtime displays transient tool activity near its controls.
- The dock can be collapsed, expanded, and dismissed.

## Filesystem Boundary

All authoring tools are restricted to:

```text
Documents/OpenClient/Mini Apps/<normalized-miniapp-id>/
```

Required protections:

- Reject absolute paths.
- Reject `..` traversal.
- Reject symlinks and aliases.
- Normalize path separators and Unicode before authorization.
- Restrict file extensions.
- Bound file count, file size, asset size, and package size.
- Use coordinated, atomic writes.
- Never allow access to another Mini App package without naming it explicitly.
- Never expose Application Support, caches, Keychain, or unrelated Documents files.

Recommended initial limits:

- 100 source files per package.
- 256 KB per JSON or Markdown source file.
- 5 MB per asset.
- 25 MB total package size.
- 1,000 component nodes across all screens.
- 100 actions per screen.

Limits should be runtime-versioned and returned by component discovery.

## Storage Separation

### Documents

User-visible package source:

- Manifest.
- Screens.
- Default data.
- Assets.
- Credential declarations and references.

### Application Support

App-owned runtime data:

- Active compiled snapshots.
- Draft metadata.
- Revision history.
- Local persisted state.
- Request cache.
- Validation indexes.

### Keychain

- Credential values.
- Tokens.
- API keys.
- Refresh credentials.

## Credentials

Plaintext `.env` files in the Files app are not acceptable for secrets. Files-visible content is easy to share, copy, back up, or expose accidentally.

The source package declares credential requirements and stores only opaque references:

```json
{
  "github-token": "keychain://miniapp/release-dashboard/github-token"
}
```

Rules:

- AI may declare a credential requirement.
- AI may check whether a named credential is configured.
- AI may request native credential-entry UI.
- AI cannot read credential values.
- Credential values are never returned by tools, logs, bindings, or validation diagnostics.
- Credentials are injected only into declared request fields.
- Deleting a Mini App offers to delete its Keychain credentials separately.

## Capability Model

Capabilities are denied unless declared by the Mini App and supported by the runtime.

Potential capabilities:

- Network access to named hosts.
- Share sheet.
- Clipboard write.
- Notifications.
- Location.
- Photo or document picker.
- Camera and document scanning.
- Open external URL.

Sensitive capabilities require native user consent at use time. A manifest declaration is not user permission.

## Network Security

- Enforce HTTPS except explicitly supported local-development hosts.
- Enforce host allowlists before requests and redirects.
- Bound request and response bodies.
- Redact secrets from logs and diagnostics.
- Do not expose a general-purpose proxy.
- Do not allow arbitrary code to process credentials.
- Provide clear user-visible network and credential indicators.
- Consider per-app rate limits and cache limits.

## Runtime Security

- No arbitrary JavaScript evaluation.
- No downloaded Swift or native binaries.
- No shell commands.
- No dynamic library loading.
- No access outside the Mini App package and runtime state container.
- No unrestricted background execution.
- No silent notification, location, camera, microphone, or contacts access.
- No automatic publication of AI-generated drafts.

## App Store Posture

A first-party declarative component runtime is safer than downloaded executable logic. Mini Apps are locally authored structured content rendered through capabilities already shipped in OpenClient.

Keep version one local-only. Public discovery, remote package installation, monetization, and shared marketplaces introduce additional moderation, trust, privacy, and App Store policy requirements and should be separate future decisions.

## Auditing And Recovery

Every write and publish operation should record:

- Mini App ID.
- Draft or revision ID.
- Timestamp.
- Changed files.
- Validation result.
- Origin, such as user edit, Files edit, or OpenCode tool request.

Audit records must not contain credential values or full sensitive request bodies.

The runtime should always retain a recoverable known-good revision before activating a new one.
