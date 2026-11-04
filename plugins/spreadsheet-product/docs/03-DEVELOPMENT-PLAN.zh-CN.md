# Spreadsheet 产品壳开发、验证与发布计划

## 交付策略

先完成真实 XLSX 的打开、网格渲染、改单元格、计算、撤销和保存重开，再覆盖全量 Ribbon 的视觉与菜单路径。所有壳入口先登记，功能随内核能力分批放开；发布时明确已验收功能，避免“点击了但没有作用”。签名产品包只带声明/资源/低频扩展，GridCraft 适配器和 Flutter 编辑面均放 `ioffice`、随 Host 升级。

## 里程碑与退出门禁

| 阶段 | 工作分工 | 可验收结果 | 估算 |
| --- | --- | --- | --- |
| M0 合同与清单 | 插件仓：GenOffice 7+4 标签及所有下拉/弹窗逐项台账、资源 Schema、命令/功能清单；`ioffice`：GridCraft 固定提交和桥接 API；Host：格式路由/ABI 协商 | 清单每项有状态、能力与测试；签名包校验/篡改拒绝；单一 GridCraft 来源，`ss-core` 缺口明确 | 1–2 工程人周 |
| M1 真实工作簿纵向切片 | `ioffice` 建 Rust `gridcraft_adapter`（不依赖 egui）和 Flutter `spreadsheet_editor` 可见网格、公式栏、表签；Host 注册 XLSX/CSV 原生编辑器；插件出首版签名壳 | macOS Host 安装包后打开 2 sheet XLSX，看到值/公式/基本格式；改 A1→公式重算→撤销/重做→保存→独立重开；Android 同源表面离线完成同一流程 | 4–8 工程人周 |
| M2 GenOffice 壳与响应式 | 插件出 7 常驻+4 上下文标签、一级组/多级菜单、快捷键与主题；Flutter 实现标准/紧凑/触控密度、状态栏/侧栏/菜单 overlay | 桌面、窄屏、平板、折叠和手机全部菜单可达且无溢出；截图对比报告；禁用原因准确；同一命令在多端参数一致 | 4–7 工程人周 |
| M3 表格编辑增强 | `ioffice` 接复制/粘贴、格式、合并、填充、排序筛选、图表/对象快照；Host 完善文件权限/恢复 | 双向格式与公式、IME、触控选区、冻结/大表格、保存语料通过；不保真对象明确阻止破坏性写回 | 6–12 工程人周，按能力拆批 |
| M4 `ss-core` 切换 | `ss-core` 实现相同桥接合同，建立 GridCraft 差分/语料/性能门禁，按能力逐步放行 | 用户工作簿始终只有一个可写引擎；同包资源无需改变命令语义；对每个格式/功能显式声明支持矩阵 | 随自研内核持续推进 |
| M5 发行 | 三仓版本锁定、离线安装/升级/回滚、macOS/Android/Web 目标端 E2E 与性能、签名密钥切换 | 正式证书、clean commit、安装/打开/编辑/保存/重开证据与 SHA-256 报告；未测平台不放行 | 持续 |

估算仅供排期，M1/M2 的 Flutter 网格与桥接是主要成本。现有 GridCraft egui 虚拟网格不能直接变为 Flutter Widget；首版不要把丰富图表/数据透视表的完整编辑列为 M1 退出条件。

## 首个开发迭代的具体任务

1. **插件仓**：建立 `spreadsheet-product/product/{product,chrome,commands,menus,shortcuts,features}.json` 与签名打包/验签/Schema 测试。先落所有标签和组，菜单树采用稳定 ID；每条命令绑定 `target=host|view|engine|extension`、参数 schema、能力、禁用理由。签名包不包含 Rust/Flutter/egui 可执行代码。
2. **`ioffice` 内核适配**：固定 `ioffice/vendors/gridcraft` 提交，新增 `gridcraft_adapter`；实现 `capabilities/open/new/snapshot/selection/execute/export/close`，先覆盖 XLSX/CSV、基础格式和 20 个左右的常用编辑命令。为 JSON/FFI 资源设大小与超时预算，避免整表复制。
3. **`ioffice` Flutter 表面**：实现可见行列虚拟化、列宽/行高、冻结、滚动、基础选区、单元格文本/公式编辑、IME 和触控、公式栏、sheet 标签、局部失效；表面消费产品包的壳描述，不内嵌 Ribbon 顺序和业务菜单数据。
4. **Host**：注册 XLSX/CSV 的编辑路由、单写者会话、插件安装/验签与版本协商；Desktop Flutter 原生窗口/嵌入区域两种容器；Mobile 引导安装资源包并持久化以便离线启用。Web 需要独立 WASM 桥接、缓存和真实浏览器离线测试后再列入已交付端。
5. **联合流水线**：提供 `spreadsheet:plan`（解析版本/能力和构建锁）、`spreadsheet:build macos|android|web|all`（构建内核/Flutter/Host/签名包）、`spreadsheet:e2e`（真实 Host 安装、打开、渲染、编辑、保存重开）。构建缓存键包含四仓提交/脏树摘要、工具链、目标和编译参数；绝不复用来源不明的二进制。

