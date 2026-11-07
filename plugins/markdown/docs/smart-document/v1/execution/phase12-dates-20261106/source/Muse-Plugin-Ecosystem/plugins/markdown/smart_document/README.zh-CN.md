# 智能文档：原生、Web 与 Mobile 实现

正在推进：[P12 嵌入资源键盘边界与原日期字段](../docs/smart-document/v1/35-PHASE12-EDITOR-INTERACTION-DATES.zh-CN.md)。保持原编辑/协作内核和冻结交互，继续逐项验收。

已归档：[P11 独立数据库实时协作适配](../docs/smart-document/v1/34-PHASE11-DATASET-REALTIME.zh-CN.md)。原 WS2 的类型 1/4、动态新行和单元格在线状态已通过真实 Cloud、公共插件及 macOS/iOS/Web 增量验收，328 份文件已归档。

已归档：[P10 文档内数据库与独立资源界面贡献](../docs/smart-document/v1/33-PHASE10-EMBEDDED-DATASET.zh-CN.md)。复用原数据库引用块及共享 Grid，三端增量与独立协作边界已验收；完整产品门仍未通过。

当前增量：[P9 数据库字段与视图持续对齐](../docs/smart-document/v1/32-PHASE9-DATABASE-FIELDS.zh-CN.md)。单选/多选、真实三端 UI 与原生/浏览器对象往返已推进，完整功能门仍未通过。

最新增量：[P8 实时协作与界面接入](../docs/smart-document/v1/31-PHASE8-REALTIME-IMPLEMENTATION.zh-CN.md)。原 WS v2、Yrs Awareness、公共插件注入及 macOS/iOS/Web 切片通过；完整编辑/协作门仍未通过。

产品基线 [SD-BL-1.2](../docs/smart-document/v1/13-FROZEN-BASELINE.zh-CN.md)；阶段开发计划/方案 [SD-F1](../docs/smart-document/v1/16-PHASE1-IMPLEMENTATION.zh-CN.md)；[实际验收报告](../docs/smart-document/v1/17-PHASE1-ACCEPTANCE.zh-CN.md)。

复用当前 Muse Cloud 的 AppFlowy-Collab revision `e59260e524f33104b0ddcd6bb8f6218cad0f7e18` / Yrs 0.23.5 和固定 Flutter editor。新增 Rust 领域包装、Flutter surface、真实本机保存、原 Cloud full-sync provider，以及 `Muse-Client/plugins/smart-document` 的公开 SDK 贡献。旧思源插件不自动转换或迁移。

最新推进（2026-11-06）：[P7 独立数据库与生命周期保护](../docs/smart-document/v1/30-PHASE7-DATASET-IMPLEMENTATION.zh-CN.md)。原 Database/Row、公开 SDK 数据库插件、中立存储/传输、基础 Grid 与三端增量验收；完整思源数据库和协作仍未完成。

此前推进：[P5-A 表格编辑与协作](../docs/smart-document/v1/26-PHASE5-TABLE-IMPLEMENTATION.zh-CN.md)。三端接通固定网格真实富文本单元格、同格/异格并发、origin undo 与离线恢复；可变行列、完整思源编辑/协作仍待后续门槛。

上一批（P4）：[完整思源编辑与协作开发门](../docs/smart-document/v1/24-SIYUAN-PARITY-PLAN.zh-CN.md) · [P4 实施与三端证据](../docs/smart-document/v1/25-PHASE4-IMPLEMENTATION.zh-CN.md)。已实现稳定块类型命令、H1–H6、Markdown 块触发和字面多行代码，macOS/Web/iOS 原 Cloud 切片通过，50 项完整门尚未完成。

此前增量：[Web/协作合同实施](../docs/smart-document/v1/18-WEB-COLLAB-IMPLEMENTATION.zh-CN.md) · [浏览器/native 互通验收](../docs/smart-document/v1/19-WEB-COLLAB-ACCEPTANCE.zh-CN.md)。Web 仍复用同一 Flutter 控制器、编辑面与 Rust 核心，使用 WASM loader 和 IndexedDB；独立协作端口位于 `Muse-Client/packages/muse_collab_contract`。

## 运行与验证

本阶段实测环境为 macOS ARM64、Flutter 3.44.2/Dart 3.12.2、Rust 1.96.0、Xcode 和 Docker。准备好这些工具后，从此目录运行：

```sh
python3 scripts/verify_phase1.py --native
```

该命令编译内核/Cloud、运行领域和 Flutter 测试、检查旧合同 golden、启动隔离基础设施、创建合成账号、执行双账号 Cloud 测试并运行真实 macOS app 的端到端测试。证据写在 `.build/verification/<runId>/`；服务缺失/失败会报错退出，不会 skip 后当作成功。`--native` 需要 macOS/Xcode；不传该参数只运行领域/Cloud 验证。

如果要交互运行已配置的原生验证宿主：

```sh
cd flutter/example
flutter run -d macos --dart-define-from-file=../../.build/native-defines.json
```

