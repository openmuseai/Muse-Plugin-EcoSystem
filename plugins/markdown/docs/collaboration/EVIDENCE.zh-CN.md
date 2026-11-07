# 代码证据、版本与核查范围

> 范围更新：用户已将目标明确为面向 Agent、异构元素同屏、Office 扩展与 Mobile/Web/Desktop 的智能文档平台。最新决议见 [智能文档架构](../smart-document/README.zh-CN.md)。本文件保留前一轮受限编辑器融合评估；其中 AppFlowy Document 作为永久公共模型的建议与 12–18 周排期不适用于新目标，依赖/源码事实仍可参考。

核查日期：2026-11-04。所有相对链接从本目录解析；行号会随版本变化。结论优先依据本地源码，在线资料只补充上游状态和机制说明。

## 1. 本地仓库基线

| 仓库 / 位置 | 本次 HEAD 或固定版本 | 核查备注 |
| --- | --- | --- |
| Muse-Plugin-Ecosystem | `f36510e946f445fce58438fe3cd5074dae974060` | 存在其他未跟踪目录/证据，不属于本次变更 |
| `vendors/siyuan` | `d3af9d5782082b379d45a69eedf4ebcfe8ba6889` | `upstream.json` 指定版本 3.8.9 |
| `vendors/appflowy/client` | `17e24f8232488fdac1213b17445af7dd4fb07ad2` | 有未跟踪文档；依赖路径迁移后不可直接使用 |
| `vendors/appflowy/web` | `3356a616babf486a0db9acc19efeea6f50a1f238` | 有 README、package.json、部署配置等未提交改动；以当前工作区内容核查 |
| `Muse-Server/AppFlowy-Cloud` | `5b44ac485f6dc1a17bb7366027c300aa87868e59` | 有部署配置等未提交改动；未读取密钥内容、未连接生产服务 |
| Flutter appflowy_editor | pubspec override ref `470c4e7` | 不以网上最新版代替固定依赖 |
| Flutter Collab | Cargo 本地 path patch | 当前路径缺失；不能从 HEAD 推断具体传递源码 |
| Flutter client-api | git rev `592f644`；锁文件含完整提交 | 不等于当前 Muse Cloud HEAD |
| Flutter Yrs | Cargo.lock `0.21.3` | manifest 写 `0.21.0`，解析结果以 lock 为准 |
| Cloud Collab | Cargo patch rev `e59260e524f33104b0ddcd6bb8f6218cad0f7e18` | 仍需冻结对应传递依赖源码 |
| Cloud Yrs | Cargo.toml / Cargo.lock `0.23.5` | 更新有专门兼容测试说明 |
| Web Yjs | 当前 package.json `14.0.0-1` | 精确安装/锁文件与实际构建在 G0 冻结 |

仓库存在未提交修改，HEAD 表不能单独用作复现清单。本次未覆盖、回滚或暂存这些修改；G0 应另存源码摘要与 patch。

## 2. 关键判断的本地依据

