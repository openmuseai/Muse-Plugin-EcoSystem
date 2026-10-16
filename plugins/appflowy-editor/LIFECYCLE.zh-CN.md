# AppFlowy Editor 0.1.4：打包、审核与人工验收

本插件是独立第三方 MCP App。开发仓库不引用 Muse-Client 代码或私有 Registry 字段。一个 `io.openmuse/appflowy-editor` 插件 ID 对应一个版本；同一份 MCP Registry `server.json` 同时声明 Desktop 的 MCPB stdio 包与 Mobile 的 Streamable HTTP 端点。Android 还可以从校验过的 MCPB 中提取 `web/` 静态站点，在 App 内离线启动 Flutter Web/Wasm 编辑器。

## 开发与打包

要求 Node 22、Flutter 3.44、Python 3。固定依赖版本后执行：

```sh
cd plugins/appflowy-editor
cd web && flutter pub get && cd ..
npm ci
npm run build:web
npm run build
npm run build:http
npm test
python3 scripts/pack.py --editor-url https://plugins.openmuseai.com/editor/
shasum -a 256 dist/appflowy-editor-0.1.4.mcpb
```

`pack.py` 生成标准 MCP Bundle。发布后不要修改同一版本的包字节；如需修复，提升版本、重新构建并提交新摘要。`open_editor` 打开空文档；`open_markdown` 通过 MCP 工具 JSON Schema 的 `contentEncoding: base64` 与 `contentMediaType: text/markdown` 声明输入，返回标准 `resource_link`。宿主无需认识此插件的私有字段。

## 上传与审核

公开 Registry 地址为 `https://plugins.openmuseai.com`。当前试运行的上传和审核接口只监听服务器回环地址，使用 SSH 隧道连接；公开 Nginx 只放行目录、已审核包及 MCP App 的读取接口。令牌应从安全保管处取得，不写入命令历史、代码仓库或截图。

```sh
ssh -N -L 18795:127.0.0.1:18794 <production-user>@<production-host>
```

在另一个终端执行，令牌由交互式安全输入或临时环境变量提供：

```sh
python3 scripts/publish.py \
  --registry http://127.0.0.1:18795 \
  --public-origin https://plugins.openmuseai.com \
  --remote https://plugins.openmuseai.com/mcp
```

脚本先 `PUT /packages/{sha256}.mcpb`，再向 `POST /v0.1/publish` 提交标准 MCP Registry `server.json`。审核状态从 `pending` 开始。审核人员通过隧道打开 `http://127.0.0.1:18795/admin`，输入审核令牌，检查包摘要、来源、许可证、Desktop 和 Android 实机操作，再批准或驳回。服务端有独立的 PostgreSQL、Redis、对象存储和审计记录；公开目录仅展示 `approved` 版本。

## 人工生命周期验收

1. **待审核**：上传 0.1.4 后，管理后台显示 `pending`；公开 `GET /v0.1/servers`、Desktop 和 Android 市场均看不到此版本。
2. **上架**：审核批准。公开目录出现同一 `name/version`、MCPB SHA-256 和 HTTPS remote。刷新两端市场，卡片出现；不要从客户端内置目录伪造这个状态。
3. **macOS 安装及使用**：从市场一键安装，校验下载摘要，打开插件时应在 OpenMuse 窗口内显示编辑器。新建、输入、离开并再次打开，检查本机编辑器存储中的内容。工作区打开 `.md` 时应由声明 `text/markdown` 的已安装插件在窗口内打开。
4. **Android 安装及使用**：在 OpenMuse 市场安装，校验 MCPB SHA-256，应用私有目录提取站点。点击“打开 / 使用”，应在 App 内显示编辑器；断网重开已安装站点，检查离线加载与本机自动保存。连接 Desktop 工作空间后点击 `.md`，确认授权提示，检查编辑器在 App 内打开文档内容。
5. **下架**：后台填写原因并执行 `delist`，刷新公开目录及两端市场。新用户不可安装；已安装副本继续可见并可打开，标记为“已下架”。后台审计记录应包含操作与原因。
6. **重新上架**：后台 `relist`，公开目录恢复。两端刷新后可重新安装；再次检查 SHA-256 与功能。正式验收结束后保持期望的最终上架状态。

目前 `open_markdown` 适合小型 Markdown 文档，上限 32 KiB。它把 Workspace 文件内容复制进编辑器，并保存在编辑器的本地 WebView 存储，支持导出 AppFlowy JSON；**不会写回原 Workspace 文件**。对远端 Workspace 的写回需要独立、可审核的资源写入授权和冲突处理，不应由插件自行访问 Desktop 文件路径。发送内容到远端 MCP 端点前，Mobile Host 会显示目标域名并征求同意。
