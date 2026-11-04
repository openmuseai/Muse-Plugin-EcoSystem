# PDF 产品开发、验证与发布计划

## 首版落地状态（2026-10-23）

已交付首个纵向切片：`product/` 中的 7 个 GenOffice PDF 顶级标签、83 个 Ribbon 控件、转换/排列/缩略图菜单、70 色 Office 色板、主题/尺寸、命令目录与功能开关均可经 Ed25519 签名为 `.mcpb`。`ioffice` 的 `PdfProductShell` 用同一套 Flutter 布局绘制顶部 Ribbon、页面区域、缩略图侧栏和状态栏，按宽度收拢侧栏；文档页面和缩略图来自现有 PDF 产品会话。Desktop Host 经 `OpenMusePdfProductPlugin` 验签后注册 `application/pdf` 原生编辑器；Mobile Host 从签名引导包或离线安装包加载相同资源，经资源句柄读入云端 PDF，也在“添加内容”提供本地入口。未实现的注释、表单、转换、签名、AI 控件保持禁用。

首版验证：插件资源校验/打包/验签通过；macOS PDF 独立应用打开 2 页样本、页面渲染、文字编辑、撤销/重做、删页/抽取页集成测试通过；Desktop Host 的签名包加载、PDF 编辑器路由、真实 PDF 打开和 128×128 页面栅格测试通过；macOS Host release 包构建与代码签名校验通过，并启动到 DSH ready；Android Host arm64 release APK 已构建，使用本地测试证书安装至 arm64 模拟器，从 Host“添加内容→PDF 文档”进入产品壳，选择本地两页样本后看到页面及“第 1 页，共 2 页”；Android Host 集成测试也通过签名包验签、原生打开及渲染。证据在 `Muse-Client/dist/pdf-product-evidence-2026-10-23/`。发布签名和上架验收尚未完成；此轮使用本地测试密钥，不能作为商店发行凭据。

后续按交付优先级推进：

### 本轮源码对齐与下一批工作

`App.tsx` 的共享 `markupGroup` 使用“高亮主按钮 + 颜色下拉”，`pageZoomGroup` 使用页码/总页数与缩放百分比两行组合，`viewNavGroup` 在缩略图和大纲之后提供搜索。本轮按这三个结构改动 Flutter 壳及签名资源，并补了桌面控件可达性测试。命令可用性仍由 Host/内核实时判断；选择高亮颜色只是产品界面状态，不能绕开内核能力门禁。

`0.1.1` 继续按 `styles.css` 修正状态栏只跨文档区、34px AI 轨道、150px 缩略图栏、24px 桌面状态栏，以及平板 45px 紧凑 Ribbon。缩略图按原页比例显示，并提供 GenOffice 同序的右键/长按菜单；删页与抽页携带目标页码执行，旋转和插页在内核能力就绪前保持禁用。布局类型和分体按钮类型由签名资源声明，Flutter 解释器不依赖固定标签 ID 决定布局。

`0.1.1` 联合构建记录：`ANDROID_SERIAL=emulator-5554 bash scripts/quick-verify.sh all` 退出码为 0，产出 `dist/quick-verify-all.json`。macOS 产品会话集成测试、Desktop Host 签名包与真实 PDF 渲染测试、Android Host 集成测试均通过；OpenMuse macOS 应用通过代码签名校验，内嵌 `.mcpb` 与独立包 SHA-256 一致。Android 本地测试签名 APK 安装后从 OpenMuse 打开两页 PDF 并显示页面。截图位于 `Muse-Client/dist/pdf-product-evidence-2026-10-23/`。这证明当前纵向闭环；像素级复刻、全部菜单行为、发行签名与真机矩阵仍按以下门禁推进。

`0.1.2` 引入独立签名 `icons.json`，将 GenOffice Apache-2.0 SVG 几何映射到 79 个控件，保留 Muse AI 自有标志；深色颜色取自原 `tokens.css`，活动标签下划线和弹出菜单样式按源码修正。每轮先运行联合构建，再用 `scripts/capture-visual.sh` 固定截取七标签与菜单；[视觉对比台账](04-VISUAL-PARITY-ROUNDS.zh-CN.md) 记录参照、截图和剩余差异。后续视觉改动必须更新台账及目标端截图，不以静态控件计数替代 1:1 验收。

