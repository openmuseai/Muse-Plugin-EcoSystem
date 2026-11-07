# 冻结基线后的实施计划与开工清单

> 2026-11-07 进度评审：本文件保留原范围和历史语境；当前状态、依赖及下一步以 [49 盘点](49-PROGRESS-REVIEW-20261107.zh-CN.md)、[50 更新计划](50-REVISED-DEVELOPMENT-PLAN.zh-CN.md) 与 [51 交接](51-DEVELOPMENT-HANDOFF.zh-CN.md) 为准。历史“未有 WS/presence”等描述不代表当前实现。

> 2026-11-06 范围追加：用户要求完整思源编辑与完整协作，最新执行批次与完成门见 [24](24-SIYUAN-PARITY-PLAN.zh-CN.md)，实际 P4 结果见 [25](25-PHASE4-IMPLEMENTATION.zh-CN.md)。本文件的旧 0.1 人周/周数不作为全量对齐承诺。

2026-11-05。产品输入：[SD-BL-1.2-20261105](13-FROZEN-BASELINE.zh-CN.md)；技术首稿：[14](14-ENGINEERING-DESIGN.zh-CN.md)；容量与全量任务：[06](06-IMPLEMENTATION-PLAN.zh-CN.md)。状态：**已形成 SD-F1 阶段工程冻结输入，第一阶段切片已实施并进入实际验收；全量 G0/M1–M4 尚未完成**。阶段 F1-01–06 及实际结果分别见 [16](16-PHASE1-IMPLEMENTATION.zh-CN.md)、[17](17-PHASE1-ACCEPTANCE.zh-CN.md)。

## 1. 里程碑、范围和决策门

沿用 6–8 人、95–170 有效人周、18–28 周总区间，G0 包含在内；约 24 周为规划参考。人员到位、依赖锁和 G0 结果确定后才换算日历日期。下列周次是相对窗口，不是已承诺交付日期。

| 阶段 | 相对窗口 | 用户可用增量 | 必须审查的结果 |
| --- | --- | --- | --- |
| B0 产品/设计冻结 | 本轮完成 | 冻结产品与可点击稿可回看 | 快照、哈希、SD/FA/WF/T/AC 追踪 |
| G0 工程可行性与合同冻结 | W1–W4 | 最小真实智能文档链路，非完整产品 | A–G 门槛、源码/构建锁、技术决策与重估 |
| M1 写作与协作底座 | W4–W9 | 创建/打开、基础编辑、真实本机/云状态 | T04–09 核心链路、数据不丢、输入可用 |
| M2 团队与 Agent | W8–W14 | 分享、评论/引用、版本/记录、Agent 有界修改 | T10–13、越权与幂等/冲突用例 |
| M3 组合内容与扩展 | W12–W19 | 真 Office/媒体、数据集/表单、声明扩展、格式桥 | T14–19，至少一类 Office 三端通过 |
| M4 发布闭环 | W18–W24，必要时至 W28 | 三端完整流程、灰度和恢复 | T20–24，全部 P0 限定范围及无阻断缺陷 |

任何阶段不能以“按钮已画出”“WS 已连接”或“预算将耗尽”替代门槛。G0 的 spike 代码属于 T03 的最小实验，T05 等任务是其后的生产完善，不构成依赖环。

## 2. 责任角色与并行边界

| 角色 | 容量建议 | 第一责任 |
| --- | --- | --- |
| 技术负责人/核心工程 | 1，计入 Rust 容量 | 合同、对象不变量、跨仓版本和工程决策 |
| Rust/协作 | 共 2 | Collab binding、native/WASM、持久/恢复 |
| Flutter/编辑交互 | 2–3 | 三端输入、命令/选区、插件面、子 surface |
| Cloud/Agent/数据 | 1–2 | 所有写入口校验、命令作业、评论/记录/数据集 |
| 跨端 QA | 1 | 可重放语料、故障注入、设备/浏览器、证据 |
| 产品/设计 | 指定职责，可共享人员 | 以冻结行为审查；精确视觉核对、Mobile 细化 |

这里分配的是责任角色，不假称已有人力到位或指定真实姓名。技术负责人不能代替 QA 独立验证。合同未稳定时可并行做假 provider/UI 接线，不能各自新建不兼容的数据真源。

## 3. G0 第一轮执行批次

### W1：源码、合同和最小对象

