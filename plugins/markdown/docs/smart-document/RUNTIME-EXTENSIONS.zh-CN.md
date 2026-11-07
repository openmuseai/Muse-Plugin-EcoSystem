# 内核分离、编辑协同、插件与三端运行

2026-11-04，拟议方案。所有新增接口为设计合同，未声明已有实现。参见[内容模型](CONTENT-MODEL.zh-CN.md)。

## 1. 数据内核应是可本地运行的领域核心

建议把“前端/后端”细分为四个边界，避免把每次输入都交给远端服务器：

| 边界 | 职责 | 部署 |
| --- | --- | --- |
| 编辑 surface | 临时输入、IME、选区、滚动、命中测试、菜单、无障碍投影 | Flutter；特定元素可有受控 Web surface |
| 领域核心 | schema/命令验证、文档结构、领域数据、事务/CRDT、undo 语义、引用枚举 | Rust native / WASM；服务器可复用可移植部分 |
| 平台存储/执行适配 | 文件授权、持久日志、快照、缓存、附件、Worker/线程、插件沙箱 | Desktop/Mobile native；Web 浏览器存储与 Worker 适配 |
| 共享服务 | 认证/ACL、同步、耐久检查点、任务、权限感知搜索/索引、事件与审计 | 现有 Muse Cloud/BFF 扩展，按合同实施 |

领域内核是逻辑角色，不要求一个巨大的 Rust crate 统管 Office。智能文档核心、word-core、spreadsheet 和 PDF provider 分别管理自己的对象，公共 coordinator 做命令路由与生命周期，不复制各自文档模型。

平台对象图高于单篇智能文档。统一协作底座是各领域共用的依赖，领域内核实现自己的协作绑定；它不是只供正文使用的纵向模块。Word/Excel、数据集、PPT、图片/视频编辑项目既可独立运行，也可嵌入同屏，公共底座的细分职责与协作粒度见[对象平台与协作底座](OBJECTS-AND-COLLABORATION.zh-CN.md)。

UI 可以有短期乐观编辑投影与输入草稿；必须带 revision/命令身份，依据内核确认修正，不能成为第二份独立可保存正文。前端也可以执行布局/绘制：基础块流式排版在 Flutter，Word/Excel 专业排版/计算在各自引擎，不强制所有类型都输出同一种图元。

服务端不会因为客户端已运行内核就信任其结果。结构化写入路径需验证调用者、目标权限、schema、预算与不变量；若 Cloud 仅接受原始 CRDT 更新，需确认其验证边界，并为公共 Agent/第三方命令增加受控入口。只在前端禁用菜单不能防止伪造写入。

## 2. 本地文件、SQLite 与云存储的关系

借鉴思源“原始内容可恢复、索引可重建”的原则，而非强制复制其物理格式。

* 正文持久化使用固定版本 CRDT 快照 + 增量日志；对象数据由领域 provider 持久化；原生 Office 文件是导入/导出或其版本化快照。
* SQLite 可承担 native 本地全文/引用/元数据索引、任务队列等，具体表不成为公开文档格式；内容状态与日志的事务边界应清楚定义。
* Web 使用可用浏览器存储适配；能否使用 OPFS/SQLite WASM 由目标浏览器、Worker 与依赖验证决定。首期不把 native SQLite 与目录 API 直接搬进 Web。
* Cloud 的 Postgres/Redis/对象存储继续通过其现有服务语义使用。搜索与引用为派生投影，带来源 revision 和权限，允许受控最终一致性。
* 可移植文档包包括顶层 manifest、对象快照、附件、schema/元素定义引用和必要迁移信息；格式名称/扩展名在合同阶段冻结，不沿用 `.sydoc` 冒充同一种原生思源包。

“已本机保存”“已发送”“服务端接受”“耐久检查点”是不同状态。离线写入与恢复基于实际 durable 日志；原生 ZIP CAS 会话不能同时被当成 live CRDT 保存通道。备份需包含被引用对象及定义/资源，不只是顶层块树。

## 3. 多样化编辑能力的协同

### 3.1 Markdown / WYSIWYG / 块级编辑

三者共同操作原生块模型：Markdown 输入规则把 `# ` 等转换成块命令，WYSIWYG 修改 inline/mark，块编辑处理移动、折叠、分组。它们共享节点身份和事务，不分别保存 Markdown 文本与富文本树。

原始 Markdown 源码模式需明确契约：