## 一键联合验证报告

每次 `spreadsheet:e2e` 输出机器可读 JSON 和截图：Host、`ioffice`、产品包、GridCraft 提交和脏树状态；引擎/表面/命令/产品合同版本；目标 OS/设备；签名包、内核库/WASM、Host 应用、样本 XLSX 的 SHA-256；安装、打开、可见格子渲染、公式计算、撤销/重做、保存、独立解析器重开、断网重启每一步的结果。工作簿含合并/样式/图表等未支持对象时，报告记录导入警告与保存拒绝或保真证据。开发态可以脏树但必须标明；发行候选必须锁定 clean revision 和正式签名。

最小语料：空表、2 sheet 基础公式/格式、中文和英文 IME、合并/冻结、图表/图片、100k 行稀疏表、损坏或加密文件。首版放行只要求前四类的已声明能力，其他用清晰的禁用/拒绝与回归测试覆盖。性能记录打开 P50/P95、首屏、滚动帧时间、可见格子批量读取、重算及内存；阈值由实测基线确定。安全门禁包括 ZIP bomb、公式输入边界、超大范围、路径授权与失败保存不损原文件。

## 发布与替换节奏

- 仅调整资源/图标/文案/菜单排序：更新并签名产品包，运行旧/新 Host 兼容和视觉/命令树测试，可独立热升级。
- 改动 Flutter 编辑面或 GridCraft 适配器：提升 surface/engine 版本，构建新的 Host 包，并在 macOS/Android（影响 Web 时加浏览器）跑真实打开、编辑、保存 E2E。插件资源仍可独立回滚。
- 改动 `ss-core`：先跑内核差分测试，生成能力矩阵；达到单项门禁才在 Host 构建配置中切换该能力/格式。会话创建时锁定引擎，切换发生在新会话，不做热替换正在编辑的工作簿。
- 市场发布前跑离线安装、签名篡改、旧包回滚、Host 升级兼容和真实设备/浏览器验证。Desktop 的原生包优先；Android APK 与 Web WASM 只在各自 E2E 完整通过后标记可交付。

## 当前状态（2026-10-23）

第一轮已落地 `0.1.0` 签名产品包、GridCraft C ABI 1、Flutter `spreadsheet_editor`、Desktop/Mobile Host 路由。真实 XLSX 在 macOS 的 Host 组件测试中完成打开、渲染、改单元格、导出和重开；Android 模拟器完成 APK 安装、功能包加载、文件选择器打开 XLSX 与网格渲染。macOS Release 包已构建并通过 `codesign --verify --deep --strict`，DSH closure 构建/运行检查通过。本轮视觉证据和差异见 [`04-ROUND-1-VISUAL-AND-BUILD.zh-CN.md`](04-ROUND-1-VISUAL-AND-BUILD.zh-CN.md)。

M1/M2 **尚未验收**：编辑区当前只有前 100 行×32 列快照，未实现可视范围虚拟化、对象/图表层、冻结、列宽行高、IME 原位编辑与完整键鼠/触控选区。Ribbon 已有 7 常驻+4 上下文标签的资源模型和多级菜单树，但上下文选区联动、全部控制的精确排布与图标、快捷键、状态回显、能力接通仍需逐项完成。CSV 导入和保存也需单独语料验证。当前产物仅用于人工验证与继续迭代，不标为 1:1 完成或发行候选。