`0.1.3` 从 GenOffice 共用 `color-picker.tsx` 同步 70 个主题、明暗和标准色至签名 `chrome.json`；Flutter 解释器实现高亮分体按钮、绘制颜色弹层和自定义颜色输入。活动 Ribbon 标签再次点击可收起工具带，选择其他标签重新展开。核对源码后将“排列”改成原版单层 11 项及“需先选中两个字段”的禁用条件，移除原版没有的水印/图章多级菜单；水印对话框待接真实能力。`scripts/quick-verify.sh macos|all` 现在在构建中自动截取 7 个标签、转换菜单、色板、收起态、平板和手机视口，报告记录截图摘要。

`0.1.4` 对照 `App.tsx` 的 `openExtractDlg`/`confirmExtract` 与 `.pdf-modal-*` 样式，实现“页面→抽取页面”的页码范围参数弹窗。标题、提示与按钮由签名 `chrome.json.dialogs.extractRange` 提供；Flutter 只负责展现与输入状态，`PdfProductBackend` 调用现有页面组合 ABI 真正抽取任意非空页集。页码语法与 GenOffice 同为 `1-3,5`、中文逗号及 en dash，排序去重、越界拒绝；缩略图右键入口仍直接抽取所选页。命令仍受 Host 的签名资源、功能开关及实时内核能力门禁限制。Host E2E 增加桌面及 390px 手机弹窗截图，台账见 [视觉对比](04-VISUAL-PARITY-ROUNDS.zh-CN.md)。下一步按相同方式把其余页面参数弹窗逐项接入，先补对应 ABI 再启用叶节点。

`0.1.5` 对照 GenOffice `pdf-search-bar`、`searchStep` 和页面命中层，把“搜索”改为文档区右上角的常驻工具条。签名 `chrome.json.searchBar` 只配置文案与输入宽度；Flutter 编辑表面使用现有产品 PDF 会话的结构化文本，显示总命中、当前索引、循环跳转及页面高亮。Host E2E 在真实两页 PDF 验证 `1/2→2/2`，并保存桌面及窄屏截图。Android 设备检查发现系统最小触控目标会使 `IconButton` 将浮层挤出左边界，已改为固定 26px 的可访问点击区域，并新增 360px 宽度边界测试。下一轮需测大文档检索耗时与键盘交互、继续接页面参数弹窗。

`0.1.6` 对照 GenOffice `openSplitDlg`/`confirmSplit`，在页面 Ribbon 启用“拆分 PDF”参数弹窗及“倒序”。两条命令由签名包声明并经过 Host 功能开关、文档页数和页面组合 ABI 门禁；拆分在产品会话的当前快照上按 N 页分段，倒序反转页序。桌面与手机弹窗视觉证据及 5 页拆成 2/2/1 的测试见[台账](04-VISUAL-PARITY-ROUNDS.zh-CN.md)。当前保存多个结果依次打开系统保存选择器，下一轮需设计跨端多文件导出服务，使一次目标选择可原子写入全部分片并支持取消/回滚。

Android 真机流程门禁在本轮发现独立 `pdf-flutter-app` 的 `savePdf` 通道没有随 Flutter 页面嵌入 OpenMuse Host；已在 Android Host 增加独立 `PdfDocumentSaveBridge` 并给集成测试增加通道合同断言。设备重验完成两页拆分的两次保存，分别拉回并检查为单页 PDF。以后新增平台通道必须同时更新各端 Host 注册和设备级调用断言；仅页面渲染通过不足以证明编辑导出可用。

`0.1.7` 对照 GenOffice `pdf-main.ts` 的 `splitPdf` IPC：确认后只选一次目录，按 `{base}-{index}.pdf` 输出全部分片。插件签名资源现在声明 `destinationMode=directory` 与 `fileNamePattern`；Flutter 编辑表面解释该策略并调用导出端口。桌面使用一次目录选择、同卷暂存后发布且拒绝覆盖既有文件；Android Host 使用 Storage Access Framework 目录选择与 `DocumentsContract` 批量写入，失败时尽力删除本次新建文件。iOS 和 Web 在目录能力不可用时保留逐文件保存流程；这两端尚未列入本轮交付验收。新增桌面文件合同单测和 Android Host 平台通道集成断言，实际目标端的选择器操作必须另行记录设备证据。