| 子任务 | 角色 / 依赖 | 可审查产物 | 完成判定 |
| --- | --- | --- | --- |
| T01.a 多仓状态/许可与源码盘点 | 核心；无 | HEAD、工作区差异摘要、实际 path/锁文件、来源许可台账 | 不依赖机器缓存；未知源码显式列出 |
| T01.b 补齐 Collab path 与版本候选 | Rust + Cloud；T01.a | 客户端/Cloud/编辑器/native/Web 候选锁，补丁归属 | 文件真实可取回；不能只替换版本字符串 |
| T02.a 冻结对象和领域边界 | 核心 + 产品；T01.a | objectRef/entity/partition/ACL/selector/epoch 图 | 文档、Dataset、PDF 可独立命名/授权 |
| T02.b 合同草案与正反 fixture | 核心 + Cloud + Flutter；T02.a | session/command/receipt/anchor/capability/error 样本 | 旧 strict 合同 digest 不变；未知版本拒写/只读规则明确 |
| T03.a 真实本机正文小闭环 | Rust + Flutter；T01.b/T02.b | Host 新对象 → 编辑事务 → core → 本机日志 → 重开 | 可重开恢复；无第二份可写 AST；保存状态可信 |

W1 结束优先检查依赖是否可重现及事务映射是否可行；未完成时继续解决，不把 W2 的多端成功提前记账。

### W2：Cloud、断线与 Web 真核心

| 子任务 | 角色 / 依赖 | 可审查产物 | 完成判定 |
| --- | --- | --- | --- |
| T03.b 原生双会话 + Cloud | Rust + Cloud；T03.a | 两会话同段/marks/块操作、乱序/重复 fixture | 重开后语义收敛，服务端拒绝非法结构/越权 |
| T03.c 本机故障与重连 | QA + Rust；T03.a/b | append/flush/ACK 边界退出、磁盘/配额失败、离线恢复日志 | 已 localDurable 的修改可恢复；失败无伪成功 |
| T03.d Web WASM/持久/输入 | Flutter + Rust；T01.b/T02.b | 真 WASM artifact、浏览器日志、中文输入/长文/语义报告 | 不是 JSON mock/远程截图；记录依赖/字体/浏览器 |
| T03.e 多入口数据身份 | Cloud + Flutter；T02.a/b | 独立 Dataset、文档 view、Agent 查询同一对象 | 删除引用不删源；离线不伪提交记录 |

W2 的合理目标是识别不可行点；Web 与 native 同期开始，不等到桌面产品完成再补。

### W3–W4：组合、权限、Agent 与工程冻结

| 子任务 | 角色 / 依赖 | 可审查产物 | 完成判定 |
| --- | --- | --- | --- |
| T03.f 真实 PDF + 正文 | Flutter/Office；T03.a/d | 真页/文本、固定版本、坐标、来源和生命周期 | 三端至少一类真实 provider，示例卡片不计 |
| T03.g Agent 原子命令 | Cloud + Rust；T03.b/T02.b | 读集/目标前置条件、同键重试、提交崩溃恢复和后台查询 | 人类先改时旧 patch 拒绝；提交后重试不重复 |
| T03.h 评论/权限/旧事件 | Cloud + QA；T03.b | 评论者原始 update 拒绝、撤权、awareness TTL、锚点失效 | 任意写入口一致授权；未知 epoch 不污染新状态 |
| T03.i 固定兼容与恢复策略 | 核心 + QA；以上 | engine/encoding/schema/epoch、FFI/Cloud profile、故障样本 | A–G passed/failed/unrun 可追溯，未测不作通过 |
| T03.j 决策与重估 | 技术负责人 + 产品；T03.i | 工程 ADR、风险、精确包/分支/源码锁、阶段容量 | 维持或显式调整技术路线与排期；P0 变化另记 CR |

不要求 G0 已交付完整评论/数据集产品，但必须用最小真实例子证明权限/状态边界可实现。任一硬门槛未通过，应形成可执行修复或替代方案；不能在工程报告里隐去失败。

## 4. 生产工作包拆解与完成标准

保留原 T01–T24 ID；子项作为工程 ticket 后缀。每个 ticket 模板包含：baselineId、SD/FA/WF、前置、责任角色、改动仓库、输入/输出、负例、证据和回退。表中状态均为 **planned**，不虚构 PR 或分支。

