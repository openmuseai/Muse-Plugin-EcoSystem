# Office 代码核查、实施路线与验证门槛

> 后续设计基线见 [v1](v1/README.zh-CN.md)。本文件保留 11 月 4 日核查，11 月 5 日的 SDK/PDF 补查见文末；未将源码/API 存在解释为运行验收通过。

2026-11-04。本文区分已读代码、目标设计与待运行验证；没有新增运行结果。总入口见[架构决议](README.zh-CN.md)。

## 1. ioffice/libs 的架构事实

本目录代码以 Rust 为主，既包含 Word/Spreadsheet/PPT 领域引擎，也依赖 `core-libs` 下的格式、图形、字体等基础库。大量目录与原 Java 模块对应，不能凭 Rust 文件数量推断全部算法已完成、可重入、可编译 WASM或支持协作。

| 组件 | 本次读到的实现 | 对智能文档的意义 |
| --- | --- | --- |
| word-core | Cargo 描述 parse/layout/render-command；`DocumentSession` 持有 `Box<TextDocument>`；`SessionEdit` 提供 insert/remove 及完整 relayout | 已有领域会话与排版边界可复用；不能让父编辑器直接改 DrawText |
| Word 布局输出 | `LayoutFrame` 含页尺寸、版本和 RenderCommand；指令 page-absolute twip，文字 y 为 baseline | 可做页面嵌入；需要版本、字体、坐标与命中映射合同，不等价可编辑 DOM |
| Word 编辑/保存 | `SessionEdit` 的 CP 按 Unicode scalar；`TextDocument::save/saveAs__string/save__string` 仍为 todo | 不能直接混用 UTF-16 offset；这些保存入口不能作为已完成的原生文件往返能力 |
| Word Flutter | `word_render`、`word_editor` 分离；native FFI loader；`engine.dart` Web 分支写明 wasm deferred/golden JSON | UI 复用方向明确；此路径尚不能证明真实 Web WASM 内核可用 |
| ss-core | 已有 `src/api/SpreadsheetSession.rs`、快照/布局/网格、C ABI | 与部分旧文档“没有 src”的说法不符，应以当前代码为准；已有只读接入基础 |
| ss-core 产品会话 | `execute/export` 明确返回 unsupported；ABI commands 为空、new 不支持；`open_bytes` 当前写临时文件再打开 | 产品级编辑/保存及纯浏览器 byte IO 仍需建设，不能以函数/测试文件存在推断已交付 |
| Spreadsheet Flutter | `SpreadsheetEngine` 接口、GridCraft 与 ss-core 适配器、引擎选择，拒绝错误引擎回退 | 说明统一 provider 合同可行；内嵌文档可依能力选择，不让两个模型同时可写 |
| ppt-core | Cargo 与 parse/layout/render 分层，render README 描述平台无关指令管线 | 可作为未来 slide provider；README 中 MVP 排除项需单独验证，未做完整当前实现审计 |
| core-libs | drawing/io/font 等依赖被 Word/PPT/Spreadsheet 引用 | 可以共享基础设施；不代表已有统一高层智能文档模型或协作事务 |

本次未深入审计 PDF 内核实现，不宣称 PDF 页嵌入、编辑、导出或多人协作已通过。方案为其规定 provider 位置和接口，实施前需补对应能力核查。

### 文档与代码不一致的处理

`plugins/spreadsheet-product/README.zh-CN.md` 及部分架构旧文档仍描述 `ss-core` 缺少 `src/`，当前源码已有 `SpreadsheetSession`、C ABI 和 Flutter `SsCoreEngine`，该描述已过时；但当前可调用产品入口仍明确限制编辑/导出。结论应是“有只读/渲染和会话基础，完整产品编辑保存不具备本次验证证据”，而非“没有代码”或“完整已接入”。本次不修改其他产品文档。

Word 的旧 layout README 也含带日期的早期“不存在”状态，而当前已有 `DocumentSession/SessionEdit/LayoutFrame`。本方案据实现判断结构和缺口，未将旧状态表或产品目标当作当前运行结果。

## 2. 可核查源码入口

以下相对路径从本目录到工作区根，再到 ioffice/Host；适用于当前并列 checkout。