`0.1.8` 对照 GenOffice `extractPagesToFile`/`pdf-main.ts`：单页生成 `{base}-p{first}.pdf`，页集生成 `{base}-p{first}-{last}.pdf`，桌面写入默认文档目录并在重名时追加 `-2`，成功后显示抽取结果。签名 `chrome.json.dialogs.extractRange` 只声明命名和目标策略；Flutter 从唯一 PDF 产品会话提取页集，桌面文件适配器写入 `Documents/OpenMuse`，Android 走 Host Storage Access Framework 单文件创建选择器。原版 GenOffice 默认目录可由设置修改；OpenMuse 尚无对应 Host 设置，故此轮先固定其自身默认目录并将可配置目录列入后续 Host 服务演进。取消 Android 保存时保持原文档，不把未保存的结果冒充已导出。视觉证据继续在相同签名包下拍摄桌面/手机弹窗和目标端保存反馈。

`0.1.9` 对照 GenOffice `view-config.ts` 与 `styles.css`，将状态栏缩放范围、5% 滑杆步进、18 个加减档位、110px 滑杆和状态文案纳入签名 `chrome.json.statusBar`。Flutter 壳只解释资源并经会话的 `onZoom` 端口请求缩放。macOS/Android 联合构建、真实两页 PDF Host 测试和固定视口截图通过，见[第 8 轮台账](04-VISUAL-PARITY-ROUNDS.zh-CN.md)。可配置桌面目录及保存/只读状态仍待下一轮，不把底栏缩放对齐称为整壳逐像素完成。

`0.1.10` 对照 GenOffice `view-config.ts`、`App.tsx` 和 `styles.css` 推进文档侧栏：150px 默认宽度、120px 下限、320px 与窗口 40% 双重上限、24px 缩略图栅格留白，以及拖动结束才重新栅格化和持久化。尺寸与偏好键由签名 `chrome.json.sidebar` 描述，Flutter 壳负责指针交互和偏好存储，PDF 页面与缩略图继续从产品会话渲染。桌面固定视口测试检查实际拖动后的侧栏宽度及非空缩略图，[第 9 轮台账](04-VISUAL-PARITY-ROUNDS.zh-CN.md)逐区登记参照和证据。此轮未实现可配置桌面默认目录和会话保存/只读反馈，继续列为下一批任务。

`0.1.11` 先处理整壳最显著的 AI dock 缺口：按 GenOffice `AiPanel.tsx` 与 `styles.css` 声明 34px 收起轨道、360px 默认面板、280–720px 和视口 60% 上限、6px 拖拽条及 180ms 过渡。签名 `chrome.json.aiDock` 管理几何、文案和偏好键；Flutter 只负责 dock 交互与可注入的 `assistantContent` 视图槽。未安装 AI 能力时保持输入和快捷按钮禁用并显示原因，不由 PDF 壳模拟 AI 答复。桌面 Host 从签名包打开真实 PDF 后捕获收起、展开、拉宽状态，手机使用同一资源显示底部面板，见[第 10 轮台账](04-VISUAL-PARITY-ROUNDS.zh-CN.md)。可配置保存目录和会话状态顺延到下一轮。

`0.1.12` 将 GenOffice 顶部标签行右侧的保存状态接入 PDF 产品会话。签名 `chrome.json.ribbonState` 声明文案、字号与反馈时长；状态颜色在 `0.1.13` 迁入主题调色板。独立 `PdfDocumentStatus` 只表达有无文档、是否有待保存修改、只读及副本保存进度。OpenMuse 当前命令是“另存副本”，所以成功状态明确写作“副本已保存”，反馈结束后仍以产品后端 `isDirty` 显示原文档待保存状态。取消系统选择器不显示成功，保存中禁用重复提交。可配置桌面默认目录继续作为下一轮 Host 服务处理。

`0.1.13` 优先修正整壳主题差异：GenOffice 仓内参照图使用浅色，而此前 OpenMuse 默认深色。签名 `chrome.json.themes` 现声明浅色默认与深色备用调色板，覆盖顶部 Ribbon、中间画布与侧栏、底部状态栏、菜单悬停和保存状态；Flutter 解释器只选择资源并绘制。两套色值逐项对照 `packages/ui/src/tokens.css` 与 `apps/pdf/src/renderer/styles.css`，另有解析器测试验证主题选择。桌面默认目录作为后续 Host 服务处理，不由 PDF 壳自行决定保存位置。

