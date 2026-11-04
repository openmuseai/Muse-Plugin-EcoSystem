# Spreadsheet 壳重建架构与合同

## 源码调查结论

GenOffice Sheets 的 [`App.tsx`](../../genoffice-pptx/vendor/genoffice/apps/sheets/src/renderer/App.tsx) 管理文件打开、Univer 实例、选区、撤销、缩放、保存与 AI 状态，并把大量回调传给 [`ExcelShell.tsx`](../../genoffice-pptx/vendor/genoffice/apps/sheets/src/renderer/ExcelShell.tsx)。`ExcelShell` 内同时定义 7 个常驻 Ribbon 标签、4 个上下文标签、功能组、多级菜单、状态栏，并挂载 `#univer-container`。公式栏、网格、工作表标签的关键交互由 Univer 运行时绘制和控制。因此直接复制 React 壳会带入第二套工作簿状态和 Web 编辑面；这里重建视觉与交互合同，工作簿真相交给 Rust 内核。

[`GridCraft`](../../../../ioffice/vendors/gridcraft/docs/architecture.md) 的 `core → formula/functions → model/calc/xlsx → chart → engine → ui-egui/apps` 分层明确。`engine::Session` 管理文档和历史，`Session::execute` 根据命令注册表执行并返回 `Result`，`engine/display.rs` 给出格式化单元格显示文本；`ui-egui` 才负责 GridCraft 自身窗口、Ribbon 与网格。首版只对接无 egui 依赖的模型/计算/IO/engine 层。现有 `apps/gridcraft-web` 是包含 egui 的完整 Web App，不能把它当成 Flutter Web 的嵌入式内核 API；现有 `engine.execute` JSON 控制通道可用于原型验证，不作为移动端进程内的生产 ABI。

[`ss-core/Cargo.toml`](../../../../ioffice/libs/ss-core/Cargo.toml) 描述了从 `koffice/et/core` 重写的目标，但当前 `ss-core` 缺少 `src/` 和可调用的工作簿会话 API。不能让未完成的重写拖住壳交付。先以 GridCraft 适配器跑通完整纵向切片，后续通过相同 Host 合同切换内核，并用相同语料比较结果。`plugins/spreadsheet/gridcraft` 与 `ioffice/vendors/gridcraft` 当前是不同 Git 提交；前者只作为参考/待清理副本，不参与产品构建。锁文件只指向 `ioffice/vendors/gridcraft` 的提交和源码摘要，防止双引擎与无意漂移。

## Everything is plugin 的边界

| 层 | 部署与所有权 | 职责 |
| --- | --- | --- |
| Spreadsheet 产品插件 | 已签名、可离线安装和回滚的资源包 | Ribbon 标签/组/按钮和各级菜单、快捷键、图标与主题、模板、功能开关、低频扩展声明 |
| Flutter 编辑面能力插件 | 源码位于 `ioffice`，随 Host 编译 | 网格虚拟化、行列标题、公式栏、单元格编辑与 IME、选区/拖拽/填充柄、工作表标签、状态栏视图、响应式布局 |
| Rust 内核能力插件 | Desktop 原生库、Mobile 随 Host 安装、Web WASM 随 Host 版本缓存 | 唯一工作簿模型、公式计算、数据验证、命令执行、撤销、XLSX/CSV 导入导出、图表数据/绘制原语 |
| Host | 固定平台能力 | 验签、ABI 发现、文档授权和单写者租约、窗口/嵌入区域、原子保存、离线缓存、生命周期与升级回滚 |

“热插拔”针对签名产品资源和明确隔离的低频扩展。Flutter AOT Widget 与进程内 Rust ABI 不能靠市场下载的资源包任意装载；更新编辑面或内核需要 Host 版本升级。Desktop 可在 Host 原生窗口内嵌 Flutter 视图，也可开独立原生窗口；两种容器使用同一会话/视图合同。Mobile 资源包离线安装，内核和 Flutter 编辑面跟包；Web 首次装载后缓存 WASM、资源包和字体以支持离线编辑，文件访问由 Host 授权。

## 领域模型

```text
Host DocumentRef + WriteLease
  └─ WorkbookSession(id, engineId, engineAbi, revision, dirty, permissions)
       ├─ Workbook → Sheet(id, name, visibility, order)
       ├─ Cell/Range → input, value, formula, style, merge, validation
       ├─ Selection → activeCell, ranges, editMode
       ├─ Calculation → dependency graph, recalc state
       ├─ Objects → charts, pictures, shapes, tables, pivot (按能力开放)
       └─ History → undo/redo → export bytes

ViewportState(sheetId, scroll, zoom, frozen panes, active tab, open menu)
ProductPackage(id, version, required ABI/surface, capabilities)
  └─ Tab → Group → Control → MenuNode → CommandId
```

