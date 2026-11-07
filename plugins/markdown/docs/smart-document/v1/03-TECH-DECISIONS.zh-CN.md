# 技术选型与架构决策记录

> 当前采用 [冻结产品基线](13-FROZEN-BASELINE.zh-CN.md) 和 [详细技术方案](14-ENGINEERING-DESIGN.zh-CN.md)；工程版本/API 仍须 G0 冻结，不能将产品冻结解释为技术验证完成。

2026-11-05。状态“选定方向”指本套设计的建议；依赖锁和运行可行性待 G0 验证。所有选型服从现有 Muse 服务端与 ioffice 领域边界。

## 1. 选型总表

| 层 | 选定方向 | 复用 / 新增 | 主要代价 |
| --- | --- | --- | --- |
| 公开内容协议 | 自有版本化对象/元素/命令 profile | 复用现有资源合同，新增领域合同 | 要维护 schema、迁移、兼容与 fixture |
| 正文 UI | Flutter + appflowy_editor 适配 | 复用 editor，剥离应用壳 | 原生输入/选区、多端与自定义块需验证 |
| 智能文档核心 | Rust + Collab/Yrs 适配 | 复用成熟文本/块链路，新增公共语义层 | 依赖抽离、树结构不变量、FFI/版本互通 |
| 领域 provider | ioffice 现有引擎 | Word/Spreadsheet/PPT Rust；PDF C++/PDFium | 各端真实能力与 ABI 不同，不做统一语言重写 |
| 云端 | Muse-Server/AppFlowy-Cloud Rust fork | 复用认证、对象协作和存储；补公共服务 | fork 自维护、schema/ACL/事务扩展 |
| 数据集 | Cloud 事务命令 + outbox + 客户端投影 | 新增受限基础数据集实现 | 0.1 不承诺离线多写合并或完整多维表格 |
| Native 本地数据 | 已有 Collab 持久层 + 私有文件；SQLite 用于适当队列/索引 | 复用可用实现，保持一个耐久真源 | 不同时在多个数据库独立写同份正文 |
| Web 本地数据 | IndexedDB 快照/日志；WASM 存储适配 | 新增运输适配 | 浏览器配额/驱逐、Worker 与恢复验证 |
| 附件/媒体 | 现有对象存储 + 摘要/授权/manifest | 复用存储，新增引用生命周期 | 历史可达性、GC、离线上传与大内容预算 |
| Agent | 领域工具 + 可查询幂等作业 | 复用模型/Agent 基础；新增文档语义服务 | 版本前置条件、权限与后台作业能力 |
| 扩展 | 声明式组件优先；后续沙箱 JS/WASM | 新元素 profile；复用安装验签 | 任意 Flutter 代码不能资源热安装 |
| 搜索 | 初期关键词/结构引用投影 | 复用已有索引模块及 ACL | 先保证可重建与权限；向量检索后续按需求增加 |

## 2. ADR-01：公共模型独立于思源与 AppFlowy 私有格式

选择自有公共语义，以 AppFlowy Document 为首期实现适配。思源的稳定块、引用、属性、投影设计和样本可借鉴，`.sy` 与原生数据库格式保留转换边界。

替代方案：直接继承思源 AST 最快保留原生 UI/格式，但受 Lute/BlockDOM/Go 事务与扩展边界约束；直接公开 Collab 私有键减少包装却把第三方锁定在某个实现。当前产品要容纳 Office/媒体/应用，因此接受一个薄而稳定的语义合同成本，避免再建设独立在线 IR 真源。

## 3. ADR-02：Flutter 优先，全端验证，不采用全 Dart 内核

Flutter 复用界面符合多端与现有 Office 表面方向；Rust 复用协作和领域逻辑。Go/Protyle 保留兼容入口；PDF 保留 C++。统一指合同和体验，不要求语言一致。

