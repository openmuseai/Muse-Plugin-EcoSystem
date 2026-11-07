# 可扩展协作文档平台与智能文档：设计基线 v1.2

已归档：[P14 数据库共享视图规则](37-PHASE14-DATABASE-VIEW-RULES.zh-CN.md)。原规则/核心/三端真实 UI 与跨端读回已验收；显示投影与协作依赖分离，完整功能门仍开放。

已归档：[P13 协作会话生命周期与异步权限边界](36-PHASE13-COLLABORATION-LIFECYCLE.zh-CN.md)。345 份源码/测试输入与三端证据已冻结校验。

已归档：[P12 嵌入资源键盘边界与原日期字段](35-PHASE12-EDITOR-INTERACTION-DATES.zh-CN.md)。保持原编辑/协作内核和冻结交互，继续逐项验收。

已归档：[P11 独立数据库实时协作适配](34-PHASE11-DATASET-REALTIME.zh-CN.md)。原 WS2 的类型 1/4、动态新行和单元格在线状态已通过真实 Cloud、公共插件及 macOS/iOS/Web 增量验收，328 份文件已归档。

已归档：[P10 文档内数据库与独立资源界面贡献](33-PHASE10-EMBEDDED-DATASET.zh-CN.md)。复用原数据库引用块及共享 Grid，三端增量与独立协作边界已验收；完整产品门仍未通过。

当前增量：[P9 数据库字段与视图持续对齐](32-PHASE9-DATABASE-FIELDS.zh-CN.md)。单选/多选、真实三端 UI 与原生/浏览器对象往返已推进，完整功能门仍未通过。

最新增量：[P8 实时协作、原在线状态与三端界面验证](31-PHASE8-REALTIME-IMPLEMENTATION.zh-CN.md)。原 WS v2、Yrs Awareness、公共插件注入及 macOS/iOS/Web 切片通过；完整编辑/协作门仍未通过。

日期：2026-11-05。状态：**产品/交互冻结为 SD-BL-1.2-20261105；阶段工程方案冻结为 SD-F1-20261105，已实现 macOS 与 Web 真 WASM/IndexedDB + 原 Cloud 的跨端链路，独立协作合同进入内部预览；完整 G0/0.1 尚未验收**。目标目录仍为 `plugins/markdown`，产品概念已超出 Markdown 编辑器。

本套文档收敛历次讨论，是后续产品与工程规划的主入口。与前期讨论稿冲突时，以本目录为准；固定依赖、端上能力与工期需经过 G0 重新确认。

产品/交互/可点击设计快照保持不变。当前已按阶段方案实施新 Rust/Flutter 智能文档、公开 SDK 插件和原 Cloud 适配；通用协作 package 的正式发布仍待工程合同门。

**本轮继续实施：[思源功能复用与交付计划](27-SIYUAN-REUSE-AND-DELIVERY.zh-CN.md) → [P6 链接/私有图片与独立传输](28-PHASE6-LINKS-ASSETS-IMPLEMENTATION.zh-CN.md) → [数据库适配方案](29-DATABASE-ADAPTER-DESIGN.zh-CN.md) → [P7 独立数据库与生命周期保护](30-PHASE7-DATASET-IMPLEMENTATION.zh-CN.md)。** 完整产品门保持未完成，运行时资格与增量验收不代替全量功能。

**此前推进（2026-11-06）：[P5-A 真实表格编辑与多人协作](26-PHASE5-TABLE-IMPLEMENTATION.zh-CN.md)。** 固定网格文字编辑和跨端协作已实现；完整思源/协作仍按 50 项能力门推进。

**上一批（P4）：[思源编辑/完整协作范围与开发门](24-SIYUAN-PARITY-PLAN.zh-CN.md) → [P4 稳定块编辑、代码与三端 Cloud 验证](25-PHASE4-IMPLEMENTATION.zh-CN.md)。** 完整目标按 36 项编辑 + 14 项协作能力逐项验收，尚未完整交付。

**此前增量：[Web 与协作合同实施](18-WEB-COLLAB-IMPLEMENTATION.zh-CN.md) → [真实浏览器/native 互通验收](19-WEB-COLLAB-ACCEPTANCE.zh-CN.md)。**

**第一阶段入口：[第一阶段方案与开发批次](16-PHASE1-IMPLEMENTATION.zh-CN.md) → [实现与验收证据](17-PHASE1-ACCEPTANCE.zh-CN.md) → [可运行源码](../../../smart_document/README.zh-CN.md)。**

**完整设计入口：[冻结记录与快照](13-FROZEN-BASELINE.zh-CN.md) → [详细技术方案](14-ENGINEERING-DESIGN.zh-CN.md) → [执行计划](15-EXECUTION-PLAN.zh-CN.md)。**

