# 数据库领域适配、跨端内核与实施顺序

2026-11-06，CR-SD-REUSE-20261106。承接 [复用计划](27-SIYUAN-REUSE-AND-DELIVERY.zh-CN.md)。本文记录完整目标；基础 Dataset/Row 及独立 Grid 的已实现部分见 [P7 实施报告](30-PHASE7-DATASET-IMPLEMENTATION.zh-CN.md)，完整数据库仍未交付。

## 已取得的代码证据

直接复用固定 AppFlowy-Collab `e59260e...` 的 `collab-database` 0.2.0，原生探针已创建 Database、三种 Field、Grid View 和独立 DatabaseRow。原版直接编译 Web 遇到 `tokio::fs` 依赖问题；受控 runtime 副本对 manifest、文件资源端口、前台行加载、阻塞模板任务和 Rayon 迭代做了明确平台适配，保留原生路径。副本有逐文件原始 hash、补丁和许可，没有修改全局 Cargo 缓存。

同一探针随后在真实浏览器 WASM 中执行成功，数据库 ID 与行对象 ID 独立，原行 CRDT 可编码。它只证明这条运行路径，不证明所有数据库 API、CSV/资源导入、字段转换、视图或 Cloud 协作均可用。后台预取等仍调用 Tokio 的入口必须完成调度端口适配后再开放。

历史探针位于 `smart_document/probes/database_runtime`。其受控 runtime 已提升为独立 `smart_document/vendor/appflowy_database`，Dataset package 和公开 SDK 插件提供独立 Grid 的基础增量；文档内嵌和全部语义仍待后续批次，不能把所有数据复制进文档块 JSON。

## 对象、事务与权限

DatasetRoot 拥有字段 schema、视图定义及行顺序；Row 拥有独立 row/cell 状态。原 Database/DatabaseRow 编码分别绑定原 AppFlowy 对象类型，不能都上传为 Document。文档只保存经过资源层解析的 dataset/view 引用，删除嵌入不删除数据集或行。

共享 package 负责 opaque transport、身份注入、限额和生命周期；Dataset binding 负责字段命令、编码、校验、行分片、领域锚点和撤销。文档选区与数据集单元格选区分开。Host 只装配公开 provider/handler/surface；文档、数据库、Office 不互相调用内部存储。

对象授权、行可见性与数据集视图权限分别表达；文档可读不自动授予数据集可读。嵌入时先解析来源权限，再建立子会话。关联/汇总要在授权读集上计算，不能通过聚合结果泄露不可见行。跨对象关系操作使用有界读集、版本前置条件、幂等 commandId 和明确 pending/committed 状态，不能把多份 CRDT 更新描述成数据库 ACID 事务。

## 思源 18 类字段映射

下表是实现方向，尚须逐项完成固定思源语料、空值/非法值、转换、复制、并发和重开测试。原 AppFlowy 字段存在不等于语义完全等价。

| 思源类型 | 优先复用 | 必须适配的语义 |
| --- | --- | --- |
| block | 原 primary RichText + 独立 row document/source reference | 原块身份、动态标题/引用、来源生命周期；不复制第二份块真源 |
| text | RichText / 原 type option reader/writer | Unicode、空值、富文本边界和剪贴板往返 |
| number | Number | 精度、格式、空值、非法输入、计算与排序 |
| date | DateTime | 时区、范围/时间部分及转换，以思源语料确认 |
| select | SingleSelect | 保留 option ID、颜色、重命名与并发选项生命周期 |
| mSelect | MultiSelect | 集合与顺序语义、删除选项、导入映射 |
| url | URL | 地址/显示内容、安全 scheme、导航能力 |
| email | RichText 存储 + 显式语义描述符 | 专用验证/链接/筛选；不能只存字符串就认定完成 |
| phone | 同上 | 地区号码、显示与拨号行为 |
| location | 同上/专用复合值 | 地点结构、来源、显示和筛选能力 |
| mAsset | Media + AssetRepository | 多附件身份/顺序、私有权限、离线与来源引用 |
| template | 派生字段 provider + 原模板语料 | 无直接等价项；保留原定义，计算未实现时只读并标明能力 |
| created | CreatedTime + 来源元数据 | 区分 row 创建和来源 block 创建时间，不能替换语义 |
| updated | LastEditedTime + 来源元数据 | 来源修改、操作者、离线时钟与服务端记录 |
| checkbox | Checkbox | 空值与默认值、批量操作、并发 |
| relation | Relation | 跨资源/行身份、反向关系与权限、多对象操作状态 |
| rollup | Summary + 派生值适配 | 逐计算函数验证授权读集、空值、重算和一致性 |
| lineNumber | 视图派生行号 | 过滤/排序后可见顺序，不作为任意可写 Number 保存 |

每个字段拥有版本化 semantic descriptor，区分存储类型与行为类型。没有等价项时保留原配置与值，禁止静默降级丢失。字段 capability 单独声明 editable/filterable/sortable/groupable，参考思源 `kernel/av/capabilities.go`；不从控件外观推断能力。

## 五类视图及冻结界面

原运行内核的 DatabaseLayout 是 Grid、Board、Calendar。思源的 table/kanban/calendar 优先适配这三类，仍需验证卡片字段、分组、日期配置等差异。list/gallery 需要扩展 surface profile，保持共享 dataset/field/row 身份与原视图过滤/排序，不能复制一份列表或卡片数据源。

Desktop/Web 在冻结的文档连续编辑区嵌入视图，字段/视图工具进入已有功能区和块菜单。Mobile 同屏滚动嵌入；横向表格保留明确可滚动区域，编辑单元格后进入该领域工具区，退出恢复文档工具。数据集撤销、焦点与选区属于子会话；触控至少 44px。嵌入视图与独立打开的数据集共用同一领域 surface。

完整 AppFlowy 前端源码中的数据库组件可用于提取交互/字段能力，但它们依赖本机 SDK/service locator。新增运行复用要固定文件 hash、依赖和补丁；不能把父仓库 Git HEAD 当作其上游版本，也不能为复用一个控件引入第二套未对齐的数据库内核。

## 继续实施的退出条件

1. **D0 资格验证：** 原生/Web 已覆盖基础对象创建；继续覆盖重开、原 row/cell API、事件、CSV、后台预取及错误边界。探针通过后才将 adapter 提升为正式 Dataset package。
2. **D1 领域 API：** create/open/export/validate；field/row/view 稳定 ID 命令；独立 row 状态、事务预条件、撤销和配额。实现层必须调用原 reader/writer/filter/sort/group，禁止另写简单 CRUD 代替原引擎。
3. **D2 协作：** 使用独立 binding 和原对象类型；Cloud 两用户根/行分片读写，乱序重放、删除、断线追赶、权限/撤权、服务端校验和耐久边界。先解决被授权对象集合再启用嵌入。
4. **D3 UI：** 先 table 的字段/单元格/行操作、过滤/排序和独立资源打开，再嵌入文档；Desktop/Web/iOS 真实点击、输入、协作与重开。普通固定网格表格保留自己的内容类型。
5. **D4 完整语义：** 18 字段、5 视图、转换/模板/关系/汇总逐项通过；再开放批量、剪贴板、导入导出。未知配置保留，不能以禁用按钮代替功能。

各步的产品验收均与完整协作计划关联。Android 继续保持用户授权约束下的未运行状态，不伪造全平台完成记录。