1. 首期只对受支持块/选定区域开放，复杂嵌入以保留引用的扩展语法或只读占位表示。
2. 源码草稿记录来源节点/范围版本，解析为结构化 diff 再提交；有人并发修改同范围时提示冲突或用严格验证的锚点重定位，不整篇覆盖。
3. 完整源模式的语法、未知节点保留、ID 稳定与并发 diff 是专项能力；首期可以仅提供 Markdown 输入和导入导出，不能因此宣称已支持双向源码编辑。

思源行为逐项由命令与交互测试承载，避免 domain 逻辑散落在 Flutter 菜单回调里。模板、AI、Agent、脚本和人类编辑都进入同一写入合同。

### 3.2 数据库视图

表/看板/日历是同一个 collection 的不同 surface。选区与行定位用稳定 recordId，视图查询响应包含版本。排序/筛选后的屏幕坐标不能直接转换成“第 5 条记录”的写入命令。视图窗口按需请求，不能把全库下载到每个文档块。

### 3.3 嵌入式编辑器与同屏协调

父编辑器负责统一阅读流、块级选择、外部拖放和文档级工具栏；激活子 surface 时由 coordinator 交付有限会话与焦点。需要明确的合同：

```text
describeCapabilities / measureIntrinsicSize / mount / updateViewport
activate / suspend / resume / dispose
getSelection / semanticHitTest / getAccessibleText
getContextCommands / execute / observeChanges
flushLocal / getCheckpoint / getStatus
```

高频 hit-test、绘制与 IME 留在受信任进程内编辑表面；跨沙箱接口按批次传递可见投影和显式命令。不同对象的撤销栈各自管理：活动子编辑器优先处理自己的 undo，父文档移动/删除嵌入用父历史；组合任务用显式业务记录，不做“依次盲撤销所有子栈”。

父 surface 与子 surface 共用焦点仲裁、快捷键作用域、剪贴板语义、坐标变换、指针捕获、滚动边界和输入法入口。触屏激活子表格后保留明确退出方式，键盘工具栏跟随当前上下文。复制嵌入可提供链接/快照/独立副本，不因 Ctrl+C 就默默复制目标对象或扩大权限。

同屏的性能依赖两级虚拟化：父文档只挂载可见块，子 Office 只布局/绘制可见页或区域；远离视口的子会话可暂停绘制但保留必要同步/本地日志。生命周期不能依赖 widget dispose 恰好完成异步保存。无障碍/文本提取要跨 surface 提供统一语义层，不能仅拼 Canvas 图像。

## 4. 插件扩展的四个层次

| 扩展方式 | 第三方能做什么 | 交付与约束 |
| --- | --- | --- |
| 声明式扩展 | 块类型组合、工具栏/菜单/快捷键、属性面板、模板、受支持表单与应用布局 | 签名资源包 + schema；解释器已有组件内热更新，能力和权限协商 |
| 沙箱逻辑 / 应用 | 查询、业务命令、低频转换、界面事件、受权外部服务 | 受控 JS/WASM/远程工具；明确 CPU/内存/网络/对象权限、取消与超时 |
| 专用交互 surface | 新图表、特殊设计器、已有 Web 编辑组件 | 沙箱 Web UI 或已编入 Flutter 的组件；几何、焦点、消息与文本投影合同 |
| 原生核心/编辑插件 | 高频布局、IME、专业领域内核、原生画布 | Rust/Flutter 源码经审核编入发行版本；ABI、各端构建与迁移门槛 |

Flutter AOT 的资源安装不等于动态装载任意 Dart widget。应承诺“统一扩展合同 + 多种受控执行方式”，而非所有第三方 Flutter 代码下载即跨端运行。Desktop 的 MCP stdio/Node 能力也不能直接成为 Mobile/Web 的运行假设。

插件 manifest/profile 需包含 `elementTypes`、`commands`、`surfaces`、`uiContributions`、`requiredCapabilities`、`permissions`、`migrations`、最低 core/surface 版本与平台降级行为；这是拟新增的元素扩展合同，不能私自往冻结的现有 manifest 顶层加字段。可用公开 resource 发布版本化 profile，再经 Host 协商；何时修改基础 SDK 由实施阶段确定。

已有 [Resource Extensions v1](../../../../contracts/resource-extensions-v1/README.zh-CN.md) 只定义资源相关浮层、工具路由及沙箱约束，当前最多 4 个视图，并不提供任意 inline 元素/逐块编辑扩展。本方案需要新增明确的文档元素与 surface profile；不能把现有右下浮层接口当作已经具备文档内应用运行时。

