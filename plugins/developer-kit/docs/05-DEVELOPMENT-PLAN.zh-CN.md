# DevKit 开发计划

## 计划基线与范围

计划建立日期为 2026-10-21，任务初始状态均为 planned。本轮交付为设计文档，尚未执行下列实现任务。产品范围包含安装 DevKit 插件、应用内初始化/编辑/调试、多个能力依赖、双资源协作、真机验证与审核发布。

首个可验收产品为 macOS DevKit 和“PPT + PDF 资料讲解/比较”样板，必需能力为两个真实资源 Provider 和可替换 Agent；Voice 为可选功能。Android 的完整 App 内调用及手机创作独立成阶段门禁，不能因桌面成功而勾选完成。

## 仓库分工与预计代码位置

下列位置除现有文件外均为拟定实施位置；实现时先核对仓库结构并通过模块评审，避免重复建设。

| 工作 | 仓库和位置 | 负责人角色 |
| --- | --- | --- |
| DevKit 产品 UI、编排服务 | Ecosystem `plugins/developer-kit/{web,src}` | DevKit 前端/工具工程师 |
| SDK、Provider SDK、CLI、核心 | Ecosystem `packages/{plugin-sdk,provider-sdk,devkit-core,devkit-cli}` | SDK/工具工程师 |
| 合同和模板 | Ecosystem `contracts/`、`templates/`、`skills/` | 生态接口负责人 |
| GenOffice API | Ecosystem `plugins/genoffice-pptx` | PPTX 插件维护者 |
| PDF 公共 Provider | Ecosystem `plugins/<选定的-pdf-provider>` | PDF 插件维护者 |
| Gateway、授权和通用 Host 服务 | Client `app/openmuse_host/lib/src/host` 与共享包 | Host/安全工程师 |
| MCP Apps 通用桥 | Client `packages/openmuse_plugin_sdk/lib/src/mcp_app_document.dart` 及各端桥 | Host/平台工程师 |
| Android/设备开发通道 | Client `app/openmuse_mobile` | Mobile 工程师 |
| 合同、报告、提交状态服务 | Ecosystem `market-service` | Rust 服务端工程师 |
| 测试和干净环境验收 | 各 SDK/Provider/Client/服务的测试目录 | QA/发布工程师 |

## 阶段与出口门禁

| 阶段 | 任务 | 必须满足的出口条件 |
| --- | --- | --- |
| M0 合同与自举 | DK-001–004 | 公开 Profile/Schema/TCK 草案、真实能力矩阵、精确 Dev Host 发行目标；能明确报告旧 Host 不支持 |
| M1 通用调用与双 Provider | DK-005–010 | 按调用者授权、两文档稳定绑定、真实 PPT/PDF API、SDK 类型与 Mock/真实校验；不含 Host 格式分支 |
| M2 Desktop DevKit | DK-011–016 | 普通插件可安装运行，应用内创建/编码/调试双能力项目；无需检出 Host/Provider 源码 |
| M3 Android 与手机创作 | DK-017–020 | Android 完整安装包、原生调用桥、真机样板与手机项目创建/构建/预览；App 内完成 |
| M4 市场闭环与发布 | DK-021–025 | 独立开发者身份、证据校验、待审→上架→下架、正常客户端安装；产物一致 |

M4 的开发者服务可以在 M1/M2 期间准备，正式产品发布必须等跨端承诺和验收范围明确。多个角色可以按依赖开展工作；任务表不要求同时创建多个 agent，也不授权自动派发任务。

## 详细任务