Flutter 官方提供 Web/Wasm 构建能力，同时要求依赖/interop 兼容；这不代表 native FFI 或文件系统可直接在 Web 使用。[Flutter Wasm](https://docs.flutter.dev/platform-integration/web/wasm)、[Web FAQ](https://docs.flutter.dev/platform-integration/web/faq)。

G0 实测长文、IME、粘贴、可访问语义、Office 组合与目标浏览器。若 Flutter Web surface 不达标，保留模型/内核，启用 DOM surface 备选 ADR；这会增加 UI 维护和排期，必须记录，而非悄悄改成两套模型。

## 4. ADR-03：复用 AppFlowy 协作，公共底座允许领域策略

正文选择 Yrs/Collab，统一更新、origin 和重连追赶机制。Yjs 官方文档说明[增量/状态向量](https://docs.yjs.dev/api/document-updates)及[按 origin 撤销](https://docs.yjs.dev/api/undo-manager)，实际 Rust 固定版本需独立验证。子对象不会因嵌套而自动同步，provider 与授权是必要组成。[子文档](https://docs.yjs.dev/api/subdocuments)。

不选所有类型强制通用 CRDT：Excel 地址语义、记录约束、专业媒体操作需要领域处理。暂不建设多算法通用执行平台；只有具体领域证明现有机制不足才引入额外 engine。

## 5. ADR-04：数据集首期服务端事务

首版数据集与表单业务采用受控 SQL 事务 + outbox，支持字段/记录版本、幂等、权限和事件。它与正文共享对象/命令/作业/事件合同，但不是另一套正文 CRDT。

替代方案为 AppFlowy database adapter：复用已有能力较多，但需要深入迁移其字段、视图、权限与约束，且容易同时产生两份记录真源。本次选择小范围自有事务服务，限制字段与视图种类；G0 若发现现有服务已有合格实现则复用，不重复造表。后续真正多维表格能力按独立领域计划扩展。

## 6. ADR-05：专业内核通过 provider 组合

Word 页、PDF 页、Excel 区域作为独立领域对象视图，渲染与命令通过版本化 provider 接口。首版优先 PDF 已有 page/byte ABI，之后 Word 与工作簿区域；PPT/媒体专业编辑留接口。

本次补查 PDF 产品声明及 `ProductEditBridge.h`：原生是 C++/PDFium 产品会话，Web 由 Emscripten 构建 WASM；不能将它泛称 Rust WASM。现有专业内核可通过 C ABI/FRB 或适配 wrapper 接入，不因公共 Rust 协作底座而重写。

服务端固定版本快照可作为 Web 缺内核时的明确只读模式；它依赖授权上传和网络，不是本地 WASM 编辑门槛的替代品。真正专业协作前必须增加领域操作、稳定锚点、重放及历史。

## 7. ADR-06：扩展声明与可执行能力分层

首版开放有 schema 的元素配置、菜单/工具栏贡献、模板及内置组件应用样板；原生高频编辑面与内核随 Host 发行。后续第三方沙箱表面有明确消息、几何与权限边界。

现有 Resource Extensions v1 是受限浮层与工具 profile，不是任意文档内应用运行时。新 contract 通过版本化 profile 协商，不在旧 manifest/严格协议中无声扩字段。禁用能力须可解释；插件卸载不删除用户 payload。

## 8. ADR-07：Agent 操作与人类编辑共享语义

选择结构化读取/命令、operationId、前置条件与可订阅事件；本地高频 UI 直接调核心，Agent 工具走受权服务。后台 Agent 不能依赖活动桌面文档 broker；身份、授权与模型服务复用现有平台。

不选“每个按键经 Agent/MCP”或只提供 UI 自动化：延迟、可靠性、权限与恢复都不适合作为文档内核接口。批量生成先形成有限 patch，应用策略尊重已授予权限；不对每个普通动作重复确认。

## 9. ADR-08：公开协议与实现版本分别管理

分别记录 object/element/command/collaboration/surface profile、schema/epoch、engine ABI、Host 版本及产品配置版本。不能把一个 SemVer 同时当作内容格式和网络协议版本。

启动按能力求交，不支持则拒写/只读降级。已打开会话固定插件版本；升级可迁移时先建可恢复检查点。底层依赖升级运行跨版本 fixture，不盲目升级到“最新”。

## 10. 当前依赖基线与 G0 冻结要求

截至核查：Flutter vendor Cargo.lock 的 Yrs 0.21.3，Cloud 0.23.5；Web package.json Yjs `14.0.0-1`；Flutter editor override ref `470c4e7`；Cloud Collab patch rev `e59260e524f33104b0ddcd6bb8f6218cad0f7e18`。迁移后的 Flutter Collab path patch 位置缺失。详见[已有证据](../../collaboration/EVIDENCE.zh-CN.md)。

这些是观察值，不是本方案已经选定兼容的组合。G0 以 Cloud 固定版本为锚，冻结完整源码/锁文件/工具链/工作区 patch，选择 native/WASM 都能工作的组合；Web 端不直接继承 vendor 的 Yjs 预发行依赖作为长期承诺。

## 11. 许可证与自主维护

[固定 editor ref 的许可](https://raw.githubusercontent.com/AppFlowy-IO/appflowy-editor/470c4e7/LICENSE)列出 AGPL/MPL 双许可；完整 AppFlowy 客户端、Cloud、思源及其传递依赖分别核查，不能从单个包许可推断整体。PDFium/Office 依赖、字体和媒体资源也需记录来源、修改与可再分发条件。

[官方 AppFlowy-Cloud 仓库](https://github.com/AppFlowy-IO/AppFlowy-Cloud)核查时显示于 2026-09-11 归档。Muse fork 必须承担协议和安全维护，发行需提供适用的对应源码/补丁/构建材料。本文件记录工程交付项，不对最终整体法律适用作结论。

## 12. 决策冻结清单

v1.1 新增的 ADR-09：独立 `muse_collab_contract/runtime` package，Cloud 以 provider/plugin 装配，领域 binding 与 state-engine 按内容模型维护；公共接口不 import Flutter/Office/段落类型。此决策和停用/迁移/权限边界详见 [09](09-COLLABORATION-PACKAGES.zh-CN.md)，先用最小切片验证，再按真实复用需要拆包。

G0 结束必须给出：模型/命令 fixture、固定依赖清单、native/Web 构建证明、树结构并发结果、durable ACK 合同、Office provider 实际模式、数据集事务复用判断、现有 SDK 映射、新 profile 版本、性能基线、许可材料清单与重估排期。任一关键项失败时保留可审查结果，不把“待研究”伪装为已解决选型。