| 主任务 | 可独立评审的实现切片 | 主要依赖 / 验收 |
| --- | --- | --- |
| T04 资源入口 | creator/object catalog；adapter probe/open；路由/context；关闭/重开 | T02/T03；AC-01 |
| T05 领域核心 | stable IDs/schema；text/marks；块树事务；基础表格；anchors；本地 origin undo；未知元素 | T03；AC-02/03/14 |
| T06 协作 | 中立 contract/runtime；Cloud adapter；auth/session；update validation；awareness；追赶/背压 | T03/T05；AC-03/15 |
| T07 耐久 | native append/snapshot；IndexedDB adapter；恢复与配额失败；receipt 状态；关闭屏障 | T05/T06；AC-04 |
| T08 Flutter 编辑 | 选区命令/格式；IME/Markdown；slash/块操作；表格上下文；Mobile 键盘/返回 | T05；FA-02–06；AC-02/17 |
| T09 子 surface | focus/undo/scroll/viewport；虚拟化卸载；语义树；provider budget/隔离 | T04/T08；FA-07/14；AC-07/17 |
| T10 团队功能 | share ACL；线程/回复；锚点状态；提及/outbox；解决/重开；引用/反链；activity 投影 | T04/T06；FA-08–11；AC-05/06/15 |
| T11 Agent 服务 | 有界结构/材料查询；委托；precondition patch；幂等/操作状态；崩溃恢复 | T02/T06；AC-09/15 |
| T12 Agent 交互 | 目标/来源；草稿/建议；冲突重读；进度/取消；已提交结果定位 | T08/T11；WF-11；AC-09 |
| T13 历史恢复 | checkpoint/manifest；只读预览；命名/查询；restore barrier；离线草稿保留 | T06/T07；WF-09；AC-13/16 |
| T14 Office | PDF selector/view/text；跨端 provider；来源版本；失败/撤权；其他类型能力表 | T03/T09；AC-07 |
| T15 媒体附件 | 暂存/上传恢复；图片/视频/替代文本；manifest；预算和历史 GC | T04/T07/T09；AC-08/16 |
| T16 Dataset 服务 | schema/field/record；事务 CAS/幂等；query/ACL；outbox；私有草稿 | T02/T04；AC-10/15 |
| T17 数据/应用面 | 共享表格/看板；表单；任务模板/统计；移除实例不删数据 | T09/T16；AC-10/11 |
| T18 扩展贡献 | versioned profile；元素/菜单/slash 目录；能力求交；安装/未知/卸载 | T02/T08；AC-12 |
| T19 格式桥 | Markdown/思源固定样本；ID 映射；未知保留；损失报告；可恢复包 | T05/T13/T15；AC-14/16 |
| T20 集成页面 | 当前功能区/布局；评论/历史/Agent 同一上下文；三端主线；能力文案 | T10/T12/T14/T17/T18/T19；WF-01–12 |
| T21 可靠性 | 并发语料/随机 seed；断线/崩溃；ACL/迁移；服务故障；回归 | T06 起持续，全链后复测；AC-03/04/13/15 |
| T22 体验/性能 | 浏览器/设备/输入法；语义/主题；50ms/500ms/2s 目标实测 | T20；AC-17 与 PRD 固定口径 |
| T23 灰度 | 跨仓发布锁；源码材料；旧 schema 只读；回退/恢复演练 | T13/T19/T21/T22；无阻断缺陷 |
| T24 试用 | 主任务试用、问题归因、能力/遗留项说明、0.1 交付 | T23；全部限定 P0 有证据 |

表中“可独立评审”不意味着可忽略前置就合并启用；对外功能开关默认关闭，纵向切片可以先进入内部实验。

## 5. 追踪、证据和依赖管理

[implementation-traceability.json](implementation-traceability.json) 将全部 SD、FA、WF 映射到 T 和 AC；它用于检查覆盖，不代替详细用例。原型 19 项只标 `prototype_passed`，真实产品状态统一 `unrun`，不自动继承成功。

工程证据目录建议在实际执行时建立 `execution/<runId>/`：source-lock、environment、commands、fixtures、case-results、logs、screens 和 decision。记录操作与错误摘要，不把凭据/用户全文放进日志。源码锁包含 HEAD 和必要脏补丁；仅有 HEAD 或本轮只读文件 hash 不是完整可重现构建锁。

依赖顺序：T01 → T02 → T03；G0 后正文/协作/T07/T08 先形成基础；T10/11/13 和 T14/16 可在稳定合同上并行；T20 汇合。T21 早期开跑，发布门槛在全链完成后复核。

## 6. 失败触发与路线调整

| 触发 | 处理 | 不能采用的捷径 |
| --- | --- | --- |
| 客户端 Collab 源码/路径不可重现 | 找回固定来源或维护明确 fork，重跑编码 fixture | 用机器缓存宣布可构建 |
| 树移动/拆合破坏单父/无环 | 修 binding 或收敛受控命令，记录产品影响 | 只比较所有端同样损坏 |
| Flutter Web IME/语义/存储硬门槛失败 | 按 ADR 评估 DOM surface，共用原合同，重估工作量 | 宣称 Web 暂时只是桌面截图但仍算三端 |
| Cloud 无原子前置条件/可恢复幂等 | 补对象串行化与日志/outbox，重复故障注入 | 先读 revision 后异步发包视为 CAS |
| PDF 真 provider 不通过 | 修坐标/ABI/平台适配；能力不足如实标记 | 用示例卡片替代 AC-07 |
| 原始更新越权/数据丢失 | 停止扩大灰度、保留队列/证据、优先修复 | 客户端禁用按钮当作权限修复 |

## 7. 当前可立即开始的工作

下一执行批次限定 T01.a/b 与 T02.a/b，完成后推进 T03.a/d；本次已提供所需冻结输入、代码接入证据和任务拆解，但未执行依赖修复、创建生产包或启动真实服务。无需重做产品讨论，也不以精确 WPS 截图缺失阻止已授权范围内的技术验证。