最新用户约束：优先对齐 WPS 智能文档的功能区、编辑区和协作方式。已更新 [交互规格](05-UX-SPEC.zh-CN.md) 与 [v1.2 可点击视觉稿/功能映射](12-FUNCTIONAL-ALIGNMENT.zh-CN.md)，上一版自定义桌面布局保留为历史。指定企业页的精确布局仍待核对；公开手册依据及证据等级见 [11](11-WPS-DESKTOP-REFERENCE.zh-CN.md)。

## 阅读与评审入口

| 文档 | 主要回答 |
| --- | --- |
| [平台架构](01-PLATFORM-ARCHITECTURE.zh-CN.md) | 对象图、横向协作底座、领域内核、细粒度协作、Cloud 扩展 |
| [智能文档详细方案](02-SMART-DOCUMENT-DESIGN.zh-CN.md) | 内容结构、命令与同步、内核/编辑面、Agent、Office、应用与持久化 |
| [技术选型与决策](03-TECH-DECISIONS.zh-CN.md) | Flutter/Rust/WASM/AppFlowy/思源/Office 的复用范围、替代路线及验证条件 |
| [产品稿 PRD](04-PRODUCT-PRD.zh-CN.md) | 用户、场景、功能范围、需求编号、指标、版本边界 |
| [交互稿与页面规格](05-UX-SPEC.zh-CN.md) | Desktop/Web/Mobile 布局草图、关键流程、操作与异常状态 |
| [开发计划](06-IMPLEMENTATION-PLAN.zh-CN.md) | 仓库归属、工作包、依赖、人员、阶段、排期、风险和灰度 |
| [验收与追踪矩阵](07-ACCEPTANCE.zh-CN.md) | 从产品需求到模块、任务、测试及发布门槛的追踪 |
| [产品与交互收敛](08-PRODUCT-REFINEMENT.zh-CN.md) | U1–U3 关键任务、现有 Host 融入、操作/状态/失败、产品边界 |
| [协作 package/plugin 设计](09-COLLABORATION-PACKAGES.zh-CN.md) | 中立协议 package、runtime、provider/plugin、领域绑定与依赖方向 |
| [历史视觉交互评审 v1.1](10-VISUAL-REVIEW.zh-CN.md) | 旧三种布局与行为试验；不作为最新桌面视觉基线 |
| [WPS Desktop/Web 对齐基准](11-WPS-DESKTOP-REFERENCE.zh-CN.md) | 公开功能依据、指定页访问状态和待核对视觉 |
| [当前功能对齐与视觉稿 v1.2](12-FUNCTIONAL-ALIGNMENT.zh-CN.md) | 功能区/编辑区/协作、14 项映射、WF-01–12、可点击稿、截图与架构反推 |
| [冻结产品/设计基线](13-FROZEN-BASELINE.zh-CN.md) | 冻结范围、快照、完整性清单、开放项与变更方式 |
| [详细技术方案](14-ENGINEERING-DESIGN.zh-CN.md) | 代码接入、包落点、对象/状态、命令/接口、数据链路和恢复 |
| [执行计划与 G0 开工清单](15-EXECUTION-PLAN.zh-CN.md) | 第一轮 4 周批次、T01–24 切片、角色、产物与门槛 |
| [阶段工程方案与开发批次](16-PHASE1-IMPLEMENTATION.zh-CN.md) | SD-F1 冻结输入、版本、F1-01–06、源码归属和阶段退出条件 |
| [第二阶段实施与方案](18-WEB-COLLAB-IMPLEMENTATION.zh-CN.md) | 真 Rust WASM、IndexedDB、独立合同与固定版本浏览器适配 |
| [第二阶段验收报告](19-WEB-COLLAB-ACCEPTANCE.zh-CN.md) | Web 双账号、整页重载、native 读回与原生回归 |
| [P5-A 表格实施](26-PHASE5-TABLE-IMPLEMENTATION.zh-CN.md) | 固定网格 schema、单元格输入/并发/撤销、无凭据新进程和 Web 重载验证 |
| [完整编辑/协作开发门](24-SIYUAN-PARITY-PLAN.zh-CN.md) | 固定思源来源、50 项能力台账、P4–P8 批次与最终完成门 |
| [P4 实施与验证](25-PHASE4-IMPLEMENTATION.zh-CN.md) | 稳定类型命令、Markdown/code、三端原 Cloud 实际验证及缺口 |
| [第一阶段验收报告](17-PHASE1-ACCEPTANCE.zh-CN.md) | 真 Cloud 双账号、macOS 原生 SDK 链路、命令、截图及尚未通过的完整门槛 |

前期[内容模型](../CONTENT-MODEL.zh-CN.md)、[协作边界](../OBJECTS-AND-COLLABORATION.zh-CN.md)、[代码证据](../DELIVERY-EVIDENCE.zh-CN.md)继续作为专项解释和来源记录。

## 核心决议