| ID | 工作项 | 前置任务 | 交付物与完成定义 | 验收 |
| --- | --- | --- | --- | --- |
| DK-001 | 现状审计与 Provider/许可清单 | 无 | 记录当前 Host、Apps、Broker、PDF、Agent 和构建能力；已实现/缺失分开，锁定上游许可 | AC-01 |
| DK-002 | 冻结公开 Profile 与配置 Schema | 001 | Host 通用服务、合同导出、依赖和报告格式发布草案；标准/生态字段边界有独立测试 | AC-02 |
| DK-003 | 兼容目录和发行身份 | 001,002 | 精确 Host 构建/摘要、协议与设备能力；latest 解析和离线缓存规则 | AC-03 |
| DK-004 | Dev Host 自举和开发通道 | 002,003 | 独立标识/数据目录、开发凭据、可下载构建；旧 Host 引导更新，无 DevKit 特权 ID | AC-04 |
| DK-005 | Capability Gateway 和逐调用者策略 | 002 | 标准工具代理、别名、Schema 校验、预算、竞态测试；拒绝跨项目/账号调用 | AC-05 |
| DK-006 | 多资源绑定与生命周期 | 004,005 | 两文档租约、焦点独立、关闭/卸载/切账号撤销；依赖视图保留 | AC-06 |
| DK-007 | 通用 SDK 和 Provider SDK | 002,005 | Apps/MCP 适配、生成客户端、输出校验、错误映射；无 Host 源码依赖 | AC-07 |
| DK-008 | GenOffice Slides API v1 | 001,002,007 | 新版本插件、notes/preview/state/navigation、结构化结果、API 包、Mock/TCK；旧版不覆盖 | AC-08 |
| DK-009 | PDF 公共 Provider API v1 | 001,002,007 | 选择合适现有引擎并核准许可；独立发行、text/preview/state/navigation、无文字层状态、API/TCK | AC-09 |
| DK-010 | 多能力依赖解析器 | 003,007,008,009 | 功能依赖图、传递依赖/循环、同 Provider 版本交集、每端计划与锁文件；冲突有解释 | AC-10 |
| DK-011 | 项目生成及 Workspace/Runner 服务 | 004,007,010 | 空目录事务初始化、相对路径/符号链接校验、沙箱任务、取消和缓存隔离 | AC-11 |
| DK-012 | DevKit 插件壳与项目 UI | 004,007,011 | 市场安装、工作台入口、创建/导入、能力选择、计划、停用/卸载保留项目 | AC-12 |
| DK-013 | 应用内编辑和 Agent 适配 | 011,012 | 多文件保存、补全/诊断、差异、项目补丁版本检查；Agent 可替换，DSH 协议留在插件内 | AC-13 |
| DK-014 | Mock/真实调试、DevTools 与 CLI | 008,009,010,012 | 同核心运行、协议诊断、只重载消费者、证据标记；CLI 是可选入口 | AC-14 |
| DK-015 | 多资料样板与可选 Voice 适配 | 006,008,009,013,014 | PPT/PDF 单独讲解和并发比较；Agent 公开合同真实实现；Voice 缺失可降级 | AC-15 |
| DK-016 | Desktop 干净环境与持久恢复 | 012,013,014,015 | macOS 完整构建、无源码依赖开发、重启恢复、任务/编辑状态验证 | AC-16 |
| DK-017 | Android 通用 Apps/Gateway 桥 | 005,006,007 | 只宣告实现的能力、正确 Origin/身份/预算；本机 JSON-RPC 路由无需 Node/localhost 服务 | AC-17 |
| DK-018 | 设备配对、候选包和证据 | 004,014,017 | 短期调试授权、候选包隔离、安装/重载、每设备产物报告，生产凭据不复用 | AC-18 |
| DK-019 | Android 双 Provider 真机功能 | 008,009,015,017,018 | 完整 App 安装，PPT/PDF/双资料、关闭/断网/恢复实测；无外部浏览器 | AC-19 |
| DK-020 | 手机创作和隔离远端 Runner | 011,013,018,019 | 手机创建多能力项目、编辑/Agent、源码上传授权、构建、App 内预览和提交候选 | AC-20 |
| DK-021 | 市场合同目录与报告服务 | 002,003,010 | 沿用独立 Rust 服务，合同/摘要/Provider/报告索引与开发渠道，无业务文档运行流量 | AC-21 |
| DK-022 | 开发者身份和发布模块 | 014,021 | 独立 OIDC/namespace、上传/提交/查询；UI/CLI 共用，不包含 reviewer 凭据 | AC-22 |
| DK-023 | 审核生命周期与组合认证 | 016,019,022 | 待审不可见、批准可见、拒绝/下架有原因；正常客户端新装与依赖校验 | AC-23 |
| DK-024 | 文档/Skill/Context Pack 和独立开发演练 | 016,020,023 | 示例真实可运行，合同/SDK/文档摘要一致；陌生开发者完成双能力产品 | AC-24 |
| DK-025 | 发布与维护基线 | 023,024 | 不可变版本、回滚、撤权、Host/Provider 升级组合测试和故障处理手册 | AC-25 |

任务表中的数字简写均指 DK 编号；机器可读的完整依赖见 [CSV](development-plan.csv)。

## 实施批次与排期方式

建议先完成 M0 的接口评审和最小自举，再据实测任务拆分锁定排期。以下为角色到位后的粗估工作包量级，不构成固定日期承诺，也未计入外部审核、设备采购或 Provider 许可处理时间：

| 工作包 | 初步估算 | 估算成立条件 |
| --- | --- | --- |
| M0 | 约 1–2 个工程周 | 现有代码可构建，确定最低 Host 与 PDF 引擎 |
| M1 | 约 2–4 个工程周 | Host/SDK 与两类 Provider 有对应维护者 |
| M2 | 约 2–4 个工程周 | 通用授权和 Runner 可用，范围保持轻量编辑器 |
| M3 | 约 2–4 个工程周 | Android 桥、真机和隔离构建服务可用 |
| M4 | 约 1–3 个工程周 | 独立身份、市场服务及审核流程具备上线条件 |

“工程周”指对应工作流的粗估历时，工作包存在依赖及可重叠部分，不能把区间直接相加成承诺上线日期。每个阶段出口评审后更新实际进度、风险和下一批任务；若资源不足，先交付 Desktop 内测，明确 Mobile 尚不支持。

## 关键路径和风险处理

1. **公开合同与身份先行**：DK-002/005 不完成，不能把当前 Agent 进程 token 给普通插件来临时打通。
2. **PDF 不能被 Mock 替代**：DK-009 真实 Provider 未交付时，双能力产品保持 blocked；可以做 UI 演示但不能通过 M2 最终门禁。
3. **保留编辑状态**：DK-006/014 不能用卸载重开 GenOffice 的方式解决生命周期，否则未保存内容和性能均不合格。
4. **通用工程能力有安全边界**：DK-011 不以无条件 shell 或整个用户目录挂载作为临时版本。
5. **Mobile 独立验收**：DK-017/019 需要完整主应用和实机，不能仅用 browser viewport、桌面或 smoke 包证明。
6. **云 Runner 与市场隔离**：DK-020 不在生产市场机器构建，不将用户文档默认上传到构建容器。
7. **API 与实现升级分别处理**：Provider SDK 输出结构/schema 变化须验证真实下游；不能依赖 SemVer 标签或 Mock 单独判定兼容。

## 工程纪律与完成记录

每个任务以可审查的细粒度提交完成，作者身份沿用 Alexixixi；修改前检查各仓库未提交内容，保持无关 UI/AppFlowy 变更。Host、SDK、Provider 和服务端的配套提交在任务记录中关联，不把尚未发布的 SDK 名写成可安装事实。

完成任务记录具体提交、包摘要、测试命令、目标 Host、设备/系统、结果和已知限制。只有验收项有证据时才能改为 complete；文档、Schema 或 Mock 的完成不代表客户端实现完成。
