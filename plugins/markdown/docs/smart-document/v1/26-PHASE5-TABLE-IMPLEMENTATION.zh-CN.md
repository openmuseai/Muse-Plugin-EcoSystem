# P5-A：固定网格表格编辑与多人协作

2026-11-06。依据 [完整思源编辑/协作开发门](24-SIYUAN-PARITY-PLAN.zh-CN.md) 推进 P5 的表格首批能力，承接 [P4](25-PHASE4-IMPLEMENTATION.zh-CN.md)。冻结的产品/交互/技术快照保持不变；本报告追加可运行实现和实际证据。**本批为固定网格协作切片，不是表格全量、思源全量或完整协作完成声明。**

结果与工件：[执行证据](execution/phase5-table-20261106/README.zh-CN.md) · [机器结果](execution/phase5-table-20261106/result.json) · [50 项能力台账](siyuan-collaboration-parity.json)。

## 1. 用户现在可以做什么

- Desktop/Web 从插入菜单，Mobile 从键盘上方 `+` 面板插入 **2 × 2 表格**，进入首个单元格；表格和正文在同一编辑区连续显示。
- 单元格使用真实 AppFlowy rich text，支持中文、emoji、多行文字及选区样式。硬件 Enter/Shift+Enter 在单元格内插入换行；单元格首尾的 Backspace/Delete 不跨格合并。
- 窄屏在表格内部横向滚动；表格高度由内容排版确定。表格操作入口至少 44px，提供删除整表；只读/阅读态不显示写操作。
- 两个已认证成员可离线修改同格或异格，经原 Cloud 合流；原生 origin 撤销只撤销自己的修改，保留对方文字和格式。
- 本机文件、Web IndexedDB 和公开 SDK CAS 资源检查点保留表格。独立新 App 进程不配置 Cloud 凭据，也能打开同一资源、表格和文字块。

当前 UI 固定创建 2 × 2；领域 API 支持初建时指定 1–20 行、1–10 列。**行列增删、调整列宽、合并/拆分、矩形选区与 Excel/HTML 整表粘贴未交付**，不能通过上游表格菜单绕过当前限制。单元格内 Markdown 块前缀保持字面输入，避免结构快捷键意外改动网格。

## 2. 领域模型与协作边界

继续使用同一个 pinned AppFlowy-Collab `Document`，未创建第二份表格副本或协作服务器。结构落在原 `blocks + children_map + text_map` 中：

```text
page
  paragraph
  table {museTable: "fixed-grid/1", rowsLen, colsLen}
    table/cell {rowPosition, colPosition}
      paragraph/其他受支持的叶子文字块 -> 原 Y.Text
    ...
  paragraph
```

`table` 和 `table/cell` 是无 external text 的结构块；可编辑文字保持原 AppFlowy external Y.Text 与 origin undo。固定坐标只描述这个版本的不可变网格，不将数组位置当作可移动行列的永久身份。整表地址使用 `{objectId, blockId}`；插入菜单捕获前一个根块的稳定地址，执行时重新解析，前置兄弟插入不会改错位置。跨对象/已删除的地址明确拒绝。

内核校验 schema 版本、整数尺寸与预算、单父/无环、单元格数量、坐标唯一与范围、非空文本内容和根级表格位置。单元格目前仅允许受支持的叶子文字块，不允许嵌套表格或任意结构。对已有表格，坐标、尺寸和 cell ID 序列不能改变；删除整表和文字编辑分别处理。类型转换不把结构节点误当文字。

本机操作与远端更新均先在候选文档验证，再改动 live session。错误网格/非法坐标/重复槽位/清空 cell/有效坐标交换均不能部分污染当前文档。未知 `museTable` 版本和没有该标签的原 AppFlowy 表格明确拒绝，需要格式桥/迁移，不能默默套用本版本规则。

**此处是客户端领域验证，不是新增服务端校验。** 原始写请求仍需服务端领域验证；恶意合法成员可能把坏更新送入现有 Cloud，当前客户端会拒绝应用并保留本机版本，但这不修复服务端坏状态。该缺口继续记在 CO-12，不能将非成员 ACL 通过解释为所有合法成员的结构写入已经安全。

协作 transport/package、原 Cloud full-sync 与文档领域解耦保持不变。此次增加的是文档内表格的细粒度文字协作；独立 Excel/数据集/AV 的事务和权限仍由各领域负责，未被塞入文档表格类型。