| 判断 | 证据入口 | 源码所能证明的范围 |
| --- | --- | --- |
| 现有思源插件是 Flutter + WebView + Go 本机内核 | [当前 README](../../README.zh-CN.md)、[Flutter pubspec](../../flutter_runtime/pubspec.yaml)、[resource_view.dart](../../flutter_runtime/lib/src/resource_view.dart) | 描述与实现承载方式；不证明远端多人协作 |
| 资源保存使用原生归档和 CAS | [资源设计](../resource-adaptation/DESIGN.zh-CN.md)、[resource_document.dart](../../flutter_runtime/lib/src/resource_document.dart)、[web resource 入口](../../web/resource_entry.ts) | 现有资源/包处理与桥；本次没有逐项审计所有 Host SDK API |
| Protyle 更新数据是 DOM 语义而非现成 CRDT 字符增量 | [transaction.go](../../vendors/siyuan/kernel/model/transaction.go) 的 `doUpdate` / `Operation` | `Data` 转字符串，`BlockDOM2Tree`，定位旧节点和替换验证 |
| 思源事务经本机接口及推送 | [api/transaction.go](../../vendors/siyuan/kernel/api/transaction.go)、[transactionQueue.ts](../../vendors/siyuan/app/src/protyle/util/transactionQueue.ts) | 现有事务提交与广播；不能推导离线分布式合并正确性 |
| Flutter editor 与 backend 文档模型有显式适配 | [editor_transaction_adapter.dart](../../vendors/appflowy/client/frontend/appflowy_flutter/lib/plugins/document/application/editor_transaction_adapter.dart) | 注释说明树到平面结构；正文分为 external text delta 和 block actions |
| editor 包不包含完整 Cloud 协作 | [document_service.dart](../../vendors/appflowy/client/frontend/appflowy_flutter/lib/plugins/document/application/document_service.dart)、[Rust document](../../vendors/appflowy/client/frontend/rust-lib/flowy-document/src/document.rs) | 通过 protobuf/dispatch 进入 Rust 文档服务，存在 UI 以外依赖 |
| 本地及云 Collab provider 可以复用 | [collab_builder.rs](../../vendors/appflowy/client/frontend/rust-lib/collab-integrate/src/collab_builder.rs) | Local / AppFlowyCloud provider，RocksDB/IndexedDB 条件持久化、workspace依赖 |
| 固定编辑器 ref 及 Git 依赖 | [Flutter pubspec](../../vendors/appflowy/client/frontend/appflowy_flutter/pubspec.yaml)、[Rust Cargo.toml](../../vendors/appflowy/client/frontend/rust-lib/Cargo.toml)、[Cargo.lock](../../vendors/appflowy/client/frontend/rust-lib/Cargo.lock) | 依赖声明、override、解析版本；不代表当前位置已成功构建 |
| Web 的 Document 由块、children、Y.Text 构成 | [application/types.ts](../../vendors/appflowy/web/src/application/types.ts) 的 `YDocument/YBlock/YTextMap` | Web 类型声明；最终 Flutter Rust schema 需 fixture 冻结 |
| Web 已有协作/outbox/awareness 代码可参考 | [sync-protocol.ts](../../vendors/appflowy/web/src/application/services/js-services/sync-protocol.ts)、[sync-outbox](../../vendors/appflowy/web/src/application/sync-outbox/index.ts)、[package.json](../../vendors/appflowy/web/package.json) | 状态向量、update flags、远端 origin、outbox flush；flush 注释明确不等价于硬耐久保证 |
| Web 使用 v2 WS | [useAppflowyWebSocket.ts](../../vendors/appflowy/web/src/components/ws/useAppflowyWebSocket.ts)、[messages.proto](../../vendors/appflowy/web/src/proto/messages.proto)、[collab.proto](../../vendors/appflowy/web/src/proto/collab.proto) | URL 构造、protobuf 外层、状态向量/版本等字段 |
| Cloud 同时暴露 v1 与 workspace v2 路由 | [src/api/ws.rs](../../../../../Muse-Server/AppFlowy-Cloud/src/api/ws.rs) | `ws_scope` 的 `/v1` 与 `/v2/{workspace_id}`；不证明生产代理/部署状态 |
| 旧消息与 v2 是不同实现链 | [message.rs](../../../../../Muse-Server/AppFlowy-Cloud/libs/collab-rt-entity/src/message.rs)、[v2 session](../../../../../Muse-Server/AppFlowy-Cloud/services/appflowy-collaborate/src/ws2/actors/session.rs)、[v2 messages.proto](../../../../../Muse-Server/AppFlowy-Cloud/libs/appflowy-proto/proto/messages.proto) | 旧链 bincode，v2 appflowy-proto；不能混用 envelope |
| 服务端了解 Document，不是纯透明字节转发 | [group_init.rs](../../../../../Muse-Server/AppFlowy-Cloud/services/appflowy-collaborate/src/group/group_init.rs)、[collab ops](../../../../../Muse-Server/AppFlowy-Cloud/src/biz/collab/ops.rs) | `validate_require_data`、`DocumentBody` 提取文本等；新增类型需链路验证 |
| Cloud 依赖版本及升级兼容要求 | [Cargo.toml](../../../../../Muse-Server/AppFlowy-Cloud/Cargo.toml)、[Cargo.lock](../../../../../Muse-Server/AppFlowy-Cloud/Cargo.lock)、[yrs_version 测试说明](../../../../../Muse-Server/AppFlowy-Cloud/tests/yrs_version/README.md) | 升级前需测试旧编码解码兼容；本次未运行这些测试 |
| 本地 OSS fork 已有差异对齐工作 | [oss-cutover 索引](../../../../../Muse-Server/AppFlowy-Cloud/docs/oss-cutover/README.zh-CN.md)、[c4_collab.rs](../../../../../Muse-Server/AppFlowy-Cloud/tests/oss_cutover/c4_collab.rs) | 有合同、权限/guest、验证计划；该测试可在缺环境时跳过，文件存在不等于环境验收通过 |