`0.1.14` 对照 GenOffice `.rb-drop`、`.rb-menu` 和 `.thumb-menu` 细化菜单：签名 `chrome.json.menuPresentation` 分别描述 Ribbon 命令菜单、缩略图右键菜单和色板弹层；`themes.*.borderStrong` 来自共享 token。Flutter 显式固定菜单视觉密度和点击目标尺寸，防止同一签名资源在桌面 Host 与独立产品测试里落到不同 Material 默认值。Host E2E 对菜单条目高度、宽度和真实 PDF 截图同时验收；菜单命令的能力可用性仍由产品会话判定。可配置桌面默认目录 Host 服务顺延至 `0.1.15`。

`0.1.15` 对照 GenOffice `ai-panel-prefs.ts`、`ai-panel-prefs-store.ts`、PDF `App.tsx` 与 `styles.css`，将桌面 AI 面板初始状态改为签名资源声明的默认展开（360px），仍允许用户开合与宽度偏好覆盖。Flutter 壳收起面板时保留注入的 AI 插件视图状态，避免聊天草稿被销毁；未连接 AI 插件时继续禁用发送与快捷命令。状态栏按 AI 面板之后的实际文档列宽度收起缩放滑杆，所需的最小列宽由签名 `chrome.json.statusBar.minSliderColumnWidth` 声明，解决 700px 窄窗溢出。Host E2E 使用真实两页 PDF，在 2400×1530 物理像素、1.5 DPR 下另拍整壳图；与 GenOffice 仓内参照的结构、边界和未对齐处见[第 14 轮台账](04-VISUAL-PARITY-ROUNDS.zh-CN.md)。

`0.1.16` 对照 GenOffice `styles.css`、`view-config.ts` 和 `App.tsx` 的页面视口，将左右 24px、上下及页间 16px、`0 1px 4px / 18%` 页面阴影写入签名 `chrome.json.pageViewport`。Flutter PDF 表面解释布局并继续通过产品会话提供真实页面；Host 不承担页面几何。真实两页 PDF 的 Host E2E 断言页面矩形、页间距和阴影，并保留 `0.1.15→0.1.16` 同场景前后图及与 GenOffice 原图的整壳并列图，见[第 15 轮台账](04-VISUAL-PARITY-ROUNDS.zh-CN.md)。可配置桌面默认目录是 Host 服务，顺延到 `0.1.17`；完整像素验收仍需同 PDF、字体、主题、语言、DPR 和 AI 状态。

`0.1.17` 对照 GenOffice 的 `default-save-dir.ts`、`pdf-main.ts` 和 `generated-output.ts`，补可配置桌面生成文件目录。Host 通用设置保存用户选择的绝对路径，并把实时读取端口注入 PDF 产品工作区；PDF 表面依签名抽页目的地策略检查目标目录可写性、退回默认目录并使用已有的防覆盖命名。配置目录不可用时不篡改用户偏好，Android 继续走系统授权的保存选择器。Host E2E 从真实两页 PDF 的 Ribbon 抽取第 1 页、写入所配目录，结果再由独立 `pdfinfo` 检查；工作区设置图与整壳对照见[第 16 轮台账](04-VISUAL-PARITY-ROUNDS.zh-CN.md)。GenOffice 的生成文件新标签打开行为仍需 Host 文档标签端口，留待下一轮；整壳像素验收仍需同条件语料。

`0.1.18` 对照 GenOffice `pdf-main.ts` 的 `openGeneratedPdf`：抽页完成持久化后请求外层 Shell 打开新的 PDF 标签。签名资源声明 `desktopOpenResult=newDocumentTab`，`ioffice` 的 PDF 表面只发出生成文件路径事件，Host 通过专用导航适配器检查路径并调用工作区 `openResource`。原 PDF 会话与页面数保持不变，目标文件成为活动标签；没有 Host 标签端口的独立/移动表面继续使用原有打开结果流程。签名包、真实 PDF E2E、macOS ZIP、Android APK 与逐区截图见[第 17 轮台账](04-VISUAL-PARITY-ROUNDS.zh-CN.md)。本轮默认桌面整壳与 `0.1.17` 同条件截图逐像素相同；GenOffice 对照仍因文档、语言、AI 内容和外层窗口不同而不能宣称整壳 1:1。

本轮从桌面缩到手机的首张截图发现页面沿用桌面 182% 缩放而横向裁切。现已把视口宽度变化接入 `PdfWorkspace` 的适应宽度/适应页面状态，在同一会话重算 PDF 查看矩阵；新的桌面→平板→手机 Host E2E 断言缩放下降，并用真实页面截图验证。手动缩放会退出自动适应，避免用户调整被窗口变化覆盖。

