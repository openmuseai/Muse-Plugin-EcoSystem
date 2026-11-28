# Resource Extensions v1

这是公开生态 Profile，基础 MCP/MCP Apps 没有定义浮层或跨插件业务语义。运输全部使用标准 MCP resources/list、resources/read、tools/list、tools/call 与 MCP Apps；不新增 MCPB 或 Registry 顶层字段，不要求客户端源码或原生通道。

## 发现与视图

已安装的 MCP Server 用普通 resource 发布 `application/vnd.openmuse.resource-extensions+json`，内容符合 [catalog.schema.json](catalog.schema.json)。`tool` 必须在 tools/list 中存在，并以标准 `_meta.ui.resourceUri` 引用 `ui://`、`text/html;profile=mcp-app` 的资源。`resourceTools` 声明本包需要调用的资源工具名称，默认为空；Host 只允许其中实际由当前编辑器贡献的工具，未声明的编辑/保存工具无法调用。安装/开发候选授权按不可变包确认该声明；模型生成仍另行原生授权。每包最多 4 个条目，Host 最多挂载 4 个视图；不兼容可选目录不阻断文件本身。

Host 将每个 View 放在独立 sandbox iframe，当前实现锚定资源容器右下、底部留 36px；width/height 有预算，不能覆盖整个工作台或读取兄弟 iframe DOM。脚本/样式离线内联，禁止外网、表单、导航和读取任意路径。内部原生通道和帧路由标记只存在 Host 外框，不向插件公开。

标准 tool-input 通知的 arguments 是本 Profile 的公开工具输入：`resourceUri`（用户已经打开的 MCP 资源 URI，调用方不得解释或修改）、`name`、`mediaType`、`active`。Host 在活动文档改变时再次发送输入，`active:false` 同时撤销服务端任务调用者。消费者暂停、不自动重新发送请求；返回文档必须用户点击继续。

## 通用路由工具

| 名称 | 输入 | 返回语义 |
| --- | --- | --- |
| list_open_resources | {} | 当前用户打开且活动的资源 URI/名称/上下文 |
| list_resource_tools | {uri} | 该 View 贡献的标准 Tool/JSON Schema |
| call_resource_tool | {uri,name,arguments} | 原样 CallToolResult；资源必须仍活动，工具必须仍存在 |
| list_plugin_tools | {} | {plugins:[{id,tools}]}；插件自行定义业务 Schema |
| call_plugin_tool | {plugin,name,arguments} | 用户批准后的插件 CallToolResult；任务归属由不透明调用者身份隔离 |

所有结果使用标准 MCP CallToolResult。部分旧路由只有 content[text(JSON)]，新路由同时有 structuredContent；客户端必须处理 isError/JSON-RPC error，不能把接收回执当业务完成。Host 拒绝其他资源、未知工具、撤回的包和已关闭调用者；每次调用前重新验证。参数预算 128KiB。扩展也可调用自己 MCP Server 贡献的工具，用于插件自身配置和开发报告；不能覆盖 Host 路由名称。

跨插件调用首次由 Host 原生授权。当前授予对象是该调用者与资源上的已安装插件，关闭/切换文档或账号立即撤销；不会传递 DSH bridge token、Workspace ID、账号凭据或本机 shell。具体模型任务、页码、提示词、DSH 会话/事件处理属于对应 Provider。

## 开发通道

development_open_bundle 验证候选 SHA/MCPB 并经用户批准后，若目录有 Resource Extensions v1，返回 `channel:resource-extension-development`，把候选浮层挂载到当前资源。修改后再次 muse dev 只替换该调用者的候选，不重新加载编辑器。原终端关闭/短期授权过期时撤销候选；开发候选不会写入正式市场安装记录。普通 MCP Apps 候选仍走独立预览页面。该通道属于公开 DevKit Host Profile，不是 MCP 基础方法。

实现位置：Host `mcp_resource_extensions.dart`、SDK `mcp_app_document.dart`；业务参考 `plugins/document-explainer`。第三方只需本目录和已发行 Provider 的工具合同，不需要这些实现源码。