1. 平台顶层是内容对象图。智能文档、Word、工作簿、数据集、PPT、PDF、图片/视频项目和应用是并列领域；可独立打开、授权、操作和协作。
2. 智能文档是“原生块 + inline + 外部对象视图 + 应用”的组合对象。引用不复制目标真源，也不自动授予权限。
3. 身份、查询、命令、版本、能力和生命周期统一；各领域保留自己的内容语义。实体、事务、同步分片、权限和订阅分别设计。
4. 协作底座横向共享，在依赖方向上位于领域内核之下。领域绑定负责命令、锚点、合并及不变量；共享基础设施不等于单一通用合并算法。
5. 新智能文档优先 Flutter 编辑面 + Rust 领域核心 + AppFlowy/Yrs 协作适配。Web 与 native 同期验证。PDF 保留现有 C++/PDFium provider，不为语言统一重写成熟内核。
6. 服务端继续基于 Muse-Server/AppFlowy-Cloud；共用现有身份与存储，按明确合同扩展对象、命令、检查点和索引。不得将所有对象伪装为 Document 类型。
7. Agent 使用与人类编辑一致的领域命令，具备结构化读取、语义前置条件、幂等作业、来源和事件；按键路径不经过模型或 MCP。
8. 插件通过版本化元素/命令/surface profile 扩展。声明式内容可动态安装，高频 Flutter/原生编辑能力随发行版编译，复杂应用在受控沙箱内运行。
9. 思源借鉴块、引用、属性、投影与内核分离；不直接继承 `.sy` AST 为平台永久模型。原生格式保留兼容入口，通过语料与迁移逐步提升保真。
10. 资源内容合同与协作协议解耦：协议/runtime 是独立 package，Cloud 是可装配 provider/plugin，领域算法/binding 随内容模型维护。停用网络连接与卸载状态引擎不同，不在已打开对象中随意换协议/引擎。

## 首版边界与周期

首版 0.1 交付：Mobile/Web/Desktop 的基础块协作、离线本机恢复、共享权限、基础引用与评论、Agent 结构化操作、图片/视频播放块、固定版本 Office 视图 provider、基础数据集与表单型应用样板。Office provider 至少一类真实来源通过三端验证，其余在能力表中显式标识，不以示例图片替代。

旧 0.1 容量基线中，Word/Excel/PPT 全量领域多人编辑、完整思源保真、任意第三方代码热安装、媒体专业剪辑、完整低代码平台不在 0.1 承诺。它们的身份/命令/领域协作接入边界必须首期预留，并有后续专项门槛。

用户已追加完整思源编辑与完整协作目标，按 [24](24-SIYUAN-PARITY-PLAN.zh-CN.md) 的变更范围实施；以下原受限首版估算不能作为全量目标的交付承诺。

建议 G0 3–4 周，6–8 人团队交付上述受控首版的规划区间为 **18–28 周，约 95–170 人周**。这是容量估算，非日期承诺；工期从人员和依赖到位开始，G0 后冻结基准。完整 Office 协作另估，不沿用早期小范围编辑器的 12–18 周估算。

## 本次交付状态

完成：产品/交互和阶段工程输入冻结、固定 AppFlowy-Collab/Yrs + Flutter 原生编辑、本机保存、原 Cloud 双账号协作、公开 SDK 插件、真实资源 CAS/重开和 macOS 端到端验证。另完成 Web WASM/IndexedDB、独立协作合同与 native/Web 互通。详细覆盖以 [17](17-PHASE1-ACCEPTANCE.zh-CN.md)、[19](19-WEB-COLLAB-ACCEPTANCE.zh-CN.md) 为准。

待实施/未认证：Web 完整输入/性能/语义、Mobile 完整能力、人工 IME、完整权限/评论/历史/Agent/Office/数据集、故障/性能发布门，以及正式 Host 装配和生产部署。第一阶段使用现有 HTTP full-sync，不具备 WS/presence 或耐久 ACK；不能将阶段结果替代 AC-01–17 全量验收。视觉稿仍是完整目标，当前最小编辑面不宣称已达到 WPS 全功能/精确视觉一致。


Mobile 最新实施输入：[产品与完整交互](21-MOBILE-PRODUCT-UX.zh-CN.md) → [视觉稿、基线与开发映射](22-MOBILE-DESIGN-REVIEW.zh-CN.md)。SD-MOB-1.3-20261105 追加归档，不改写 SD-BL-1.2 历史冻结内容。


**Mobile 进度：[M3-A 历史结果](23-MOBILE-IMPLEMENTATION.zh-CN.md) → [P4 新结果](25-PHASE4-IMPLEMENTATION.zh-CN.md)**。iOS 本机、新进程恢复与第二认证用户 Cloud 同步已通过；历史 Cloud 阻断保留在旧报告。完整目标视觉稿保持冻结，未实现功能继续按能力台账推进。

[Mobile 24 项实现追踪](mobile-implementation-traceability.json) 单独记录部分实现/未实施与最新 Cloud 验证，不改写既有冻结验收状态。
