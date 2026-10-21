# 文档讲解：实现方案与开发计划

## 分层与合同

| 所属 | 责任 | 不透明边界 |
| --- | --- | --- |
| Host | Resource Extensions v1 目录发现、隔离 MCP Apps View、当前资源路由、授权、调用者生命周期 | 不读取 slideIndex/pageIndex，不生成讲解提示词，不识别 PPTX/PDF/DSH 业务工具名 |
| GenOffice | 原版 React/Konva、实时读取/页状态/导航公开工具 | PPTX 参数与页面内容留在插件 |
| PDF Reader | PDF.js 画布、文字层、实时页状态/导航公开工具 | PDF/OCR 语义留在插件 |
| DSH Agent | 任务开始、状态、取消，复用会话、真实模型调用与 UI 对话 | DSH HTTP、会话 ID、事件解析留在 DSH 插件 |
| Document Explainer | 浮层 HTML、依赖适配、提示词、顺序/暂停/重试 | 通过普通 MCP tools/call 调用公开生态 Profile |
| DevKit | 合同说明、项目脚手架、独立协议测试、打包/提交 | 不要求消费者导入 Provider 源码 |

标准 MCP/MCP Apps 负责运输、工具发现和 HTML 资源。基础规范不定义“文档讲解”或“浮层”，因此 Resource Extensions v1 是公开、版本化、可由其他 Host 实现的生态 Profile，不能称为 MCP 内置方法或向 MCPB 塞私有顶层字段。目录以普通 MCP resource 公开，UI 入口沿用标准 `_meta.ui.resourceUri`。具体 Schema 见 `contracts/resource-extensions-v1/`。

Host 在编辑器的外层文档中组合互相隔离的 iframe，避免 macOS 原生 WKWebView 遮盖 Flutter 悬浮控件；不向 GenOffice DOM 注入讲解代码。每个 iframe 只允许自己的 source/window 与 Host 通道，内部路由标记仅在 Host 外框与原生层使用。扩展通过 tools/list、tools/call 访问当前已打开资源的通用 list_resource_tools/call_resource_tool，以及已授权的 list_plugin_tools/call_plugin_tool。工具 JSON Schema 原样转交，Host 不解释业务返回值。

DSH 暴露自己的 dsh_generate/status/cancel 工具，生成返回受调用者约束的任务引用。消费端轮询任务完成，不把 ui/message 的接收回执当作模型完成。每轮讲解复用同一 DSH 会话，并在 DSH UI 中显示；取消只作用于本调用者创建的请求。Host 销毁扩展时调用通用 disposeCaller，DSH 负责实际取消。

PPTX 增加公开实时读/导航能力，保留旧 Agent 编辑工具。原版画布通过已有选择上下文进行导航，禁止改写引擎。PDF 原先只有文件快照，需要增加独立 PDF.js UI 入口和页导航，不让 Host 实现 PDF 逻辑。

## 实施顺序与门禁

1. 修复布局恢复：标题栏 Agent 恢复入口，保留编辑/终端；测试关闭与恢复。
2. 冻结 Resource Extensions v1 及路由工具 Schema；Host 只处理通用 Profile。测试未知工具、非活动文档、卸载/关闭撤权及 iframe 来源隔离。
3. Provider 合同：GenOffice 实时页导航/读取；PDF Reader 原版 PDF.js View；DSH 异步任务工具与会话/取消。每项独立协议测试。
4. 实现独立讲解 MCPB、SDK 客户端、DevKit 示例与开发指引，覆盖第一页/当前页/暂停/继续/错误/页面切换。
5. 完整 macOS Release 构建，保留 entitlements；在实际应用安装新包，分别 PPTX/PDF 启动讲解并核对 DSH 真实输入输出、顺序与暂停。
6. 记录发行 SHA、构建身份、截图、实际测试结果和剩余范围；按插件粒度提交。未通过的门禁保持未完成，不以设计/模拟测试代替 E2E。

## 安全和性能

目录发现按安装摘要缓存，安装/升级后失效。页面快照按需读取；不传 5MB 文件给讲解插件。每个资源扩展最多一个活动运行，单页只启动一个模型任务。默认读/导航操作不包含写入；Agent 调用需用户原生授权。禁止任意网络/任意 Host 命令；现有离线 CSP 继续执行。任务超时给出错误并取消，不无限排队。日志不记录文件内容或模型密钥。
