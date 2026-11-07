# P7：独立数据库资源、共享持久化与生命周期保护

2026-11-06。承接 [思源复用计划](27-SIYUAN-REUSE-AND-DELIVERY.zh-CN.md)、[数据库方案](29-DATABASE-ADAPTER-DESIGN.zh-CN.md)、[横向协作 package 设计](09-COLLABORATION-PACKAGES.zh-CN.md)。这是基础增量的实现记录；完整思源功能和协作验收继续保持未完成。

## 产品与交互落点

保持 SD-BL-1.2、SD-F1 和 SD-MOB-1.3 的冻结快照。数据库复用 [现有独立资源机制](08-PRODUCT-REFINEMENT.zh-CN.md)，提供 `.musedataset` 创建、打开、编辑、保存和上下文提取。该资源与智能文档并列，后续按冻结设计嵌入连续文档编辑区；P7 不把独立资源页面冒充文档内嵌已完成。

Desktop/Web/iOS 使用同一个 Grid surface：视图入口、撤销/重做、新增记录、新增字段、字段菜单和单元格编辑。窄屏保留横向表格滚动及最小 44 点触控入口；文本弹窗由路由拥有输入控制器。字段重命名保留 field ID 和原单元格；键盘退出后恢复原表格。待补齐的筛选/排序、分组、行操作、多视图和文档内嵌继续按 D3/D4 开发，不用无效按钮代替。

实际截图验收发现并修正了列表重复消费系统安全区和新增字段按钮占满整行的问题。原生例程通过 SafeArea 放置共享 surface，行列表显式不再追加 MediaQuery 顶部间距。

## 复用与领域分层

1. 固定 AppFlowy-Collab `e59260e...` 的原 `collab-database` 0.2.0 runtime 提升到独立 `vendor/appflowy_database`，逐文件 provenance、6 个平台适配和许可保留；历史探针仍独立可核验。没有修改思源源码或全局依赖缓存。
2. `dataset/rust` 使用原 Database、DatabaseRow、Field、View、cell reader/writer 和 origin undo manager。Root 类型 1、独立 Row 类型 4，Native 与 WASM 共用；不都伪装为 Document 类型 0。
3. `dataset/flutter` 拥有领域会话与可复用 surface。内核不依赖网络/存储，应用层不读取原生插件私有内存。源未知的字段选项先安全解析，再调用原 upstream 的转换函数；无法解释的值保留原编码并只读。
4. `muse_content_store` 从原文档 File/IndexedDB 适配器提取，供不同内容模型复用；文件写入使用每次独立的同目录 staging，避免并行独立适配器覆盖临时文件。本机语义版本仍由领域拥有者串行保存。旧文档的 IndexedDB 前缀保持不变，已实际重载旧文档验证。
5. `runtime/appflowy_wire` 提取原 full-sync protobuf 与有界 Zstd 解压；原智能文档和 Dataset 共用。`muse_appflowy_transport` 注入 binding/type，不认识字段、段落、行或附件。
6. `Muse-Client/plugins/dataset` 通过公开 SDK 贡献 creator/handler/context。Host 注入持久化和协作能力；历史资源快照使用隔离的只读内存会话，不连接实时 provider，不被 live cache 替换。没有修改生产 Host 的格式路由。

## 已实现的领域边界

- Root 与 Row 的身份、类型、数据库归属、重复引用、字段/视图引用及配额均校验。缺少 Row 状态时显示尚未加载，不用空记录覆盖。
- 文本、数字、复选框和 URL 四种原字段提供 create/rename/add-row/set-cell。数字等格式及 SiYuan 全语义仍需继续对照原语料，不能将原类型存在视为保真验收。
- 单元格 hash 和字段旧名称作为本地命令前置条件，弹窗中的过期草稿不覆盖已收到的更新。该条件不等于服务端全局 CAS；两个尚未收到彼此更新的同一单元格提交仍按原值合并。
- 应用撤销时间线选择 Root 或 Row，反向变更由各自原 Yrs manager 执行；远端 Server origin 不进入本地命令栈。撤销创建记录只撤销视图引用，保留独立 Row 状态以供重做。
- 候选状态先校验，再进入 live session。编码配额在 skip-GC scratch Doc 中计算现有状态与候选状态的并集，避免候选重开 GC 低估 live undo 保留的数据。
- 本机快照按 generation 串行写入；旧保存完成不将新编辑标为已保存，失败时保留当前会话并阻止新命令，显式重试保存。
- 同步冻结根的出站版本和依赖集，先发布其行，再发该根；等待 I/O 期间的新编辑保持 pending。新设备先导入远端原 Root，再加载 Row，避免创建第二棵默认嵌套 Y.Map 与原根竞争。
- 已观察的行身份在继续网络工作前持久化。已见行消失或返回原 RecordDeleted 时，保留本机副本并停止写入；重试、新进程打开不自动重建该行。Root 删除也不自动创建。

## Cloud 删除缺陷与共享修复

真实删除测试发现：软删除后，内存快照或 Redis 未落盘更新可能继续提供旧行。客户端可能因此仍可编辑，不能靠 UI 提示修复。

新增 `database::collab::check_collab_lifecycle`，按 PostgreSQL 注册的 workspace/type/tombstone 判断生命周期，在 full/current cache 读取、batch 读取、HTTP full-sync 入队、直接/排队 upsert、创建路径及原 realtime group 的协议/写入路径使用。普通权限检查仍先执行；生命周期校验本身不授予权限。原库对未注册 ID 的创建路径继续保留，未被描述为新的耐久对象注册协议。

原 `RecordDeleted(-4)` 映射为 `OBJECT_DELETED`，与可创建的未找到状态分离。智能文档和 Dataset 会话分别保留终态；文档暂停/恢复不会清除删除/拒绝访问状态。修复仅覆盖已接入的路径，WS v2、事件失效、删除与队列并发的线性化、完整恢复/撤权和所有写入口领域校验仍需 R4 完整验收。

## 验证和复核

最终凭证落点：[P7 证据目录](execution/phase7-dataset-20261106/result.json)。包含 Rust/Flutter/SDK/中立包测试，真实 Cloud 原对象 1/4 双用户同步、删除保护，以及 macOS/iOS/Web 实际界面与新进程/整页重载。旧 P6 归档不覆盖；旧源锁的 `--source` 因继续开发产生差异是预期，默认历史制品完整性检查仍须通过。

验收只说明本次检查通过。当前没有认证全部字段/视图、同一单元格字符级协作、WS presence、耐久 ACK、完整 ACL/分享/评论/历史、Agent/Office 协作、正式 Host 发布或 Android。

## 下一批的退出条件

1. R4：继续原协议实时订阅与 presence、受权对象集合/动态角色、删除/撤权事件和所有写入口的领域校验；建立耐久检查点/恢复合同，不能把 HTTP 接收或 Redis RID 当作耐久 ACK。
2. D3：授权子会话明确后，依据冻结图将 dataset/view 引用接入智能文档，复用当前 surface；删除嵌入只删引用，不删 Root/Rows。子会话拥有焦点、选区、撤销与滚动，父文档不复制行内容。
3. D4：按 18 类字段、5 类视图清单完成来源块、日期/选项/附件、模板、关联/汇总、筛选排序与多视图同源行为，调用原能力并补齐差异，不另造简化引擎替代。
4. 继续思源编辑/图片/链接剩余项与三端真实 IME、可访问性和性能验收；保留 Android 暂不安装约束。完整 50 项门未通过前不宣布全功能对齐。
