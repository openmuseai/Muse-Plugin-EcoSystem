# 独立 Dataset 领域（持续对齐至 P22）

本目录复用固定 AppFlowy-Collab `e59260e524f33104b0ddcd6bb8f6218cad0f7e18` 的 Database/DatabaseRow、Field、View、type-option reader/writer 和 Yrs undo manager。它不是从零实现的表格数据库，也不以智能文档块 JSON 作为行数据的真源。

- `rust/`：原数据结构上的有界命令、投影、根/行编码、作用域校验、撤销及同步适配，Native 和 WASM 共用。
- `flutter/`：应用会话、持久化/协作注入、共享 Grid 和路线拥有的编辑弹窗。
- `../../../../../Muse-Client/plugins/dataset`：公开 SDK 的 `.musedataset` resource creator/handler/context contributor；不向生产 Host 添加格式分支。
- `../vendor/appflowy_database`：76 个原 runtime 文件、7 处记录在 manifest/patch 中的适配；P21 新增原货币 formatter 的完整容量分组修复。`scripts/verify_database_probe.py` 对历史探针的 6 个补丁和正式副本的 7 个补丁分别校验，并验证补丁可逆到固定原源码。

内容内核不依赖 HTTP、资源路径或编辑器。`muse_content_store` 提供原 File/IndexedDB 持久化，`muse_appflowy_transport` 仅传输 opaque 的原对象类型 1/4，`runtime/appflowy_wire` 复用原 full-sync protobuf 和有界解压。插件拥有资源会话，领域会话拥有 CRDT；暂停网络不改变内容模型或引擎绑定。

已开放文本、数字、日期、复选框、链接、单选、多选七类基础字段与原 Grid 的多个共享视图、按单选字段分组的原 Board 看板。单选/多选复用原 type-option/ID reader-writer，创建时配置初始选项；单元格草稿绑定字段与原值 hash，已有选项的完整并发 CRUD 尚未开放。原未知字段/配置保持编码并只读。创建/重命名字段和视图、创建记录、单元格更新调用原内核；视图切换是本地状态，原 Root1/Row4 与资源引用不复制；弹窗保留旧值 hash，收到更新后拒绝旧草稿。每个单元格当前是原 row cell 值，**同一文本单元格的并发提交使用原 Y.Map 值合并，并非字符级协同输入**。跨单元格并发与原作者撤销已有测试。

每个 Root/Row 独立同步。先上传被冻结根版本引用的行，再发布该根；等待网络时允许继续本地编辑，新引用留到下一轮。已观察到的远端对象身份写入本机检查点后才继续同步；行消失或删除时保留本机内容并停止写入，不通过重试自动重建。完整的级联删除、恢复、权限变更和离线授权策略仍待实现。

运行与验收：

```sh
cargo test --locked --manifest-path dataset/rust/Cargo.toml
python3 scripts/build_dataset_web_core.py
python3 scripts/verify_database_probe.py
python3 scripts/verify_dataset.py --device macos
```

Flutter 局部测试须在 `dataset/flutter` 运行；Cloud 测试依赖 `.build/e2e-fixture.json` 的本机合成账户。原生例程为 `flutter/example/lib/dataset_main.dart`，浏览器例程为 `flutter/web_example/lib/dataset_main.dart`。两者仅是验收工作台；没有发布生产 Host。Android 按用户约束不安装、不运行。

与思源 18 类字段、5 类视图的完整差距、冻结设计与后续嵌入条件，见 [P7 实施报告](../../docs/smart-document/v1/30-PHASE7-DATASET-IMPLEMENTATION.zh-CN.md) 和 [数据库适配方案](../../docs/smart-document/v1/29-DATABASE-ADAPTER-DESIGN.zh-CN.md)。

P9 字段与交互进度见 [数据库字段持续对齐](../../docs/smart-document/v1/32-PHASE9-DATABASE-FIELDS.zh-CN.md)。输入上限不是已验证的可交互容量；全部思源字段、五视图和文档嵌入继续按原计划推进。

P24 看板与协作验收见 [单选分组看板](../../docs/smart-document/v1/47-PHASE24-SINGLE-SELECT-BOARD.zh-CN.md)。卡片只是原行的分组投影；原 GroupSetting 与 Option ID 驱动列，移动和详情修改继续写同一 Row4，不新增卡片存储。