| 主题 | 证据 |
| --- | --- |
| Word crate 依赖与 native/wasm 条件 | [word-core Cargo.toml](../../../../../ioffice/libs/word-core/Cargo.toml) |
| Word 稳定内存会话 | [DocumentSession.rs](../../../../../ioffice/libs/word-core/src/cn/wps/moffice/writer/api/DocumentSession.rs) |
| Word 变更与 Unicode scalar CP | [SessionEdit.rs](../../../../../ioffice/libs/word-core/src/cn/wps/moffice/writer/api/SessionEdit.rs) |
| Word 布局、页面与 twip 指令 | [LayoutDocument.rs](../../../../../ioffice/libs/word-core/src/cn/wps/moffice/writer/api/LayoutDocument.rs)、[Flutter render_command.dart](../../../../../ioffice/samples/libs/word/word_render/lib/src/render_command.dart) |
| Word 保存占位 | [TextDocument.rs](../../../../../ioffice/libs/word-core/src/cn/wps/moffice/writer/core/TextDocument.rs) 的 `save`、`saveAs__string`、`save__string` |
| Word Web 暂缓分支 | [engine.dart](../../../../../ioffice/samples/libs/word/word_render/lib/src/engine.dart)、[ffi_loader_stub.dart](../../../../../ioffice/samples/libs/word/word_render/lib/src/ffi_loader_stub.dart) |
| ss-core 模型、临时文件 IO、能力限制 | [SpreadsheetSession.rs](../../../../../ioffice/libs/ss-core/src/api/SpreadsheetSession.rs)、[session_abi.rs](../../../../../ioffice/libs/ss-core/src/ffi/session_abi.rs)、[Cargo.toml](../../../../../ioffice/libs/ss-core/Cargo.toml) |
| Spreadsheet provider 合同与选择 | [gridcraft_engine.dart](../../../../../ioffice/samples/libs/spreadsheet/spreadsheet_editor/lib/src/gridcraft_engine.dart)、[ss_core_engine.dart](../../../../../ioffice/samples/libs/spreadsheet/spreadsheet_editor/lib/src/ss_core_engine.dart) |
| PPT 分层 | [ppt-core README](../../../../../ioffice/libs/ppt-core/README.md)、[render README](../../../../../ioffice/libs/ppt-core/render/README.md)、[Cargo.toml](../../../../../ioffice/libs/ppt-core/Cargo.toml) |
| Office 产品包/编辑面/内核边界 | [Word 架构](../../../word/docs/02-ARCHITECTURE.zh-CN.md)、[Spreadsheet 架构](../../../spreadsheet-product/docs/01-ARCHITECTURE.zh-CN.md)；含旧状态，结合实现读取 |
| 现有资源 CAS 会话 | [resource_capabilities.dart](../../../../../Muse-Client/packages/openmuse_plugin_sdk/lib/src/resource_capabilities.dart) 的 `ResourceEditorSession` |
| 现有本机 Agent 活动资源路由 | [resource_agent_broker.dart](../../../../../Muse-Client/packages/openmuse_plugin_sdk/lib/src/resource_agent_broker.dart) |
| 当前公开扩展 Profile 的边界 | [Resource Extensions v1](../../../../contracts/resource-extensions-v1/README.zh-CN.md) |
| 思源与 AppFlowy 版本/协议核查 | [前一轮证据](../collaboration/EVIDENCE.zh-CN.md)，仍有效；其中旧方案的范围不覆盖本轮完整目标 |

本次 `ioffice` 目录本身未解析到 Git 根，故不编造单一 HEAD；正式复现应记录文件摘要、源 checkout 与跨仓版本锁。AppFlowy/Cloud 的 HEAD、工作区修改及依赖问题沿用前一轮证据，G0 重新冻结。

## 3. 必须先做的架构原型

目标：用 **3–4 周**证明端到端组合路线，不能只做一个漂亮的同屏界面。

