# 智能文档开发交接

日期：2026-11-07，Asia/Shanghai。状态：**代码与既有证据已按职责细分为本地提交；没有推送远端。最新冻结切片 P24；P25 块公式的 Native 部分通过，Web 全链与执行冻结未完成；完整产品 NOT COMPLETE。**

先读 [进度盘点](49-PROGRESS-REVIEW-20261107.zh-CN.md) 和 [更新计划](50-REVISED-DEVELOPMENT-PLAN.zh-CN.md)，实际接力从 **SDR-01** 开始。不要重新讨论架构、重写 CRDT 或把 P25 直接改成已完成。

## 1. 提交与检出

[机器可读细粒度提交清单](handoff-commits.json) 记录本次代码/设计/证据提交，共 53 个；本交接文档所在的最后一个文档提交不自包含在该清单，避免自引用哈希。下列 HEAD 是文档提交前的位置；插件仓库实际检出应包含本交接所在提交。

| 仓库 | 文档提交前 HEAD | 清单中提交数 |
| --- | --- | ---: |
| Muse-Client | `6d103f0d12ba` | 10 |
| AppFlowy-Cloud | `ae59eb0124ac` | 4 |
| Muse-Plugin-Ecosystem | `75a4c8c8144b` | 39 |

拆分原则：Client 分为合同、资产引用、嵌入、存储、HTTP、实时、在线 UI、两个 SDK 插件和公式依赖锁；Cloud 分为 Yrs GC 修复、生命周期/授权、私有附件与字节保护；插件分为原依赖、运行时/探针、P24 内核/界面/数据集、P25 公式增量及来源，再逐阶段提交 P3–P24 冻结证据。**中间提交是评审单元，运行产品请使用匹配的完整仓库集合。**

P24 文档/Rust/Flutter 基础部分按已冻结的 P24 源字节入库，随后再提交 P25 差异；没有改写历史档案或覆盖当前工作区。受控上游和冻结档案配置了字节保留，避免换行转换破坏 manifest。生成缓存和携带凭据的应用构建物没有入库。

原有 PDF、Word、表格、其它 Host 工作及 Cloud 的 deploy.env、.collab-demo.env、scripts/tmp.txt 保留在工作区。后续先按路径检查差异，不执行全仓 reset/clean/stash，也不把其它任务改动合入本功能。

## 2. 目录与职责

保持三个仓库相邻，当前工作区为 `/Users/mac/src/openmuse-io`：

| 目录 | 职责 |
| --- | --- |
| Muse-Plugin-Ecosystem/plugins/markdown/smart_document/rust | 原 Document/Yrs 领域、稳定地址、事务/校验与 FFI |
| smart_document/flutter | 公共 Flutter 编辑面、控制器、文件/浏览器持久化 port、Native hook |
| smart_document/dataset/rust 与 dataset/flutter | 独立原 Database Root1/Row4、字段/视图/规则/看板及共用 surface |
| smart_document/runtime | 原 protobuf/full-sync、awareness FFI 与测试网关 |
| smart_document/vendor | 固定 runtime、受控补丁和原实现参照；不是另一个知识库真源 |
| Muse-Client/packages/muse_* | 中立绑定/存储/传输/嵌入与协作 UI 包 |
| Muse-Client/plugins/smart-document、plugins/dataset | 公开 SDK 资源创建、会话、检查点和 handler/context 贡献 |
| Muse-Server/AppFlowy-Cloud | 原服务、原始写入口授权、生命周期、私有资产与原 Yrs 修复 |
| docs/smart-document/v1 | 冻结设计、功能账本、执行证据、更新计划与本交接 |

内容内核与协作模型保持水平解耦。文档只保存子资源 reference/selector；数据库和 Office 保持自身模型/会话。Root1 与 Row4 是原数据库对象类型，正文是 Document0；不能擅自给未知 wire type 6 分配新内容类型。生产 Host 的全局 registry/session pool/继承权限仍未完整交付，workbench 通过不能替代它。

## 3. 当前可依赖的状态

- P24：[结果](execution/phase24-single-select-board-20261107/result.json) 与 [实际视觉](board-functional-review/index.html) 已冻结。Dataset Rust 66、Flutter 64、公共 SDK 3；两种 Apple 目标各 9 UI + 3 重开；Web 11 / Bob 10 / 离线 6；Cloud 重启 Native 回读 7。
- P25：Document Rust 31、常规文档测试 51；macOS/iOS 各 9 UI + 3 独立进程重开。[进度回执](progress/20261107/p25/macos/result.json)、[iOS 回执](progress/20261107/p25/ios/result.json) 已保存；**没有 P25 完整执行冻结目录**。
- 8 个 Client 包测试通过，智能文档 SDK 与 Web 静态分析通过。冻结档案校验和数学 vendor 校验通过；从已提交 Git 内容导出的 22 组证据及 3 个来源校验也全部通过，共 25 项，详见 [导出校验](progress/20261107/git-export-checks.json)。
- 原完整文档命令曾因旧真实文件选择器 fixture 缺少标记图片而失败；日志在 [诊断](progress/20261107/p25-document-full-with-stale-filepicker.log)。只给探针增加了 manual-browser-filepicker 标签，全部断言仍保留；常规 51 项不包含这项需实际 UI 前置的探针。
- 50 家族中 28 partial / 22 planned，完整家族关闭 0。不要把这些计数当工程完成百分比。完整 gate 当前应失败。

