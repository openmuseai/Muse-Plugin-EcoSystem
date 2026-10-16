# AppFlowy Editor MCP App

Third-party plugin based on AppFlowy Editor 6.2.0 (MPL-2.0). The plugin communicates with any compatible host using MCP Registry, MCP Bundle, MCP Streamable HTTP, MCP Apps and standard `resource_link` content. There are no imports from Muse-Client.

- `web/`: Flutter Web Wasm editor with JavaScript fallback, mobile responsive, autosave in application WebView storage, AppFlowy JSON export. The build pins and bundles Flutter's fallback fonts for offline rendering.
- `flutter_editor/`: standalone native Flutter package for macOS. It renders AppFlowy Editor directly in the host's Flutter tree and reads and saves an explicitly granted Markdown file. It imports no Muse-Client code or private protocol fields.
- `vendor/appflowy_editor/`: upstream source and license, with Flutter 3.44 input callback and Wasm-compatible browser API patches.
- `src/`: independent stdio and HTTP MCP servers.
- `scripts/`: deterministic MCPB packaging and Registry submission.
- `test/`: standard MCP client tests.

```sh
cd web && flutter pub get && cd .. && npm ci && npm run build:web
npm run build && npm run build:http && npm test
python3 scripts/pack.py --editor-url https://plugin.example/editor/
PORT=8768 EDITOR_PUBLIC_URL=http://127.0.0.1:8768/editor/ node dist/http.mjs
```

The Desktop MCPB supplies standard Registry identity and a tool with JSON Schema `contentMediaType: text/markdown`. A compatible macOS distribution may compile `flutter_editor/` into its AOT application and activate that native renderer only while this marketplace plugin is installed. Flutter release apps cannot load a newly downloaded Dart widget at runtime, so native renderer additions require a new macOS app build. The MCP tool's HTML resource link remains available for hosts without the native renderer. Android verifies the MCP Registry `fileSha256`, extracts the built `web/` site into application-private storage and launches it in an in-app WebView without connecting to the editor server at use time. The site includes Flutter Web Wasm and JavaScript fallback; it is not a standalone native Wasm plugin. The `web/` layout is a documented static-site packaging profile within an ordinary MCPB archive, not a private Registry field or a claim that base MCPB defines Mobile execution.

Version 0.1.5 lets an embedding host deliver a browser-standard `File` object with `window.postMessage` to the offline editor. A host can cache the standard MCP tool input JSON Schema `contentMediaType` at installation, choose a local editor for a Markdown resource, and pass the file only after selection. This handoff uses no client-specific message fields or online MCP call on each file open. See [the lifecycle guide](LIFECYCLE.zh-CN.md) for packaging, upload, review, macOS and Android acceptance, delisting, and the current Workspace writeback limit.