第二轮已交付 `0.1.1`：开始页布局改为插件资源定义的大按钮/竖列/双排混排，补齐 Ribbon 图标映射；桌面、平板、折叠、小屏及多级菜单截图和新的双端构建哈希见 [`05-ROUND-2-VISUAL-AND-BUILD.zh-CN.md`](05-ROUND-2-VISUAL-AND-BUILD.zh-CN.md)。M1/M2 未验收项仍按上段跟进。

第三轮已交付 `0.1.2` 产品资源包、GridCraft 桥接 `0.1.1` 与 Flutter 表面 `0.1.1`：可视窗口懒加载、远处行列编辑、多格选区与状态栏聚合、表格上下文 Ribbon、拆分命令/菜单入口。双端构建和逐轮视觉证据见 [`06-ROUND-3-VISUAL-AND-BUILD.zh-CN.md`](06-ROUND-3-VISUAL-AND-BUILD.zh-CN.md)。图表对象层和其余 Ribbon 精确还原仍为未验收项。

第四轮将产品资源包升至 `0.1.3`、Flutter 通用表面升至 `0.1.2`，为全部 11 个标签、55 个组补上显式的大按钮/竖列/双排布局，并显示桌面组标题。所有组必须覆盖控件清单的校验进入产品生成流程。逐页截图、差异及双端构建报告见 [`07-ROUND-4-RIBBON-LAYOUT-AND-BUILD.zh-CN.md`](07-ROUND-4-RIBBON-LAYOUT-AND-BUILD.zh-CN.md)。下一轮需要按 `ExcelShell.tsx` 补全遗漏控件与菜单级联、做同工作簿同尺寸视觉对照；对象层、图表、冻结及 IME 等仍按 M1/M2 未验收项推进。

第五轮将产品资源包升至 `0.1.4`、Flutter 通用表面升至 `0.1.3`，逐组补到 183 个控件、65 棵菜单；新增插入页九宫格图表布局和状态栏六项可配置统计菜单。两个 Host 端到端测试、macOS Release/Android arm64 构建、Android 模拟器真实 XLSX 打开与“插入”页截图已完成，逐轮差异和版本化产物见 [`08-ROUND-5-CONTROL-INVENTORY-AND-BUILD.zh-CN.md`](08-ROUND-5-CONTROL-INVENTORY-AND-BUILD.zh-CN.md)。M1/M2 的复杂对象和逐像素对齐仍未验收。

第六轮将产品资源包升至 `0.1.5`、Flutter 通用表面升至 `0.1.4`、GridCraft 桥接升至 `0.1.2`。顶部快捷栏、自动保存、原位编辑与工作表标签菜单完成第一版；Rust 快照补充工作表可见性和视图状态，修复返回 JSON `null` 的成功命令未刷新界面。3 项 Host 端到端测试、macOS Release/Android arm64 构建及模拟器打开真实 XLSX、长按菜单和插入工作表均通过。截图、差异与构建哈希见 [`09-ROUND-6-TOPBAR-INLINE-AND-SHEET-TABS.zh-CN.md`](09-ROUND-6-TOPBAR-INLINE-AND-SHEET-TABS.zh-CN.md)。下一轮优先补工作表移动/复制和标签颜色，随后针对同一复杂工作簿做同尺寸视觉对齐。

第七轮将产品资源包升至 `0.1.6`、Flutter 通用表面升至 `0.1.5`、GridCraft 桥接升至 `0.1.3`。签名菜单参数驱动主题/标准/自定义标签颜色，工作表移动和复制走 GridCraft 命令；标签颜色从 Rust 快照回传，XLSX 往返验证顺序与颜色。深色弹窗、桌面/平板/折叠屏/手机截图、Android 模拟器复制与着色验证、双端 Release 包见 [`10-ROUND-7-SHEET-COLOR-MOVE-COPY.zh-CN.md`](10-ROUND-7-SHEET-COLOR-MOVE-COPY.zh-CN.md)。下一轮继续对齐 GenOffice 平铺调色盘、常驻移动列表以及 Ribbon/底栏的尺寸和间距。

第八轮将签名产品包升至 `0.1.7`、Flutter 通用表面升至 `0.1.6`：10 列主题/标准色和 5 行明暗色阶由产品资源声明，工作表色盘平铺呈现；移动或复制改用常驻目标列表。现有 35/80/40/24 逻辑像素顶部标签/Ribbon/公式栏/底栏尺寸已对照源码复核。真实 XLSX 端到端测试、跨宽度截图、macOS Release ZIP、Android arm64 Release APK 及签名/包内哈希验证见 [`11-ROUND-8-PALETTE-LIST-VISUAL-AND-BUILD.zh-CN.md`](11-ROUND-8-PALETTE-LIST-VISUAL-AND-BUILD.zh-CN.md)。后续重点转向同一复杂工作簿的等视口视觉对比与图表/对象层。