## 4. 环境恢复与验证命令

以下在当前工作区执行；若机器路径不同，保持仓库相邻并调整工作区根。依赖：当前匹配的 Flutter/Dart、Rust Apple/WASM target、固定 wasm-bindgen 0.2.128、Python、patch、Docker 和 Xcode。原始依赖/锁文件为准，不擅自升级。

```sh
cd /Users/mac/src/openmuse-io/Muse-Plugin-Ecosystem/plugins/markdown/smart_document
python3 scripts/dev_stack.py status
python3 scripts/dev_stack.py start
```

只管理 Compose project `muse-smart-document-stage1`。端口：Cloud 18000、Postgres 15432、Redis 16379、GoTrue 19999、MinIO 19000。当前检查均健康。独占 Cloud PID 由 `.build/stack/cloud.pid` 跟踪，`dev_stack.py` 会核对进程，不得为了端口冲突杀其它服务或删除卷。

新机器还需在 Cloud 仓库构建匹配服务：

```sh
cd /Users/mac/src/openmuse-io/Muse-Server/AppFlowy-Cloud
SQLX_OFFLINE=true cargo build --locked --bin appflowy_cloud
```

提交并不会自动替换现有服务进程。当前本机服务仍是此前验收的 P19 删除修复二进制；若重建，记录新二进制摘要，并在没有活动 UI/同步验证时才重启。

合成账号/工作区需要新建或过期时：

```sh
cd /Users/mac/src/openmuse-io/Muse-Plugin-Ecosystem/plugins/markdown/smart_document
python3 scripts/provision_e2e.py
```

该命令会覆盖私有 `.build/e2e-fixture.json`，创建新的合成账号/工作区，并不迁移旧回执 objectId。**先保存旧测试引用，使用独立 fixture 或新跑 Native，不可把新凭据与旧资源随意拼接。** 凭据文件 0600、已忽略；不打印 token、URL token、编码 DartDefines，不提交 .build 或应用 main.dart.js。

常规检查：

```sh
cd /Users/mac/src/openmuse-io/Muse-Plugin-Ecosystem/plugins/markdown/smart_document
python3 scripts/verify_parity.py
python3 scripts/verify_math_vendor.py
python3 scripts/verify_database_probe.py
cargo test --locked --manifest-path rust/Cargo.toml
cargo test --locked --manifest-path dataset/rust/Cargo.toml
```

```sh
cd /Users/mac/src/openmuse-io/Muse-Plugin-Ecosystem/plugins/markdown/smart_document/flutter
flutter test --exclude-tags=manual-browser-filepicker
```

数据库测试使用独立子包目录：

```sh
cd /Users/mac/src/openmuse-io/Muse-Plugin-Ecosystem/plugins/markdown/smart_document/dataset/flutter
flutter test
```

复跑原生公式：

```sh
cd /Users/mac/src/openmuse-io/Muse-Plugin-Ecosystem/plugins/markdown/smart_document
python3 scripts/verify_formulas.py --device macos
python3 scripts/verify_formulas.py --device 5F0D9070-BE32-4063-BF7D-B7EB3B48D105
```

iOS ID 是当前 iPhone 17 Pro / iOS 26.5 模拟器，换机器用实际 iOS 目标。iOS bundle ID 为 `io.openmuse.museSmartDocumentStage1`，macOS 为 `com.example.museSmartDocumentStage1`。**用户持续约束：不安装、不运行 Android。** 不在 Native 集成测试期间读取 Native AX 树，以免破坏语义句柄；截图文件可直接查看。

## 5. 下一步：SDR-01 的具体未完成项

已有代码：`flutter/web_example/lib/formula_main.dart`、`formula_commands.dart`、`formula_components.dart`、`rust/src/formulas.rs`、Native 集成测试和 `scripts/verify_formulas.py`。Web 风格提示已修正，但没有真实浏览器验收回执。