核心允许安装新的 UI 不代表允许任意服务端数据操作。普通自定义元素可以先使用标准字段与 CAS 操作；新增领域命令/算法应提供服务器端实现或可验证受限声明。沙箱恶意或崩溃时占位降级，不阻断文档其他块；卸载或回滚插件保留其文档数据，旧版本不得毁坏新 payload。

## 5. 文档内应用的运行链

```text
用户/Agent 事件
  -> 已固定版本的应用定义
  -> 受权查询或结构化命令
  -> 领域核心/服务的状态转换
  -> 持久事件与对象状态
  -> 多端订阅后的界面刷新
```

表单、仪表盘、审批流可以先以声明式组件和 collection 绑定实现；业务动作以命令表定义输入/输出、前置条件、幂等和权限。网络与系统访问通过 Host/服务代理显式授权，不把主应用 cookie、任意文件路径或原生 FFI 指针交给第三方。

界面重建、离线重放、历史快照加载不自动重复外部副作用。应用的运行代码与持久状态分离，升级定义需迁移检查点；依赖不可用时静态展示已提交结果并标记状态。非确定性的外部结果记录为事件/版本，便于 Agent 引用与多人复现。

## 6. 三端技术矩阵

| 能力 | Desktop | Mobile | Web |
| --- | --- | --- | --- |
| 文档壳/基础编辑 | Flutter | Flutter，触控与软键盘适配 | Flutter Web 优先，验证 IME/无障碍/长文 |
| Rust 核心 | native FFI/版本化桥 | 随应用的 native 库 | 单独 Rust WASM + interop/Worker 适配 |
| Office surface | 共用 Flutter + native provider | 共用 Flutter + native provider | 共用可移植 Flutter 部分 + WASM provider；不能走原生指针 ABI |
| 本地存储 | 授权文件/数据库 | 应用私有文件/数据库 | 浏览器存储，配额/驱逐/离线恢复专项 |
| 动态应用 UI | 声明解释器/受控 Web surface | 声明解释器/受控 Web surface，遵守平台约束 | 声明解释器/sandbox iframe |
| 任务执行 | 可受控本地执行或 Cloud | 可用内置运行时或 Cloud | Worker/沙箱或 Cloud |
| Agent | 本机受限工具 + Cloud | 前台受限工具 + Cloud | Web 会话受限工具 + Cloud |

Flutter 与 Rust 的 Web WASM 是两个产物。不能从 Flutter `--wasm` 推导 Rust C ABI、文件系统、字体、线程或 `dart:ffi` 已可用。长任务要验证 Worker 与内存复制/缓冲释放，移动端后台暂停要验证恢复，不依赖某个平台特有的 isolate 行为。

一致性的优先级：内容与权限语义一致 > 操作结果/能力标识一致 > 主要交互一致 > 布局外观尽量一致。手机不必显示桌面整条 Ribbon；同一 Office 固定页面尽量用相同字体/内核版本，但流式正文可按屏幕换行。

建议定义每个 provider 的能力矩阵，如 `render/readText/edit/export/collaborate/offline/accessible`。某端只有 render/readText 就明确为预览；不以另一端能力补写“全端支持”。Web 需要在 G0 中接入真实文档，禁止用 golden JSON/预渲染图片冒充 WASM 编辑内核验收。

## 7. Agent 与现有工具基础的衔接

现有 SDK 有 resource handler/creator/context，`ResourceEditorSession` 提供字节与 CAS commit；本机 ResourceAgentBroker 只路由活动资源，并使用本机 HTTP/IO。这能作为现有 Desktop 集成参考，不能直接推导出 Web/mobile 后台或服务端 Agent 能力。

建议新增公共文档会话 profile：对象范围、能力查询、结构化读取、命令、任务状态和事件订阅；由本机和 Cloud 两个 transport 实现同一语义。服务端 Agent 不依赖用户此刻打开某个桌面窗口；其权限由明确委托范围、期限及作业身份确定。当前 Profile 的授权语义保留，新合同不能暗中扩大已有插件权限。

按键路径不经 MCP/LLM，Agent/低频跨插件能力才经标准工具入口。UI 操作与工具调用最终都落到同一领域命令/权限校验，结果和历史可相互观察。