第九轮将签名产品包升至 `0.1.8`、GridCraft 桥接升至 `0.1.4`、Flutter 通用表面升至 `0.1.7`：当前工作表的真实图表由内核解析成有界绘制快照，Flutter 在网格之上按工作簿锚点绘制；插入页图表九宫格/二级菜单携带产品声明参数，点选图表出现“图表设计”。真实 XLSX 图表导出回读、四项 Host 测试、桌面/手机视觉证据、macOS Release ZIP、Android arm64 Release APK 和模拟器启动证据见 [`12-ROUND-9-CHART-VISUAL-AND-BUILD.zh-CN.md`](12-ROUND-9-CHART-VISUAL-AND-BUILD.zh-CN.md)。同工作簿等视口 GenOffice 对照、图片/形状对象层、保真写回门禁仍未验收。

第十轮将签名产品包升至 `0.1.9`、GridCraft 桥接升至 `0.1.5`、Flutter 通用表面升至 `0.1.8`：形状菜单由产品插件声明参数，桥接按需传输图片字节并返回有界对象元数据，Flutter 在同一网格对象层显示图表、形状和图片，点选后切换上下文 Ribbon。真实 XLSX 的三类对象导出回读、五项 Host 测试、桌面/手机视觉对照、macOS Release ZIP 和 Android arm64 Release APK 已完成，见 [`13-ROUND-10-SHAPE-IMAGE-VISUAL-AND-BUILD.zh-CN.md`](13-ROUND-10-SHAPE-IMAGE-VISUAL-AND-BUILD.zh-CN.md)。同工作簿等视口的 GenOffice 逐像素对照、复杂形状、对象拖拽缩放和完整保真门禁仍未验收。

第十一轮将签名产品包升至 `0.1.10`、Flutter 通用表面升至 `0.1.9`：产品声明对象移动、缩放和删除的引擎命令；表面识别拖动、右下角缩放手柄和 Delete/Backspace，坐标换算独立建模，GridCraft 继续作为对象唯一写入源。真实 XLSX 保存重开验证了锚点与尺寸，删除图片及撤销也通过 Host 测试；视觉证据和 macOS/Android Release 产物见 [`14-ROUND-11-VISUAL-INTERACTION-AND-BUILD.zh-CN.md`](14-ROUND-11-VISUAL-INTERACTION-AND-BUILD.zh-CN.md)。同工作簿等视口的 GenOffice 逐像素对照、其余缩放手柄和复杂对象保真仍未验收。

第十二轮将签名产品包升至 `0.1.11`、Flutter 通用表面升至 `0.1.10`：按 GenOffice 源码补齐八个对象缩放控制点，纯几何模型保持对侧边界并限制最小尺寸与工作表起点。三项几何测试、五项 Host 端到端测试、真实 XLSX 保存重开和双端构建进入联合流水线；截图与差异见 [`15-ROUND-12-EIGHT-HANDLE-VISUAL-AND-BUILD.zh-CN.md`](15-ROUND-12-EIGHT-HANDLE-VISUAL-AND-BUILD.zh-CN.md)。同工作簿等视口的 GenOffice 对照、可变行列尺寸、RTL 和旋转对象仍未验收。

第十三轮将签名产品包升至 `0.1.12`、Flutter 通用表面升至 `0.1.11`：按 GenOffice Ribbon CSS 移除带内组标题，缩进组分隔线，并由签名资源声明大按钮和字体字段宽度。实际壳的前后截图、GenOffice 对照、静态分析、端到端测试和双端产物见 [`16-ROUND-13-RIBBON-BAND-VISUAL-AND-BUILD.zh-CN.md`](16-ROUND-13-RIBBON-BAND-VISUAL-AND-BUILD.zh-CN.md)。同工作簿等视口逐像素对照及图标细节仍未验收。

