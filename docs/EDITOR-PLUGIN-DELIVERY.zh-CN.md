# AppFlowy Editor 插件交付与验证

## 交付边界

[AppFlowy Editor](https://github.com/AppFlowy-IO/appflowy-editor) 是 Flutter Widget。Flutter AOT 客户端不能在应用发布后装载下载的 Dart Widget，因此本插件将上游 6.2.0 编辑器编译成 Flutter Web，Desktop 和 Android 使用相同的远程编辑器界面。插件仓库内保留上游 MPL-2.0 许可证及最小源码副本，只补齐 Flutter 3.44 新增的 `TextInputClient.onFocusReceived` 方法。

Desktop 包是标准 MCPB，提供 `open_editor` 工具、`ui://` MCP Apps 资源和 HTML `resource_link`。Android 使用同一插件 ID 的 MCP Streamable HTTP endpoint。一个 `server.json` 同时列出 MCPB `packages` 与 HTTP `remotes`；客户端从标准字段选择可用交付，不需要客户端私有 manifest 或字段。MCP Apps 资源声明 `text/html;profile=mcp-app` 和 `_meta.ui.csp.frameDomains`；当前客户端通过标准 `resource_link` 打开隔离 WebView 或浏览器。编辑内容在当前设备浏览器存储中自动保存，可导出 AppFlowy JSON。

## 开发与发布

1. `cd plugins/appflowy-editor/web && flutter pub get && flutter build web --release --no-wasm-dry-run --base-href /editor/`
2. `cd .. && npm ci && npm run build && npm run build:http && python3 scripts/pack.py --editor-url https://plugin.example/editor/`
3. 部署 `web/build/web` 与 MCP Streamable HTTP 服务，生产地址使用 HTTPS。当前开发服务器在 `PORT=8768 node dist/http.mjs`，公开地址由 `EDITOR_PUBLIC_URL` 指定；Desktop MCPB 构建时必须将该地址固定为可用的公开 HTTPS 地址。
4. `python3 scripts/publish.py --registry https://market.example --token ... --remote https://plugin.example/mcp`
5. 审核者在独立 `/admin` 控制台检查元数据、包与实机 TCK，然后批准。下架后目录和包下载即刻隐藏；已安装包继续在本机存在。

## 验证记录（2026-10-16）

- Rust 服务：SQLite/files 流程、PostgreSQL/MinIO/Redis 流程均通过上传、审核、公开目录、下载、下架、重新上架。
- MCP 兼容：Node 标准客户端通过 stdio 与 Streamable HTTP 读取工具、MCP Apps 资源和 `resource_link`。
- macOS：Flutter 集成测试从已审核目录下载 MCPB，校验 SHA-256、安装、调用 `open_editor` 并请求编辑器页面，通过。
- 浏览器：移动宽度下输入正文、自动保存、重载恢复，通过。
- Android：真机 `3B65BB01B4H00000` 集成测试从已审核目录发现插件、安装、调用 `open_editor`，并在应用内 WebView 加载编辑器页面，通过。
- AppFlowy Editor 本身：在上述安装测试后，下架使目录隐藏且 MCPB 下载返回 404；重新上架后目录恢复，通过。

## 后续发布前条件

本地使用的 `127.0.0.1` editor URL 只适合端到端测试。正式 MCPB 必须嵌入部署后的 HTTPS URL，Web 资源和 MCP endpoint 保持在线。账号、命名空间、扫描和审核 SLA 需要在正式市场部署前完善。