| 门槛 | 原型要求 | 不通过时如何调整 |
| --- | --- | --- |
| G0-1 公共模型 | 一个正文文档含标题/段落/表格/公式/未知插件块/资源嵌入；schema 与元素合同可迁移 | 缩小首期元素集，但保留未知数据与版本策略 |
| G0-2 三端主链 | Desktop + Android/iOS + Web 读取同一对象；正文真实编辑、离线重开与重连收敛 | 先修复内核与平台运输；Flutter Web surface 问题可评估 DOM 适配，不另建数据真源 |
| G0-3 真实 Office 嵌入 | 至少一个真实 Word 页或工作簿区域；记录是否本地渲染/服务端快照、版本与 selector；跨端重开 | 真实 WASM 尚不可用时先只读版本快照并明确标识；这不算 WASM 门槛通过 |
| G0-4 Agent 主链 | Agent 读取结构与子对象版本、插入引用/摘要；人类并发修改目标触发语义前置条件；作业可查询 | 重做命令合同，不能以键鼠自动化替代此门槛 |
| G0-5 插件升级 | 新增声明式元素/小应用；未安装端占位保留；版本迁移后旧端不能毁坏新数据 | 限制可用扩展类型；不要开放任意原生代码下载 |
| G0-6 权限和检查点 | 嵌入目标撤权不泄露；父/子历史重开版本明确；跨对象失败可恢复 | 增补服务端合同；不以 UI 隐藏视图代替对象授权 |
| G0-7 独立领域对象 | 独立工作簿/数据集入口、智能文档内视图和 Agent 连接同一对象；实体/同步分片/事务/权限范围分别描述 | 修正以父文档为根的模型；不能先复制数据到不同 surface 再分别保存 |

G0 中 Web 不后置：必须明确 Rust 核心 WASM 是否可构建/运行、浏览器持久化与内存边界。若 Office Web 只读快照可接受，可以进入受限首版，但能力矩阵必须标记“正文可编辑，Office 仅快照预览”，不可承诺全端 Office 本地编辑。

## 4. 首期平台路线与周期

以 6–8 人有效投入为估算基础：2–3 名 Flutter/编辑交互，2 名 Rust/领域与WASM，1–2 名 Cloud/Agent/插件，1 名跨端 QA（部分职责可交叉）。下列为 **18–28 周、约 95–170 人周** 的范围估算，含 G0 与首次集成缓冲，未有 PoC 测量支撑。

| 阶段 | 工作 | 输出与范围 |
| --- | --- | --- |
| M0：3–4 周 | 上述架构原型，依赖与合同冻结 | 用运行结果确认 Flutter Web 与 Office 交付模式；重估计划 |
| M1：4–6 周 | 原生块/inline、Rust 命令、AppFlowy 协作适配、本地日志、Cloud 对象会话 | 三端正文创建/编辑/协作、结构化读取与权限校验 |
| M2：4–6 周 | 引用/嵌入/基础 collection、Agent 幂等/前置条件/事件、版本与manifest | 至少一类真实 Office 只读 provider，公共对象合同不绑定具体内核 |
| M3：3–5 周 | 声明式扩展、工具栏/菜单、简单文档应用、兼容/未知节点/迁移 | 一类表单或仪表盘应用，Agent 可读可操作；不承诺任意第三方 UI 代码 |
| M4：4–7 周 | 三端输入/生命周期、网络/崩溃/权限故障注入、性能/无障碍、灰度 | 可交付首版与明示能力矩阵，阻断数据缺陷清零 |

按依赖可以局部并行，范围合计按关键路径和缓冲核算。若团队只有前一轮 4–5 人，或 Web/Office 核心需大改，应扩大日历区间；不能沿用 12–18 周小范围编辑器排期。

后续独立立项：Word 领域编辑保存补齐与稳定锚点、Spreadsheet 核心替换/领域协作、PDF 页内容编辑与注释、思源 AV/SQL/图谱/闪卡、完整 Markdown 源码模式、第三方沙箱生态与应用发布。每项先盘点现有能力，再估时；不把它们打包进首版平台估算。

## 5. 思源功能保真的分级验收