第十四轮将签名产品包升至 `0.1.13`、Flutter 通用表面升至 `0.1.12`：视图切换按钮和状态栏色彩、间距、缩放滑块由产品资源声明，表面通用渲染并调度命令。普通视图与分页预览交互、同一测试工作簿的前后截图、GenOffice 参考和双端产物见 [`17-ROUND-14-STATUS-BAR-VISUAL-AND-BUILD.zh-CN.md`](17-ROUND-14-STATUS-BAR-VISUAL-AND-BUILD.zh-CN.md)。点击缩放百分比打开对话框及同工作簿逐像素对照仍待验收。

第十五轮将签名产品包升至 `0.1.14`、Flutter 通用表面升至 `0.1.13`、GridCraft 桥接升至 `0.1.6`：按 GenOffice 源码新增由插件声明的缩放对话框，支持预设、自定义范围校验和适配选区；网格、文字与浮动对象随缩放值实际变化。桥接快照提供选区工作簿尺寸，以便通用表面把视口换算为引擎适配选区命令的参数。视觉对比、交互测试与双端构建见 [`18-ROUND-15-ZOOM-DIALOG-AND-CANVAS-VISUAL-AND-BUILD.zh-CN.md`](18-ROUND-15-ZOOM-DIALOG-AND-CANVAS-VISUAL-AND-BUILD.zh-CN.md)。可变行列尺寸与同工作簿等视口 GenOffice 逐像素对照仍需后续迭代。

第十六轮将签名产品包升至 `0.1.15`、Flutter 通用表面升至 `0.1.14`、GridCraft 桥接升至 `0.1.7`：桥接传输工作簿默认行列尺寸与稀疏覆盖值，表面用统一轴模型布局网格、滚动和浮动对象；行列标题尺寸由签名资源声明。同一可变尺寸 XLSX 的旧版/新版截图、隐藏行和对象几何测试、双端构建证据见 [`19-ROUND-16-WORKBOOK-GEOMETRY-VISUAL-AND-BUILD.zh-CN.md`](19-ROUND-16-WORKBOOK-GEOMETRY-VISUAL-AND-BUILD.zh-CN.md)。同工作簿 GenOffice 实机逐像素对照、字体驱动的默认列宽和复杂对象仍未验收。

第十七轮将签名产品包升至 `0.1.16`、Flutter 通用表面升至 `0.1.15`：在已安装 GenOffice 中打开与 OpenMuse 相同的测试 XLSX，取顶部、定位对话框和 Z100 跳转的实机截图；产品资源声明定位文案、颜色及命令，通用表面完成名称框箭头、菜单入口、合法引用校验和可视区同步。签名资源、真实工作簿测试、视觉差异和双端构建证据见 [`20-ROUND-17-GO-TO-VISUAL-AND-BUILD.zh-CN.md`](20-ROUND-17-GO-TO-VISUAL-AND-BUILD.zh-CN.md)。默认列宽、字体、背景模糊和其余壳细节仍需继续差分验收。

第十八轮将签名产品包升至 `0.1.17`、GridCraft 桥接升至 `0.1.8`：研究 GenOffice 的 Normal 字体最大数字宽度、`baseColWidth` 及字符宽度到像素的换算，在工作簿引擎修正 XLSX 默认与显式列宽，并保持导出逆换算。相同工作簿的 GenOffice 实机、OpenMuse 前后截图及 Z100 视区对照、双端构建证据见 [`21-ROUND-18-NORMAL-FONT-COLUMN-GEOMETRY-VISUAL-AND-BUILD.zh-CN.md`](21-ROUND-18-NORMAL-FONT-COLUMN-GEOMETRY-VISUAL-AND-BUILD.zh-CN.md)。更多 Normal 字体、原生标签栏、状态文案、遮罩模糊和其余 Ribbon 功能仍按计划迭代。

第十九轮将签名产品包升至 `0.1.18`、Flutter 通用表面升至 `0.1.16`：对照 GenOffice 的弹窗遮罩与顶底状态消息，把模糊度、遮罩透明度、颜色及状态文案交给产品资源声明；表面根据引擎快照生成同一状态消息，定位弹窗保留遮罩点击关闭。相同 XLSX 的 GenOffice、改前和改后视觉证据与双端构建见 [`22-ROUND-19-MODAL-STATUS-VISUAL-AND-BUILD.zh-CN.md`](22-ROUND-19-MODAL-STATUS-VISUAL-AND-BUILD.zh-CN.md)。原生标签栏、图标密度、更多定位类型及未接通的 Ribbon 命令仍需逐项验收。
