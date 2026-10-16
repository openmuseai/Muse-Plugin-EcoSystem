# 插件协议与运行时选型

## 结论与适用范围

MCP 是第三方插件与 OpenMuse Agent/Host 交换工具、资源和提示词的**公开协议**；MCP Registry `server.json` 是发现与分发描述；MCPB 是 Desktop 本地服务的包格式。它们不规定 UI 必须用浏览器，也不规定插件必须是独立进程。Mobile 的交互界面必须留在 OpenMuse 内，由 A2UI 渲染器或隔离的应用内 WebView 呈现。Wasm 是 WebView 内运行 Flutter Web 编辑器的编译目标，与 MCP 的消息协议属于不同层。

本轮 AppFlowy Editor 的组合是：一个 Registry 插件 ID；Desktop 使用 MCPB + stdio，Android 从已审核 MCPB 的 `fileSha256` 校验完整包并安装其中的 Flutter Web 静态资源；远端 MCP Streamable HTTP 仍供需要服务端工具的客户端使用。`open_editor` 以 MCP Apps 元数据发现 UI。Flutter Web 构建为 Wasm（不支持 WasmGC 时由 Flutter 引导器选择 JavaScript 后备）；macOS 用 WKWebView、Android 用应用内 WebView。Android 编辑器从 App 私有目录启动，打开和编辑时不依赖电脑端 `127.0.0.1`。编辑内容保存在各设备的 WebView origin 本地存储。

## 分层决策

| 层 | 采用 | 原因 | 尚需补齐 |
| --- | --- | --- | --- |
| 目录和发布 | MCP Registry `server.json`、SemVer、包摘要 | 一个逻辑插件可同时声明可下载包和远端服务；客户端按标准交付字段选目标 | 生产 Registry 全量兼容、签名、撤回推送 |
| 能力调用 | MCP tools/resources/prompts，stdio 或 Streamable HTTP | JSON Schema、能力发现、协商及成熟跨语言 SDK；Agent 可直接调用 | OAuth、逐工具授权、长期会话与弱网恢复 |
| Desktop 本地执行 | MCPB + Host 进程 | 可独立安装、卸载、终止；Node/Rust/Python 插件不必编入 Flutter AOT | OS 沙箱、资源配额、更新事务 |
| Mobile 简单 UI | A2UI over MCP | 声明式组件与动作，便于 Agent 生成和宿主控制 | 完整组件渲染及动作 TCK |
| Mobile 复杂 UI | MCP Apps + 已校验的离线资源 + 应用内隔离 WebView | 富文本编辑等交互无需改客户端 AOT；限制来源、导航和桥接 | 统一文档同步、更多机型验证 |
| UI 代码执行 | Flutter Web Wasm + JS 后备 | 可复用 AppFlowy Editor Widget；实际运行在应用内 WebView | WasmGC/图形能力矩阵、WebView 崩溃恢复 |

## 对比其他方案