下一批按可验收依赖顺序执行：

1. **交互轨迹**：逐项列 `App.tsx` 中标记、绘制、签名、页面组合、表单的弹窗/菜单/模式切换，给每个入口定义参数、取消、Esc/返回、禁用理由；优先实现纯壳状态和已有 ABI 可执行的操作。未实现的 PDF 写回能力保持禁用。
2. **视觉差异**：固定 1365×860、1024×768、平板、390×844 的截图，逐区核对 Ribbon 图标、间距、字级、画布起始位置、缩略图比例及底栏；记录差异图和阈值。已映射的控件使用签名包中的 GenOffice SVG；未映射的状态与 Muse 自有品牌图标仍需逐项验收，当前尚未达到逐像素复刻。
3. **会话状态**：从唯一 PDF 产品会话推送保存中/已保存/失败、当前工具、选区、只读、页数、缩放；工具状态不能只由壳本地推断。
4. **签名发布**：保持产品资源包和原生表面分别版本化；每次资源更新执行签名、旧包兼容、macOS Host 和 Android Host 打开真实 PDF、离线重启及摘要报告。当前本地测试签名只供人工验收。

## 可执行基线和优先级

沿用 [`ioffice` 既有产品方案](../../../../ioffice/koffice/pdf/rebuild/docs/product-integration/PLAN.md) 与 [`pdf-flutter-app`](../../../../ioffice/koffice/pdf/rebuild/pdf-flutter-app/README.md)。当前能够复用：macOS arm64、Android arm64、Web 的产品会话；打开、页面渲染/区域渲染、文字/链接、基础文字编辑、撤销/重做、导出；页面组合/抽取/删除/合并的部分流程。Flutter 编辑表面已作为同一源码包嵌入 Desktop/Mobile Host，产品配置解释器和验签器已接入。Windows/Linux、iOS 真机未有本产品放行证据；iOS 当前 `ioffice` 计划暂停验收。

| 里程碑 | 工作与仓库归属 | 完成标准 | 建议投入 |
| --- | --- | --- | --- |
| M0 合同与样本 | `pdf-product` 建功能/菜单/命令台账、JSON Schema、签名资源 profile；`ioffice` 固定 ABI 能力查询；Host 定义 PDF 产品路由 | 同一清单逐项标 `ready/planned/blocked`，不支持项有禁用理由；静态合同与签名篡改测试 | 1–2 工程人周 |
| M1 可用阅读产品 | `ioffice` 抽出 Flutter `pdf_surface`，保留 `PdfProductBackend`/`ProductPdfDocument`；本插件提供七标签、侧栏、页面区、底栏声明；Host 注册 `application/pdf` 原生编辑器 | macOS OpenMuse 真正安装资源包后打开 160 页语料、显示页数和首/末页、缩略图/大纲入口、缩放/搜索/链接、断网重开；Android 真机和 Web 同源表面打开渲染；未接能力保持禁用 | 4–7 人周 |
| M2 完整壳与响应式 | Flutter 实现全部 Ribbon 标签、各级菜单、工具状态、对话框、侧栏/底栏及四类窗口布局；插件资源驱动命令排序/图标/快捷键/主题 | 七标签和所有登记菜单可到达；桌面、平板、折叠屏、手机截图与操作轨迹通过；无布局溢出；启用按钮都有真实命令 | 4–6 人周 |
| M3 编辑与页面工具 | `ioffice` 扩注释、页面、表单所需 ABI；Flutter 接文本/选区/批注、工具模式、页操作；Host 原子另存 | 修改→撤销→重做→另存→独立解析器重开；不保真的页面组合明确拒绝；三端共享命令语义与 PDF 结构回归 | 8–14 人周 |
| M4 高风险与扩展 | 涂黑内容净化、证书签名、表单设计、OCR/AI/转换逐项实现或保持关闭；扩展显式调用、权限和预算 | 涂黑后文字/图像不可恢复，签名独立校验；扩展失败不损伤原文；无能力项目仍被禁用 | 8–16 人周，依能力分批 |
| M5 发行质量 | 清理原生重复阅读库、复杂文档/字体/加密语料、性能、崩溃恢复、市场升级回滚 | macOS/Android/Web 目标端 full E2E、离线、性能基线、签名发布证据齐全；其他端按各自门禁逐步放行 | 持续 |