`native-defines.json` 只在验证时生成，含本地合成测试账号的凭据，位于忽略目录，不能归档到产品稿、源码或公开发行包。省略 `--dart-define-from-file` 可运行本机模式。资源实际存放在验证宿主沙箱的 Application Support 下，与既有 Muse 数据分开。

停止本轮隔离环境（保留测试卷）：

```sh
python3 scripts/dev_stack.py stop
```

Compose project 为 `muse-smart-document-stage1`；只使用回环端口 15432、16379、19999、19000、18000，不操作现有 `muse-*` 容器。镜像 digest 在 `infra/images.lock.json`，Rust/Dart 精确依赖在各自 lock 文件。

## Web 构建与端到端

需要 `wasm32-unknown-unknown` target 与 `wasm-bindgen-cli 0.2.128`，从本目录运行：

```sh
python3 scripts/build_web_core.py
python3 scripts/verify_phase2.py
```

第二个命令还会执行整套 native 回归，然后等待浏览器页面的实际验收回执和整页重载回执，最后由 native 读回 Web 修改。没有浏览器结果不会宣告通过。普通本机 Web 从 `flutter/web_example` 运行 `flutter run -d web-server --web-port=18080`，不注入测试账号；端口被本轮服务占用时先停止该服务，不能抢占其他进程。详细步骤见最新实施/验收文档。

## 代码边界

* `rust`：一个权威 `collab_document::Document`，UTF-16、稳定块、增量/marks、候选校验、原生 origin undo、FFI 和现有同步 wire。
* `flutter`：AppFlowy 事务适配、可重建投影、本机/协作独立状态、独立 provider/store 端口、native build hook 和编辑面。
* `vendor/appflowy_editor`：原 revision 运行时子集和许可；三个文件的兼容/适配补丁由 `openmuse-upstream.json` / `openmuse.patch` 说明，不修改全局 pub cache。
* `flutter/example`：真实公共 SDK workbench，复用现有 `LocalResourceProvider`、`ResourceCenterHub`、`ResourceEditorSession` 和 CAS 检查点；不是新的生产 Host。
* Cloud 有两处必要修复：HTTP full-sync 入队前写权限/路由校验，以及相等 state vector 仍传递删除集合。没有升级 wire 或另起协作服务器。

可编辑内容为段落、H1–H6、列表/待办、引用、基础多行代码、固定网格表格、分隔线及基础 marks；嵌套内容经过同一结构校验。可变表格拓扑/合并、代码/公式专业编辑、媒体、Office、评论/历史/Agent 和数据集不在此阶段完成声明中。插入/slash 只显示已经接通的元素，不以无效按钮冒充功能。

## 诚实的状态与限制

UI “已保存到本机”取决于实际文件写入/flush；写失败保留内存修改并阻止安全关闭。尚未实现的内容操作明确报错，用户可以显式放弃该操作恢复已保存内容。资源文件 CAS 是持久检查点，不是在线协作合并器。

“协作服务已接收”表示原 HTTP exchange 成功，不等于 durable ACK。本阶段按固定间隔同步，没有 WebSocket 推送、在线头像或远端光标。删除集合修复由实际 undo/删除跨端用例覆盖；Cloud 重启读取另外验证。

已验证 macOS 原生、Web 真 Rust WASM/IndexedDB、二者经真实 Cloud 互通；Mobile 完整能力、Web 完整输入/性能/语义、人工中文 IME、断电/驱逐、性能、完整权限角色和完整 0.1 尚未认证。build hook 对未支持的平台明确拒绝，当前插件未默认加入正式 Host 发行装配。后续按阶段门完善，不将本轮小闭环宣告为全部 AC-01–17 通过。

Native code asset 的构建/捆绑采用 Dart 官方 [build hook 机制](https://dart.dev/tools/hooks)，使运行程序从自己的产物加载 Rust 库，而非依赖临时库路径。

固定 Collab 的浏览器 clock 补丁位于 `vendor/appflowy_collab`；原始来源、哈希与 patch 同时保留。Cloud 回包统一用固定纯 Rust zstd decoder，编码不变。当前 Web 内容 workbench 与正式 Web Host 装配分开；SDK 智能文档插件的默认存储仍为 native，不宣称已完成 Web 资源中心接入。

停止本轮浏览器审阅服务：从 `smart_document` 运行 `python3 scripts/stop_web_fixture.py`。脚本核对登记 PID 的实际命令，仅停止本任务服务器，保留 IndexedDB 与独立 Cloud；可加 `--dry-run` 先做只读检查。


Mobile 最新增量：[完整产品交互与视觉稿](../docs/smart-document/v1/22-MOBILE-DESIGN-REVIEW.zh-CN.md) · [M3-A 实施与实际验证](../docs/smart-document/v1/23-MOBILE-IMPLEMENTATION.zh-CN.md)。已实现 iOS 首批本机编辑/保存/新进程重开；本批恢复隔离后端后通过 iOS 双账号原 Cloud 同步。完整协作业务和全量编辑仍待完成，详见 [P4](../docs/smart-document/v1/25-PHASE4-IMPLEMENTATION.zh-CN.md)。
