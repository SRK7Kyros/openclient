# Mac Tests Notes

## Responsibility

`OpenCodeMacClientTests/` currently covers macOS-specific and Apple Intelligence integration behavior.

These tests may depend on platform availability and local model readiness, so they should skip cleanly when requirements are not met.

## Apple Intelligence

Keep Apple Intelligence tests explicit about availability checks, locale support, prompt text, and transcript logging. The local workspace mode is app-specific and should not be confused with OpenCode server sync semantics.

As Apple Intelligence behavior moves out of `AppViewModel`, migrate these tests toward focused Apple Intelligence stores/services/facades.

## Do / Avoid

Do use temporary workspaces and clean deterministic fixture files.

Do keep prompts narrow enough that assertions can be reliable.

Avoid making these tests required on machines or OS versions where Foundation Models are unavailable.
