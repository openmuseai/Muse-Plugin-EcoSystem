# 离线 MCP Apps 发现快照 v1

这是公开的**生态打包 Profile**，并非 MCP/MCPB 基础规范自带的移动执行机制。插件与 Host 通信仍使用 MCP tools/list、tools/call 和 MCP Apps JSON-RPC；不添加客户端私有 Registry/manifest 字段。

适用于有自包含 MCP Apps HTML、在设备内执行 UI 的插件。构建时从发行版 stdio Server 导出：

```sh
node packages/plugin-sdk/scripts/export-offline.mjs <built-server.mjs> <dist/web/mcp-offline.json>
```

`web/mcp-offline.json` 格式：

```json
{"tools":["MCP tools/list 的 Tool 对象"],"resources":["MCP resources/read 返回的 ResourceContents 对象"]}
```

上述字符串仅是说明；真实数据为对象。导出器连接真实 Server，不手写另一份能力配置。资源中的 `uri`、`mimeType`、`text` 和工具 `_meta.ui.resourceUri` 沿用标准字段。快照和 HTML 一起包含在不可变 SHA-256 MCPB 中，必须重新提交审核才能修改。Mobile 只读取快照与受控 HTML，不执行 Node Server，也不依赖手机 127.0.0.1 服务。

## Host 校验

- 核验 Registry 包摘要、路径和下载/解压预算，发现快照最多 64 MiB。
- 文件编辑器：工具 inputSchema 的 `contentEncoding: base64` 与 `contentMediaType` 用于资源匹配。工具 UI 引用必须对应 `text/html;profile=mcp-app`，且其完整文本与已审核 `web/index.html` 相同。否则拒绝安装。
- 资源扩展：从普通 ResourceContents 中读取 `application/vnd.openmuse.resource-extensions+json`，校验公开 Resource Extensions v1 目录，再按入口工具 UI 引用寻找 HTML。每个 UI 最多 4 MiB，每个包最多 4 个扩展。
- 只有扩展目录，不代表插件可以成为文件编辑器。安装讲解插件不会抢占 PPTX 默认打开方式。
- HTML 运行在无同源权限的 sandbox iframe，网络由 Host CSP 和 Android AssetLoader 阻断。Android 原生消息通道仅暴露给 Host 外层文档。
- 快照描述 Server 能力，但不让手机“执行”其中的 Node 业务工具。离线 View 自身声明的实时工具及已授权 Provider 才可调用；不支持的工具明确失败。

## 生命周期

Mobile Host 持有应用内全局扩展窗口，不申请系统悬浮窗权限。缩小保持原生 View 与 JS 状态；展开恢复同一实例。关闭先撤销通用调用者、由 Provider 取消其任务，再销毁 View。资源关闭后全局窗保留为暂停状态；另一文档打开后重新建立独立资源作用域。退出账号或更换配对连接清理窗口及授权。

Host 不识别页码、文档格式或 Agent 提示词。文档 Provider 定义读页/导航，讲解插件定义顺序与提示词，Agent 插件维护其会话和私有传输。
