# P12：嵌入资源键盘边界与原日期字段

承接 [P11 实时数据库](34-PHASE11-DATASET-REALTIME.zh-CN.md) 与 [完整思源对齐台账](24-SIYUAN-PARITY-PLAN.zh-CN.md)。本轮沿用冻结的 Desktop/Web/Mobile 布局；属于可回溯的增量，不修改 SD-BL-1.2、SD-F1 和 SD-MOB-1.3 的历史快照。完整 36 项编辑 + 14 项协作门继续保持未通过。

## 源码依据和复用范围

思源基线仍为本地干净、只读的 `d3af9d5782082b379d45a69eedf4ebcfe8ba6889 / 3.8.9`，不宣称已跟踪远端最新版。本轮逐项检查：

- `kernel/av/value.go` 的 `ValueDate`、`NewFormattedValueDate`：区分起点/终点、空值、全天/含时间和范围；思源时间戳为毫秒。
- `app/src/protyle/render/av/dateFormat.ts`、`datePaste.test.ts`、`fieldValueEditor.ts`：日期格式、区间解析、校验及既有值保留；本地时区依赖需要在多端协作适配中消除。
- 固定 AppFlowy Database 的 `date_type_option.rs`：原字段类型 2、DateTypeOption、DateCellData、原 reader/writer 和 Row 4 存储。
- 原 AppFlowy `database_view_block_component.dart`、editor selection interceptor、keyboard service 和 undo/redo command：复用焦点和快捷键扩展接口，不另写历史引擎。

数据库仍为独立资源、独立 Database 1/Row 4；父文档只存原 grid 引用和中立 ResourceEmbedTarget。日期不是正文中的序列化 JSON，也没有引入第二套 CRDT、Go Kernel 或 SQLite 权威存储。

## 产品与交互补充

### 三个撤销所有者

| 当前交互位置 | 撤销所有者 | 父文档行为 |
| --- | --- | --- |
| 正文光标或选区 | 原 Document undo manager | 正常处理原快捷键 |
| 嵌入数据库，含标题、空白区域和只读表格 | 子资源自己声明的快捷键 / 原 Database/Row manager | 清除正文选区并让出快捷键；只读子资源消费按键但不改数据 |
| 单元格、日期或字段弹窗中的文本草稿 | Flutter 原文本输入历史 | 弹窗位于独立 Navigator route，不能触发两个内容域的历史 |

已复现并修复：仅在指针按下时请求子焦点不够。点击只读子表格标题时，父 editor 的选择手势仍可能在随后接管焦点，Cmd+Z 会撤销 grid 引用。适配原 SelectionGestureInterceptor，使用每个子表面的独立注册与真实边界，阻止父选择手势接管子区域；再由 FocusScope 让位和按 editor 分组的焦点所有者集合维护快捷键。移除引用、卸载子表面时注销，多个子表面换焦不能提前恢复父快捷键。

文档只认识中立资源界面，不导入 Dataset 类型或 HTTP；DatasetSurface 只认识自己的领域会话，使用 Flutter CallbackShortcuts 分派 Ctrl/Cmd+Z、Ctrl/Cmd+Shift+Z 和 Ctrl+Y。弹窗未提交草稿不进入协作状态或本机资源检查点。

### 日期字段与单元格

新增字段菜单 → 日期 → 名称与显式 IANA 时区 → 原字段 2。默认新字段 `Etc/UTC`，不读取设备时区作为协作语义。重命名日期字段同时可以配置时区，保留原时刻，界面明确提示显示可能变化。

日期单元格 → 独立日期弹窗，包含完整开始输入、选择日期、包含时间开关、选择时间、结束日期开关、可留空的终点、字段时区、清空/取消/应用。日期/时间选择器复用 Flutter 原组件；手动输入支持到秒，夏令时重复时刻可通过明确偏移量区分。日历改变日期时保留原本地钟面时间，重新按字段时区解释，避免把旧 DST 偏移复制到新日期。

手机视觉检查发现，两枚行内图标挤占输入宽度，导致完整日期横向裁切；已把选择日期/时间移到输入下方的 44 高度操作区。弹窗内容可滚动，底部操作保留，继续使用冻结的整页与键盘上方编辑功能区。旧截图保留为诊断，不作为最终视觉验收。

应用期间禁用操作；非法日期、空缺时刻、重复时刻、偏移不符、范围倒置均保留草稿。远端改变同格时提示“内容已被修改，草稿保留，请取消后重新编辑”；远端改变字段或时区时使用独立提示，不能按新时区误解释旧草稿。父资源权限只收窄子资源，不能扩大其独立权限。

## 领域、命令与数据

`dataset/rust/src/dates.rs` 仅提供严格边界和读取投影，调用原 DateTypeOption/DateCellData writer。原 writer 的宽松字符串路径包含解析失败写 epoch 0、解析纯时间依赖 Local::now 的行为，不能直接暴露为智能文档的命令边界。