建议先做 **M1 纵向闭环**，再扩 M2 全壳；M2 的视觉工作可与 M3 内核开发并行。投入为规划估算，不代表能力已经实现。大纲/旋转/复杂 PDF 的缺口在 M1 可以显示入口与禁用解释，但不得伪造数据。

## 一键联合构建与版本流

当前可从插件目录执行 `scripts/quick-verify.sh macos|android|all`：签名资源、核对 staged chrome、按目标端构建产品原生库、运行 macOS PDF 与 Host 集成测试、构建 OpenMuse macOS 包或 Android APK。`ANDROID_SERIAL` 可指定要安装本地测试签名 APK 的设备；生产 Android 签名仍走发行密钥。下一步把脚本提升为根目录 `pdf:plan|pdf:build|pdf:e2e`，加入 Web、设备截图、全量报告与版本矩阵。`pdf:plan` 只解析当前三仓版本/能力/依赖；`pdf:build` 构建固定 PDFium 产品库或使用显式校验过的锁定产物、Flutter 表面、Host、签名插件并验签；`pdf:e2e` 在真正目标进程安装并打开固定 PDF 后采集证据。内核或表面有更改时，禁止默默复用过期二进制；缓存键包含源码/补丁、工具链、目标三元组与构建参数。Web 记录加载的 `ksp_product.wasm` 摘要并证明断网缓存重载。

报告应至少记录：Host/`ioffice`/插件的 Git commit 和脏树状态、ABI/Profile/表面版本、签名包与目标端内核哈希、设备/浏览器与 OS、输入 PDF 哈希、安装/打开/渲染/命令/导出重开每步结果和截图、性能样本、失败原因。开发态允许脏树但报告必须标记；正式发行必须锁定 clean revision 与生产密钥。修改内核运行 `ioffice` 的 [`tool/verify.sh`](../../../../ioffice/koffice/pdf/rebuild/pdf-flutter-app/tool/verify.sh) 相应门禁，再执行三仓 `pdf:e2e`；仅 Flutter/插件变更也需至少跑受影响平台的真实 Host E2E。旧签名包和新包须在新 Host 上各跑一次兼容测试。

## 最小 E2E 场景与质量门禁

1. 安装：验签、拒绝篡改、离线导入、版本不兼容拒绝、安装失败回滚。与 `pdf-reader` 同时安装时，PDF 产品编辑器由明确的 Host 优先级路由，Provider 合同不受影响。
2. 阅读：打开普通/加密/损坏/大页数 PDF，页数、首末页、缩略图、大纲、链接、搜索、缩放/适应、连续滚动与内存回收；M1 以普通文档闭环为放行目标，其他类型按能力列表决定支持或明确报错。
3. 编辑：IME（中英混输）、文字选择、修改、撤销/重做、另存、独立解析器重开，比较文字、页面数和渲染图；页面操作检查注释/链接/书签/表单/签名的保留或拒绝。
4. 壳：七标签、所有二级组/下拉菜单、快捷键、状态栏、工具禁用态；1365×860、1024×768、折叠窗口与 390×844 手机，横竖屏及高 DPI。触控、键鼠和屏幕阅读器分别验证。
5. 原生/离线：macOS OpenMuse 独立窗口与内嵌标签页均加载 Flutter 表面，无 WebView 承担 PDF 页面绘制；Android 真机离线打开/保存；Web 首次安装后离线重载仍能打开用户授权文件。M1 如设备或浏览器未跑，报告标 blocked，不能宣称跨端通过。
6. 性能目标（待基线校准）：长文档首屏、滚动帧率、缩略图缓存内存与页面区域重绘延迟均记录 P50/P95；超出回归阈值阻止发布。大文件预算由实测确定，不先写无证据的绝对 SLA。

## 发布节奏

合并到集成线：M0 合同与签名测试、`ioffice` headless/Flutter 测试、macOS quick Host E2E；影响 Android/Web 的变更增加目标端 quick。每日 full 在现有 macOS、Android、Web 目标矩阵运行；发布候选冻结三仓版本、PDFium 基线/补丁、工具链和插件包摘要，在目标端真机/真实浏览器重跑 full，并验证离线安装、升级、回滚。按端声明已验收范围；iOS/Windows/Linux 只有对应内核产物和 Host E2E 通过后才进入发布矩阵。产品包升级只变更签名资源/低频扩展；内核或 Flutter 表面升级随 Host 发行。每次发布附兼容清单和完整报告，避免“插件更新后按钮可见但内核不支持”。
