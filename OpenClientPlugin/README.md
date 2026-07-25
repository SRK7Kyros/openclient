# OpenClient Plugin

Server-side OpenCode extensions used by the OpenClient iOS app.

The plugin is loaded locally from `src/index.ts` through the repository's
`opencode.json`. OpenCode must be restarted after changing plugin code.

## Development

```bash
npm install
npm run check
npm run build
```

Add hooks and tools to the object returned by `OpenClientPlugin` in
`src/index.ts`.

Plugin documentation: <https://opencode.ai/docs/plugins/>