## 3. 渲染与输入实现

新增 `table_components.dart`，三端使用同一 renderer。它按坐标绘制单元格，并将真实文字块交给原 AppFlowy renderer，保留节点 key、矩形和输入连接；不使用独立 TextField 保存另一份内容。初建后 cell/文字身份不因屏幕宽度或自动行高变化而重建。

没有直接启用上游 TableView 的行列操作。该版本上游 renderer 在排版回调中更新 cell 高度，且自带行列/拖拽入口；本实现只计算本地布局，不把行高/视口宽度写入 CRDT，避免渲染引发同步循环。只读视图也不会因排版产生写事务。

共享 command profile 处理单元格内换行及首尾删除边界。原有 Tab/方向键导航保留；Mobile 减少/增加缩进在表格内禁用。跨单元格复杂删除、剪切/粘贴、列表缩进与其他快捷键仍须扩大测试，不将基本输入通过等同于所有边界交互已验收。

公开 SDK 仍通过原资源会话做 CAS 检查点。当前 Agent context 是现有文本遍历提取，能取回表格文字，但尚未输出具备完整坐标/ID/读集的结构化表格合同；结构化 Agent 修改按 T11/T12 继续实施。

## 4. 验证和复现

新增 Rust 三组测试，使总数为 10：同格/异格 Unicode 与 marks 并发、origin undo/redo/重开、坏网格/固定拓扑原子拒绝、坏远端更新不污染 live。Flutter 本机总数为 17，新增稳定插入地址/文件重开/整表删除撤销、单元格输入命令和 320/390/1100 宽度布局不写入内容。

原生新验证脚本 `verify_table.py` 明确只接受 macOS 或已连接 iOS，不允许其被用于 Android 安装。主流程 6 组检查，第二次独立进程 4 组；重开仅传同一 run，移除全部 Cloud 凭据。鼠标/触摸命中警告设为失败，点击前清掉插入操作产生的选区，避免把已有光标误判为触摸命中成功。

Web 新增同格离线并发、marks 与 origin undo；在独立测试 IndexedDB namespace 保存重载前的 table/cell/text block/external Y.Text ID 与精确 delta，整页重载后逐一比对，不只检查文本 contains。native 再读回 Web 表格。完整 `verify_phase2.py` 仍要求真实浏览器页面操作和回执；本机回归已将新增 17 项纳入必跑列表。最终次数为 Web 8 组、重载 2 组、native 读回 4 组；均通过，完整 native 回归通过。各端切片使用独立合成资源，native/Web 读回使用同一对象；本批没有完成三端同时同一对象的完整故障矩阵。结果以本批 `result.json` 为准，不修改旧 F1/F2/P4 历史回执。

在 `smart_document` 中：

```sh
cargo test --locked --manifest-path rust/Cargo.toml
cd flutter
flutter test test/controller_test.dart test/editor_commands_test.dart test/mobile_view_test.dart test/document_view_test.dart test/table_test.dart
cd ..
python3 scripts/verify_table.py --device macos
python3 scripts/verify_table.py --device <明确选择的iOS设备ID>
python3 scripts/verify_phase2.py
python3 scripts/verify_parity.py
python3 scripts/verify_parity.py --require-complete
```

最后一项仍必须拒绝完整产品验收。截图前关闭键盘，原生回执的键盘可见字段表示截图时状态，不能证明输入中的软键盘几何。模拟器输入连接回调不替代人工拼音候选、物理 iPhone、长按范围选择、后台杀进程、性能与无障碍专项。Android 继续按用户要求未安装/运行。

## 5. 后续开发门

1. **P5-B 稳定树与可变拓扑：** 交付行/列稳定身份、语义事务、删除冲突/tombstone、并发增删及合并/拆分策略后，才能迁移到可变网格版本。不得放开更新 `rowsLen` 的按钮冒充完成。
2. **所有写入口服务端验证：** 既有 HTTP full-sync、WS、创建/批量写、后台任务均须按对象类型共享校验与授权；修复被拒的远端坏状态需要恢复和审计路径。
3. **P5 其余内容：** 图片/附件草稿上传、元素 registry、公式、未知内容保留与格式桥；原子树移动/拆合继续单独处理。
4. **P6 完整协作业务：** 原 Cloud WS/presence、相对锚点、角色撤权、私有评论/@、分享、历史恢复和耐久确认。这些仍未因表格双账号互通而完成。
