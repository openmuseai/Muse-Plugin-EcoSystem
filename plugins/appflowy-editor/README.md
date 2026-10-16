# AppFlowy Editor MCP App

Third-party plugin based on AppFlowy Editor 6.2.0 (MPL-2.0). The plugin communicates with any compatible host using MCP Registry, MCP Bundle, MCP Streamable HTTP, MCP Apps and standard `resource_link` content. There are no imports from Muse-Client.

- `web/`: Flutter Web Wasm editor with JavaScript fallback, mobile responsive, autosave in application WebView storage, AppFlowy JSON export. The build pins and bundles Flutter's fallback fonts for offline rendering.
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

The Desktop bundle's default editor URL is loopback for local testing. Build a production bundle with the deployed HTTPS editor URL and publish that exact digest and version. The MCPB also contains the built `web/` site. Android verifies the MCP Registry `fileSha256`, extracts the site into application-private storage and launches it in an in-app WebView without connecting to the editor server at use time. The site includes Flutter Web Wasm and JavaScript fallback; it is not a standalone native Wasm plugin. The `web/` layout is a documented static-site packaging profile within an ordinary MCPB archive, not a private Registry field or a claim that base MCPB defines Mobile execution.

Version 0.1.4 adds a Markdown file editor contribution discovered through the standard MCP tool input JSON Schema and HTML `resource_link` result. See [the lifecycle guide](LIFECYCLE.zh-CN.md) for packaging, upload, review, macOS and Android acceptance, delisting, and the current Workspace writeback limit.