1. 以新跑或当前有效的 macOS 回执派生 FORMULA_OBJECT / FORMULA_BLOCK / FORMULA_NATIVE_SOURCE / SMARTDOC_RUN 等公共配置。当前本机原始回执在 `.build/formula-runs/20261106T233624Z-formula-52f77f12dd23`；iOS 为 `20261106T233804Z-formula-4cf62c0e79ae`。新环境不能假定旧 Cloud 数据存在。
2. 实现 `serve_formula_fixture.py` 的回执白名单和固定工作区代理，及 `formula_web_readback_test.dart`；参考 P24 server/读回，但正文只有 Document0，不能照搬数据库 Root1/Row4 和字段。
3. 当前 50946 实际运行 **serve_board_fixture.py / board-web**，不是公式页面；替换前核对该监听 PID 的脚本和两端已离开。50940 是更早实时验收页，用户可能正在看；不把它当最新公式实现，不擅自关闭用户标签。
4. 生成忽略的 `formula-web-public.json` / `formula-web.private.json`，再运行 `scripts/build_web_core.py` 和 Flutter Web 构建。保持同一 Native objectId/formulaId 和原字体，不创建独立示例文档假装互通。
5. 执行两账号真实 UI：各自原帧/HTTP 暂存后证明分支、释放合并、旧公式草稿拒绝、原 undo/redo、新建第二公式；离线重开后关闭双方，再重启自有 Cloud 做无缓存 Native 回读。
6. 实现 P25 evidence collector/verifier 和实际视觉关联，核对源码、ABI、WASM/字体、App JS 摘要、原始失败。应用 JS 含构建凭据时只能记录摘要，不复制字节入归档。
7. 冻结 P25 后更新账本/计划；SY-07 仍保留行内/完整 KaTeX 等缺口。再完成 SDR-02 的干净 Native/Web/Cloud 复建及 SDR-03 的 fixture 隔离。

源码中的浏览器流程尚未跑通，**不预先宣称其用例数量或结果**。Root Document history 返回的是 snapshot；Web `_HistoryCore` 观察的是真实返回 formula，不能套用 Dataset 的 historyApplied 字段。

## 6. 关键实现约束与已踩问题

| 位置 / 主题 | 接力要求 |
| --- | --- |
| 公式格式 | 原 math_equation + formula 字符串，无平行 Y.Text；同一公式仍为原属性替换，不是字符级协作 |
| 公式草稿 | 按对象/块 ID 和旧值摘要提交；摘要只拒绝已观察到的旧输入，不是全局 CAS |
| 公式 renderer | 原 0.7.3、381 文件、原公开包摘要；一个布局回调兼容补丁，不改全局 pub 缓存 |
| 渲染限制 | 新输入 8192 UTF-8 字节；更大有界旧源保留。宏/尺寸/链接等不在当前渲染配置内，不能清空不支持的 TeX |
| UI 与 fake async | Headless 测试的挂载 UI 和真实异步队列需共同推进；formula_test 的 domain helper 不能简化成跨调度区直接 await 后误判挂死 |
| 原生测试 | 无 Native AX；严格命中仍开启。iOS 用可见区域真实滑动，不能关闭命中检查掩盖屏外点击 |
| Client/Cloud Yrs | 保留 P19 GC 前缀删除尾部修复；客户端另有 bounded undo 补丁，不能升级/替换时丢掉它们 |
| 视图与字段 | 原隐藏主视图维护成员、FieldMap 维护 schema；读取派生缺少成员/字段，不做读时 CRDT 修补或重建 |
| 会话与权限 | 保存失败保留 owner；父只读只缩小子能力，不能改变子资源原授权；服务端能力仍是后续门 |
| 冻结证据 | `execution/*` 和 `baselines/*` 不覆盖、不重写 hash。旧档案 --source 随代码演进不匹配是预期 |
| 运行顺序 | Cloud 重启与实时测试不可并行；pub/analyze 不与同一个 Native Xcode 构建争用项目 |

## 7. 当前限制与接力退出条件

生产 Host 装配、全局会话池、继承权限、多实例即时撤权、durable ACK/outbox、完整结构并发、全部表格/数据库能力、私有分享/评论/历史、Agent、真实 Office 与格式桥仍未关闭。编辑家族与协作家族的完整目标不变。

本次本地提交解决“代码散落且不可移交”的检查点问题；**没有完成干净机器复建，没有发布生产 Host，也没有通过完整功能门。** 后续提交前按工作包验收，所有差异与失败继续留痕。校验本交接与工作包：`python3 docs/smart-document/v1/scripts/verify_development_plan.py --current --git`（在 markdown 目录）。


## 8. 回退与故障处置

尚未发布生产版本，提交只是本地开发检查点。若要回退，在隔离分支评审并按本任务提交集反向回退，保持 Client/插件/Cloud 版本匹配；不要全仓 reset/clean 或覆盖其它产品改动。先保留新模型文档、离线草稿和私有 fixture，不让能力不足的旧写入端改写新数据。

同步/保存失败时优先保留当前 owner、检查点和原始失败语料；不能通过清空数据库、删除 Docker 卷、重建同名对象或覆盖归档来使测试通过。P19 的 GC 删除修复与客户端 bounded undo 也不能在没有对应恢复与回归证据时单独移除。

`--current` 只用于比较本次盘点与当前账本。后续开发改变状态后，省略该参数可验证历史交接；新评审另存快照，不改旧证据制造“当前一致”。
