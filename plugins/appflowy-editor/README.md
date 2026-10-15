# AppFlowy Editor MCP App

Third-party plugin based on AppFlowy Editor 6.2.0 (MPL-2.0). The plugin communicates with any compatible host using MCP Registry, MCP Bundle, MCP Streamable HTTP, MCP Apps and standard `resource_link` content. There are no imports from Muse-Client.

- `web/`: Flutter Web editor, mobile responsive, autosave in browser storage, AppFlowy JSON export.
- `vendor/appflowy_editor/`: upstream source and license, with the single Flutter 3.44 input callback compatibility patch.
- `src/`: independent stdio and HTTP MCP servers.
- `scripts/`: deterministic MCPB packaging and Registry submission.
- `test/`: standard MCP client tests.

```sh
cd web && flutter pub get && flutter build web --release --no-wasm-dry-run --base-href /editor/
cd .. && npm ci && npm run build && npm run build:http && npm test
python3 scripts/pack.py --editor-url https://plugin.example/editor/
PORT=8768 EDITOR_PUBLIC_URL=http://127.0.0.1:8768/editor/ node dist/http.mjs
```

The Desktop bundle's default editor URL is loopback for local testing. Build a production bundle with the deployed HTTPS editor URL and publish that exact digest and version. Once approved, the same Registry record is installable on macOS via MCPB and on Android via remote MCP.