| 入口 | 前置条件 | 行为 |
| --- | --- | --- |
| createField(date, timezone) | 合法名称与 IANA 时区 | 创建原字段 2，写入原 type options |
| configureDateField | expectedFieldHash | 更新名称/时区，保留原日期/时间格式；原 root 历史可撤销 |
| setCell(date) | expectedHash + expectedFieldHash | 严格解释草稿，向原 writer 传 DateCellData 对象 |
| setCell(date, null) | 同上 | 明确清空，不把 0 当空值或生成今天 |
| 协作 / 重开 | 原对象身份与授权 | 原 Root 1/Row 4、WS2、HTTP 修复和独立资源检查点 |

命令草稿为 `{start, end, includeTime, isRange}`；全天为严格 `YYYY-MM-DD`，含时间为字段时区本地 `YYYY-MM-DDTHH:mm[:ss]` 或偏移明确且与字段时区一致的 RFC3339。拒绝额外键和有损小数秒；范围允许未设置终点，但不允许结束早于开始。

原 AppFlowy 保存秒级时刻：本轮不把思源毫秒时间戳无损兼容列为已完成。epoch 0 与空值明确区分，是本产品的明确语义；不是对思源中 0 作为空值哨兵的原样复制。旧全天单元格即使携带非午夜的隐藏时间，未改变 civil date 时也保留原时刻。未知配置/格式、无法解析的值和带未接入提醒的单元格保留原 CRDT 且只读，不自动重置。

IANA 时区解释使用已锁定 chrono/chrono-tz；UTC、本地时区和 WASM 共用同一 Rust 边界。DST 空缺拒绝，重复要求明确偏移；极端外部时间戳先检查支持年份，避免时区换算溢出影响整个 core。历史 LMT 的秒级偏移无法由 RFC3339 精确表达时拒绝新含时间写入，已有值保留只读，不能四舍五入后回写。

原 Cell 仍为原 Y.Map 键的合并语义。此轮验证的是原对象收敛、因果后写、字段/单元格预期值保护和原作者撤销；没有把它升级宣称为复合日期值的原子冲突解决、字符级表格协作或完整离线命令协议。

## 验证与证据组织

- Rust 数据库 14 项：原编解码、全天区间、空值/epoch/负值、旧隐藏时间保留、非法输入、DST 空缺/重复、Apia 跳过日期、偏移/精度、未知配置与提醒保留、同格因果更新、字段 hash 和原作者撤销/重开。
- 共享 Dataset 本地回归 25 个独立用例，其中 Ctrl/Cmd 快捷键与三种宽度日期交互共 5 项（不重复累计）。正文原回归 32 项，避免子手势适配破坏既有块、媒体与 Mobile。
- macOS 独立键盘集成组验证实际 Cmd+Z/Cmd+Shift+Z、弹窗草稿、只读子表面及返回正文的原快捷键。最初混合 widget harness 在回调结束后停滞，已取消并保留日志，不计通过；最终使用真实 macOS application 集成验证。
- macOS/iOS 日期 UI 通过公共资源会话、真实 Cloud 双账号、原 WS2 根/行更新、同格与字段时区草稿冲突、独立子历史、原日历/时间选择器和双资源检查点。新进程仅本机恢复，不携带凭据或 transient presence。
- 同一原生对象继续在两个真实浏览器编辑：Alice 9 项、Bob 7 项、IndexedDB 无凭据恢复 5 项；两端 HTTP 门关闭时原 WS 更新仍到达。保留真实 AX/截图及同格冲突草稿；历史观察器只记录原 core undo/redo，不实现替代历史。

网页快捷键撤销已实际触发；AX 自动化撤销后浏览器焦点回到 WebArea，重做通过显式聚焦子表格重做控件后发送组合键完成。该记录不扩大为所有浏览器/物理键盘的连续焦点保证。iOS 软件键盘真实几何、物理中文 IME、旋转与 Android 仍不计完整通过；继续遵守用户“仅 iOS，暂不安装 Android”。

Native→Web→Native 4 项只读读回也通过：同一 Date field 2/Row 4、范围起止、秒精度/标志、时区和父文档中立引用一致。

归档与最终运行身份由 `execution/phase12-dates-20261106/result.json`、manifest 和源快照确定。最终校验器比较文件摘要、收据身份、实际日志、浏览器冲突文本与独立对象关系；完整思源/协作门必须继续拒绝。

## 下一批

数据库已具备七类基础字段和共享 Grid，距离原目标 18 字段/5 视图仍有差距。日期格式/农历、毫秒导入损失报告、提醒、完整日历视图和复合值冲突处理继续按完整门推进。其后优先复用原筛选/排序/分组和多视图实现；同时修复已识别的协作生命周期边界，继续资源注册表/授权继承、即时分布式撤权、同 UID 多设备成员、持久 ACK、离线命令、评论/历史、Agent 与 Office。