缺失路径检查：Rust workspace 位于 `vendors/appflowy/client/frontend/rust-lib`，其 `../../../../vendors/AppFlowy-Collab/collab` 在当前目录解析为 `plugins/markdown/vendors/vendors/AppFlowy-Collab/collab`，核查时不存在。这是路径/依赖包需要补齐，不意味着上游库不存在。

## 3. 许可来源与在线一手资料

* 思源 [LICENSE](../../vendors/siyuan/LICENSE)，完整 AppFlowy 客户端 [LICENSE](../../vendors/appflowy/client/LICENSE)，Web [LICENSE](../../vendors/appflowy/web/LICENSE)，Cloud [LICENSE](../../../../../Muse-Server/AppFlowy-Cloud/LICENSE)：本地许可文件，不据此自动推断所有第三方依赖同一许可。
* [固定 appflowy_editor ref 的 LICENSE](https://raw.githubusercontent.com/AppFlowy-IO/appflowy-editor/470c4e7/LICENSE)：明确列出 AGPL 与 MPL 双许可；应与整个 AppFlowy 客户端区分。
* [AppFlowy-Cloud 官方仓库](https://github.com/AppFlowy-IO/AppFlowy-Cloud)：核查时显示 2026-09-11 归档。其归档不影响 Muse 已持有源码的继续开发，但增加自主维护成本。
* [AppFlowy-Collab 官方仓库](https://github.com/AppFlowy-IO/AppFlowy-Collab)：用于识别上游来源；不能替代本地固定 rev 及 path patch 的精确源码。
* [Yjs Document Updates](https://docs.yjs.dev/api/document-updates)：增量更新、幂等合并及状态向量机制。
* [Yjs UndoManager](https://docs.yjs.dev/api/undo-manager)：可按 origin 控制撤销范围。
* [Yjs Relative Positions](https://docs.yjs.dev/api/relative-positions)：稳定位置锚点，删除后可能无法解析。

在线信息仅用于这里对应的具体判断；方案不依赖第三方博客对功能、商业许可或实现细节的推断。

## 4. 核查与推断的区分

已核查：上述目录/源码存在，文档和关键实现，Git 基线及部分工作区状态，声明/锁定依赖版本，Cloud 双 WS 路由，缺失 path，上游归档状态及固定编辑器许可。

工程推断：推荐路线、模块拆分、性能目标、人周和日历估算、完整思源兼容的风险等级，均是基于现有代码的设计判断。需要 G0 运行证据才能将其转为实施承诺。

未验证：完整插件重建、三客户端交叉运行、Yjs 14 与 Yrs 编码/语义互通、真实多人冲突、生产 Cloud/代理配置、线上安全与负载、全量原生思源样本兼容、最终许可适用边界。