`WorkbookSession` 是唯一文档模型。Flutter 可以缓存可见区域 `CellView` 快照，不持有可写的第二工作簿；视口像素、活动 Ribbon 标签和弹窗属于 UI 状态。所有编辑命令携带 `sessionId`、`baseRevision`、`requestId` 与显式参数，返回新修订、受影响范围、计算状态、dirty/undo/redo。Host 拒绝过期修订、只读租约、超大输入和未知命令。保存由内核输出字节，Host 对授权目标做安全提交；产品包不得读取任意文件路径。

## 首版 `spreadsheet.engine/1` 桥接合同（拟定，M0 冻结）

| 请求 | 最小返回 | 实现原则 |
| --- | --- | --- |
| `capabilities()` | ABI、engine ID/版本、格式、命令与对象能力 | 安装与每次打开前求交集 |
| `open(bytes, formatHint)` / `new()` | 会话、sheet 列表、revision、警告 | 根据内容识别格式，导入损失显式报告 |
| `snapshot(session, viewport, revision)` | 可见行列尺寸、格式化 CellView、合并/冻结、对象锚点 | 按视口分页/分块，不跨 FFI 传整本工作簿 |
| `selection(session)` / `status(session)` | 活动单元格、公式文本、统计、保存/计算状态 | Ribbon 回显只读取快照 |
| `execute(session, commandId, params, baseRevision, requestId)` | 新 revision、受影响范围、能力错误 | 按稳定命令 ID 映射 GridCraft `Session::execute`；不传 UI 回调/指针 |
| `export(session, format)` / `close(session)` | XLSX/CSV 字节与警告 | 保存后独立重开校验 |

GridCraft `UiRequest::Dialog` 是引擎的提示，不直接触发 egui 对话框；Flutter 根据签名产品描述和 Host 权限展示对话框，再提交带参数的命令。浏览器与移动端使用同一语义合同，FFI/JS 桥接只改变传输方式。原生桥接优先基于 Rust `engine` 新建薄封装并提供稳定 C ABI；Web 单独导出匹配的 WASM API。跨边界的错误、字符串、字节缓冲和会话句柄要定义所有权与释放函数。

**高频路径**：Flutter 只请求可见格子的批量快照、局部失效和滚动增量；选区命中测试及滚动保持在编辑面，公式计算、格式化值和编辑提交留在内核。产品扩展不能进入每格绘制、每次光标移动、逐字输入或公式依赖计算。图表首版先消费内核数据/图元快照；没有可验证的绘制合同前不承诺 GridCraft 与 GenOffice 图表像素一致。

## 命令与能力门禁

产品命令分 `host`（打开、保存、打印）、`view`（Ribbon、缩放、面板）、`engine`（改单元格、格式、公式、表、数据操作）和 `extension`（显式 AI/外部服务）。每个声明包含 `id`、参数 schema、能力 ID、目标、撤销类别、菜单路径、快捷键及禁用文案。运行时可用性 = 内核报告能力 ∩ Host 权限 ∩ 签名功能开关 ∩ 工作簿保护/选区上下文。壳可显示未实现入口，但必须灰化并解释原因；不能用空操作伪造完成。

首版命令 ID 尽量复用 GridCraft `cmd` 与 `catalog.rs` 的稳定语义，例如 `cell.set`、`home.bold`、`data.sortAscending`；产品资源有自己的外部 ID 与映射表，不把 Rust crate 私有结构暴露成长期 ABI。迁移至 `ss-core` 时保留外部 ID 和参数/结果合同，逐命令跑差分测试。对于 GridCraft 支持而 `ss-core` 暂缺的能力，新的 Host 能力集自动禁用对应按钮，不更换产品包的视觉目录。

## 版本与供应链

定义独立版本：`spreadsheet.product/1`（签名资源 schema）、`spreadsheet.command/1`、`spreadsheet.engine/1`、`spreadsheet.surface/1`，以及各自 SemVer。产品包包含 manifest、每文件摘要、Ed25519 签名、`chrome.json`、`commands.json`、`menus.json`、`shortcuts.json`、`features.json` 和有来源记录的字体/图标资源。安装时验签、校验 Host/engine/surface 最低版本与命令 schema，原子切换并保留上一版；已打开的会话锁定产品版本直至关闭。发布报告记录 Host、`ioffice`、插件和 GridCraft 的提交及 SHA-256。不要把 `plugins/spreadsheet/gridcraft` 的二进制或 egui UI 放入产品资源包。

自研 `ss-core` 接班门禁：同一合同能打开、编辑、撤销、计算、保存、重开固定 XLSX/CSV 语料；公式值、显示文本、样式、合并、sheet 顺序和图表保真差异有报告；性能与内存不退化到验收阈值外。先按文档/功能能力逐步切换，不让一个工作簿在两个内核中同时可写。
