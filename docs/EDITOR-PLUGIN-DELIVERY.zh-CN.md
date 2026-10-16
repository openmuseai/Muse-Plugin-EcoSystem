# AppFlowy Editor 插件交付与验证

## 交付边界

[AppFlowy Editor](https://github.com/AppFlowy-IO/appflowy-editor) 是 Flutter Widget。Flutter AOT 客户端不能在应用发布后装载下载的 Dart Widget，因此本插件将上游 6.2.0 编辑器编译为 Flutter Web Wasm，并保留 Flutter 生成的 JavaScript 后备。Desktop 和 Android 在 **OpenMuse 应用内部**打开相同的编辑界面。插件仓库保留上游 MPL-2.0 许可证及最小源码副本，并适配 Flutter 3.44 的 `TextInputClient.onFocusReceived` 与 Wasm 所需的 `package:web` 浏览器 API。

Desktop 包是标准 MCPB，提供 `open_editor` 工具、`ui://` MCP Apps 资源和 HTML `resource_link`。同一个 MCPB 也包含 `web/` 静态站点。Android 读取同一插件 ID 的 MCP Registry `packages`，下载已审核包、校验 `fileSha256`，解包到应用私有目录，再用应用内 WebView 从本地受控来源打开。`server.json` 同时列出标准 MCPB `packages` 与 HTTP `remotes`，插件不需要客户端私有 manifest 或字段。`web/` 是公开文档化的静态站点打包约定，基础 MCPB 规范本身不定义 Mobile 执行。MCP Apps 资源声明 `text/html;profile=mcp-app` 和 `_meta.ui.csp.frameDomains`。macOS Host 在应用内 WKWebView 打开编辑器；Android Host 使用 Hybrid Composition 让该设备的 Flutter Web Wasm 画布可见。两个 Host 均限制跨来源导航且不提供宿主特权 JS 桥。编辑内容在当前 WebView origin 的本地存储中自动保存，可导出 AppFlowy JSON。

## 开发与发布

1. `cd plugins/appflowy-editor && npm ci && cd web && flutter pub get && cd .. && npm run build:web`。构建脚本把 Flutter 的后备字体固定到 `font-fallback-lock.json`，并把字体及 OFL 许可证纳入交付；编辑器启动时只从包内请求这些资源。
2. `npm run build && npm run build:http && python3 scripts/pack.py --editor-url https://plugin.example/editor/`
3. 若支持 Desktop 的 HTML `resource_link` 或远程 MCP 工具，部署 `web/build/web` 与 MCP Streamable HTTP 服务，生产地址使用 HTTPS。当前开发服务器在 `PORT=8768 node dist/http.mjs`，公开地址由 `EDITOR_PUBLIC_URL` 指定；Desktop MCPB 构建时必须将该地址固定为可用的公开 HTTPS 地址。Android 离线使用仅依赖下载完成的已审核 MCPB。
4. `python3 scripts/publish.py --registry https://market.example --token ... --remote https://plugin.example/mcp`
5. 审核者在独立 `/admin` 控制台检查元数据、包与实机 TCK，然后批准。下架后目录和包下载即刻隐藏；已安装包继续在本机存在。

## 验证记录（2026-10-16）

- Rust 服务：SQLite/files 流程、PostgreSQL/MinIO/Redis 流程均通过上传、审核、公开目录、下载、下架、重新上架。
- MCP 兼容：Node 标准客户端通过 stdio 与 Streamable HTTP 读取工具、MCP Apps 资源和 `resource_link`。
- macOS：从已审核目录安装 MCPB，应用内打开 WKWebView，输入标题 `OpenMuse` 和正文 `macOS in-app save 2026-10-16`，返回市场后重新打开，标题、正文和“已保存到此设备”状态恢复。完整 macOS Release 打包及 SHA-256 校验通过。
- Android：真机 `3B65BB01B4H00000`、Google WebView 138 从已审核目录发现、安装并在 OpenMuse 内打开编辑器。Android WebView 默认视图合成导致 Flutter Web 画布空白；改用 Hybrid Composition 后画布可见。Wasm 构建的编辑器正文输入 `AndroidBodySaved20261016` 后，集成测试从 AppFlowy 文档 JSON 确认自动保存，重载后再次确认正文恢复，通过。测试日志为 `/tmp/editor-wasm-android-body.log`。
- Android 离线安装：`0.1.3` 已审核 MCPB 为 38,128,993 字节，包内有 725 个后备字体和 145 份字体许可声明。Release 真机从市场安装后移除 `adb reverse`，在应用内启动 Flutter Web/Wasm，输入标题和正文并看到“已保存到此设备”。返回并重开、强制停止应用后重启，均在无转发状态恢复了同一标题和正文。`plugins/mobile-plugin-market/test/offline_mcp_install_test.dart` 另外验证了校验摘要、解包和市场断开后的安装记录恢复。
- Android 系统浏览器不是交付路径；其他 WebView/系统版本仍须设备矩阵验证。Wasm 构建包含 Flutter 生成的 JavaScript 后备，不能据此声称所有设备都执行了 Wasm 路径。
- 上下架：管理后台下架后公开目录为空且 MCPB 下载返回 404；再次上架后目录恢复且下载返回 200，审核日志保留两次决定，通过。

新验收截图：[macOS 应用内正文恢复](evidence/2026-10-16/macos-in-app-editor-restored.png)、[Android 离线冷启动后正文恢复](evidence/2026-10-16/android-offline-cold-restored.png)、[后台下架](evidence/2026-10-16/admin-delisted.png)、[后台恢复上架](evidence/2026-10-16/admin-relisted.png)。

## 本地完整应用人工验收

相邻的 `Muse-Client/dist/` 目录包含 `OpenMuse-macos.zip` 和 `OpenMuse-Android-arm64.apk`，以及 `SHA256SUMS.txt`。本轮 Android APK 内置本地测试 Registry 地址 `http://127.0.0.1:18793`，并仅对 `127.0.0.1`/`localhost` 开放明文 HTTP；正式部署必须改用 HTTPS 地址重新构建。首次安装时保持本地市场服务 `127.0.0.1:18793` 运行，确认 `GET /v0.1/servers` 包含 `io.openmuse/appflowy-editor@0.1.3`。Android 使用插件时不需要编辑器服务 `127.0.0.1:18789`。

macOS：解开 ZIP，设置 `OPENMUSE_MCP_REGISTRY_URL=http://127.0.0.1:18793` 后直接执行包内 `OpenMuse.app/Contents/MacOS/OpenMuse`。进入匿名模式 → 插件 → AppFlowy Editor → 打开 MCP App；输入标题与正文，返回插件市场，再次打开确认恢复。

Android：连接实机，首次安装使用 `adb reverse tcp:18793 tcp:18793` 访问本机市场；`18789` 不参与离线编辑器启动。安装 APK 后进入发现 → 在线 MCP 插件 → 安装 AppFlowy Editor → 打开 / 使用；完成安装后可移除 `adb reverse`，编辑正文，返回并再次打开确认恢复。`adb reverse` 仅是本地市场联调端口映射，生产市场应使用 HTTPS。

## 后续发布前条件

本地使用的 `127.0.0.1` Registry URL 只适合端到端安装测试。正式客户端应连接独立市场的 HTTPS 地址。Desktop 的 `resource_link` 若使用远程编辑器，MCPB 必须嵌入部署后的 HTTPS URL；Android 安装后的编辑器静态资源由已审核 MCPB 提供，不依赖编辑器服务。WebView 本地存储按插件来源隔离，跨设备不会共享文档。账号、命名空间、扫描和审核 SLA 需要在正式市场部署前完善。完整运行时选型与 Wasm 边界见[插件协议与运行时选型](PLUGIN-PROTOCOL-SELECTION.zh-CN.md)。