| 等级 | 能力 | 完成证据 |
| --- | --- | --- |
| S0 可保留 | 原生包、未知节点与 source IDs 不丢 | 取回原文、完整性校验、插件缺失/旧端重开 |
| S1 核心写作 | 段落/列表/代码/公式/基础表格/附件、稳定块操作 | 人类与 Agent 操作、三端交互、导入导出语义往返 |
| S2 知识关联 | 动态引用、嵌入、IAL、标题折叠、反链/检索 | 引用重定位、并发编辑、权限过滤与重命名行为一致 |
| S3 数据与工具 | AV/关系/公式/查询、图谱/历史等分能力实现 | 源语料与操作序列差分；SQL 语义映射/安全边界单独列明 |
| S4 深度兼容 | 特殊交互、复杂原生格式、第三方插件 API 等 | 单独范围/许可/运行时决策，不随 S3 自动达成 |

每轮开发维护 feature → schema/command → SiYuan fixture → expected behavior → platform evidence 的映射。未知载荷保留是 S0；不能冒充 S1–S4。持续迭代路径可以设计，达到完整保真的日期和所有第三方行为不能提前保证。

## 6. 平台级验收补充

* 同屏测试：正文 + 表格 + Office 视图 + 应用块并存；滚动、缩放、焦点、剪贴板、撤销和软键盘没有跨 surface 混乱。
* Agent 测试：后台无桌面窗口也能按权限读取/提交；重复请求幂等，取消和重试不重复副作用；读取来源版本可追溯。
* 协作测试：正文收敛；子 Office 为只读/单写者时明确拒绝第二写入；未来可协作模式分别验证领域冲突，不能只测嵌入配置同步。
* 版本测试：live/pinned/copy、旧/新 schema、子对象失效、插件升级/卸载、历史检查点跨对象恢复。
* Web 测试：目标浏览器真实 Rust WASM 或明确受限模式、IME/无障碍、字体与性能、Worker、存储配额与缓存驱逐；golden JSON 不算真实内核验证。
* 原生测试：macOS/目标 Desktop、Android/iOS 真机输入法、应用后台与进程终止恢复；模拟器结果与真机分开记录。
* 可信边界：不允许插件/Agent 伪造 actor 获权，引用不授予对象权限，服务端拒绝越权写，沙箱失败不阻断整篇文档。

性能预算在 M0 用真实设备、固定文档集与网络记录后冻结；至少跟踪本地输入、远端可见、首屏/大文档滚动、多个 Office 会话内存、Web 核心下载/编译耗时，不仅测试简单段落帧率。

## 7. 本次交付限制

此次完成架构调整、代码边界核查及方案落盘，更新前一轮文档入口使其保留为历史范围评估。未修改 ioffice、编辑器内核、服务端或 SDK 代码，未编译/运行 Web/native/协作 PoC，未改用户已有工作区内容。文档链接/格式检查不能替代上述产品验收。

## 8. 2026-11-05 补查：PDF 与现有资源合同

* [PDF 产品架构](../../../pdf-product/docs/01-ARCHITECTURE.zh-CN.md)与 [ProductEditBridge.h](../../../../../ioffice/koffice/pdf/rebuild/pdf-rebuild/src/ksp/product/ProductEditBridge.h)表明：当前产品会话是 C++/PDFium，提供 byte open、page size、page/region render、文本/选区编辑等 ABI；Web 为 Emscripten WASM。智能文档应通过 provider 复用，不要求迁到 Rust。此次仅核查声明/头文件及文档，未重新构建或设备验证。
* [engine_session.dart](../../../../../Muse-Client/packages/muse_resource_contract/lib/src/engine_session.dart)已有引擎身份、manifest、模式、placement、会话状态与能力类型；[resource.dart](../../../../../Muse-Client/packages/muse_resource_contract/lib/src/resource.dart)已有资源描述与版本；[presentation.dart](../../../../../Muse-Client/packages/muse_resource_contract/lib/src/presentation.dart)已有展示请求和 provider anchor。新增 live/object/element profile 应先映射这些合同，并遵守其严格版本解析；类型声明存在不等于已有完整智能文档运行时。
* 复核 [Cloud WS 路由](../../../../../Muse-Server/AppFlowy-Cloud/src/api/ws.rs)、[ss-core 产品会话](../../../../../ioffice/libs/ss-core/src/api/SpreadsheetSession.rs)、[Word Web 分支](../../../../../ioffice/samples/libs/word/word_render/lib/src/engine.dart)，此前关于双 WS 路由、产品 execute/export 不支持及 Web golden JSON/wasm deferred 分支的观察仍在。