| 方案 | 跨端开发和分发 | 宿主隔离与权限 | 离线/性能 | 本项目判断 |
| --- | --- | --- | --- | --- |
| Flutter 动态 Dart/AOT Widget | 复用 Flutter UI，但发布后的 iOS/macOS/Android AOT 客户端不能通用地装载第三方 Widget | 代码进入宿主进程，权限边界很弱 | 原生性能好 | 只适合随客户端发布的内置组件，不是公开动态插件 ABI |
| 私有 JSON-RPC/插件 Manifest | 可定制所有功能，但插件只能适配 OpenMuse 字段和版本 | 每个能力需自定义安全语义 | 取决于实现 | 与第三方独立开发目标冲突；不作为公开合同 |
| 纯 REST/OpenAPI | HTTP 互操作广，适合业务 API | 认证成熟；Agent 工具发现、UI 资源、会话需另约定 | 远端依赖明显 | 可作为插件自有后端；不承担本项目统一插件协议 |
| MCP + MCPB/Registry | 工具、资源、提示、发现、版本和包有公开约定及 SDK | Host 可逐工具授权；Desktop 可隔离进程 | stdio 本地低延迟，远端依赖网络 | 采用为插件能力与发现合同；其 UI/安全空白由 A2UI/MCP Apps 与 Host 策略补足 |
| A2UI 单独使用 | 适合表单和信息面板，跨端声明式 | 宿主绘制；动作仍需可信传输及权限 | 负担较小 | 与 MCP 配合，不能替代富文本编辑器或服务协议 |
| WebView + HTML/JS 单独使用 | 复杂 UI 开发方便 | 必须限制来源、导航、CSP、消息桥 | 易受 WebView 版本影响；可离线打包 | 作为受控 UI 运行时，不作为能力/发布协议 |
| QuickJS/Node 兼容层 | 小脚本可运行，但 Node 原生模块、DOM 与 Flutter Widget 不通用 | 需自建 API 与配额 | 小脚本低开销 | 可作为宿主内部实现，不承诺 Node 兼容或私有插件 ABI |
| 原生 Wasm 运行时 | Rust/C++ 逻辑可跨端；需统一 WASI、UI、文件与权限 ABI | 线性内存便于限制，但系统调用仍需 Host 设计 | 有机会支持离线；UI 渲染另建 | 值得独立 RFC/TCK；不能把 Flutter Web Wasm 误认成可直接装载的原生 `.wasm` 插件 |

MCP 的选择是**互操作优先**：独立插件仓库不导入 Must/Muse-Client 源码，也不识别客户端私有字段。代价是远端服务运维和网络延迟、MCP 本身不负责 UI 沙箱与发布审核。市场服务因此独立提供扫描、审核和撤回，客户端自行执行来源隔离、安装与工具权限。

## Mobile Wasm 的准确边界

`flutter build web --wasm` 生成 Flutter Web 的 Wasm 和 JavaScript 后备产物。它仍需要浏览器 DOM、图形 API 和资源装载环境，所以由应用内 WebView 承载；不能把 `main.dart.wasm` 交给 QuickJS 当 Node 引擎，也不能直接由现有 Flutter AOT Runtime `dlopen`。Android Host 将资源从摘要校验后的 MCPB 解包到应用私有目录，并通过受控 HTTPS 本地来源加载；`https://p<包摘要>.plugins.openmuse.io` 是 WebViewAssetLoader 拦截的应用内虚拟来源，不经外部网络。Flutter Web 默认后备字体仍可能访问 CDN，因此本插件同时打包了后备字体并设置 `fontFallbackBaseUrl`；否则离线时中文绘制会反复失败并导致空白页。Android WebView 是否可用取决于设备 WebView 的 WasmGC、WebGL 和视图合成行为，需要实机 TCK。没有通过 TCK 的机型不能被标为支持该编辑器。若需运行非浏览器 Wasm，还需要另行定义 WASI/组件模型及宿主 UI ABI。

应用内 UI 最低要求：同源导航白名单、无宿主特权 JS 桥、HTTPS（本地联调允许 loopback）、每个已安装包独立 origin 与存储、CSP 和资源预算、关闭/重开恢复、编辑/保存/查看真机验收。按包摘要隔离 origin 使版本升级时的浏览器本地存储迁移仍需设计；跨版本长期文档保存应移交宿主授权的持久化能力。即使插件工具返回标准 `resource_link`，Host 也必须把它放进符合上述约束的应用内页面，而不能把编辑器交给系统浏览器。

参考：[MCP 规范](https://modelcontextprotocol.io/specification/2026-07-28)、[MCP Registry API](https://github.com/modelcontextprotocol/registry/blob/main/docs/reference/api/openapi.yaml)、[MCPB](https://github.com/modelcontextprotocol/mcpb/blob/main/MANIFEST.md)、[A2UI](https://a2ui.org/specification/v0.9.1-a2ui/)、[MCP Apps](https://apps.extensions.modelcontextprotocol.io/)、[Flutter Web Wasm](https://docs.flutter.dev/platform-integration/web/wasm)。
