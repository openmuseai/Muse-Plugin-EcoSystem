# Spreadsheet 产品壳第十轮：图片与形状对象层

## 实现与责任边界

继续对照 GenOffice `apps/sheets/src/renderer/WorkbookVisuals.tsx` 的对象浮层。本轮签名产品包为 `0.1.9`，在“插入→形状”的菜单中声明矩形、圆角矩形、椭圆、三角形、箭头和文本框的命令参数。菜单结构与参数由产品插件提供，Flutter 表面只消费声明并派发命令。

GridCraft 桥接 `0.1.5` 从当前工作表读取图片、形状及锚点，连同图表组成有界对象快照。图片字节按对象 ID 另行获取，避免每次单元格刷新都传输媒体；当前只预览不超过 2 MiB 的 PNG/JPEG/WebP/GIF。Flutter 通用表面 `0.1.8` 在网格上方绘制支持的形状、图片和图表，滚动时按锚点移动；点选对象切换“形状格式”“图片格式”或“图表设计”上下文 Ribbon。工作簿内容、对象、保存与重开语义由 GridCraft 持有，界面只缓存图片字节和当前选择。无法绘制的形状明确显示“形状不可预览”。

## 视觉对照证据

下图将 2750×1706 的 GenOffice 参考图与 1365×860 的 OpenMuse 桌面截图并列，后者接近参考图一半的像素尺寸。两张图**不是同一工作簿**，所以这里只比较壳的区域组织和浮动对象行为，不能据此声称逐像素或内容 1:1。

| GenOffice 参考 | OpenMuse 第十轮 |
| --- | --- |
| ![GenOffice Ribbon、对象编辑区和状态栏](evidence/round-10/genoffice-reference.png) | ![OpenMuse Ribbon、真实 XLSX 图表、形状、图片和状态栏](evidence/round-10/desktop-objects.png) |

| 对照项 | 证据 | 本轮结果及可见差距 |
| --- | --- | --- |
| 顶部多级 Ribbon | [开始](evidence/round-10/desktop-home.png)、[插入](evidence/round-10/desktop-insert.png)、[形状菜单](evidence/round-10/desktop-shape-menu.png) | 保持 7 个常驻与 4 个上下文标签、55 组、183 个控件、66 棵菜单；形状菜单参数已可派发。GenOffice 的部分图标、组宽、控件间距、文字排布仍有差异。 |
| 中间编辑区 | [图表、圆角矩形和图片](evidence/round-10/desktop-objects.png)、[插入椭圆后](evidence/round-10/desktop-shape-inserted.png) | 三类对象与单元格同时显示，形状使用工作簿颜色、文字和锚点，图片来自 XLSX 媒体。对象的拖拽、缩放、裁剪及复杂形状路径尚未还原。 |
| 上下文菜单 | [形状格式](evidence/round-10/desktop-shape-context.png)、[图片格式](evidence/round-10/desktop-picture-context.png) | 点选对象会出现对应标签；部分格式命令仍受 GridCraft 能力限制，不能视为完成所有编辑动作。 |
| 底部状态栏 | [桌面整体](evidence/round-10/desktop-objects.png)、[状态菜单](evidence/round-10/desktop-status-menu.png) | 表签、状态、视图按钮与缩放保留；图标和间距尚未与 GenOffice 等视口校准。 |
| 窄屏 | [手机宽度组件](evidence/round-10/mobile-objects.png)、[平板宽度组件](evidence/round-10/tablet-view.png) | 同一表面可显示形状和图片。手机截图中的图表超出当前可视范围；需滚动查看，未做移动端对象专属布局。 |

## 数据、测试和构建

[真实 XLSX 往返样本](evidence/round-10/objects-roundtrip.xlsx) 同时包含单元格、图表、圆角矩形和 PNG 图片。Host 的 5 项端到端测试通过：签名包验签与篡改拒绝、编辑/导出、图表往返、对象往返及菜单派发、自动保存和上下文 Ribbon。重开后核对对象类型、文字、图片字节和绘制指令；对象 ID 是会话标识，导入时会重新分配，因此测试按内容核对，并用新 ID 验证点选。`cargo fmt --check`、`cargo check`、`flutter analyze`、产品生成/校验与双端 Release 流水线通过。

macOS ZIP 完成严格代码签名校验，Android arm64 APK 完成构建与双端产品包哈希核对。报告分别见 [macOS](evidence/round-10/build-report-macos.json)和 [Android](evidence/round-10/build-report-android.json)。产物使用本地开发密钥签名，供人工验证；仓库报告记录了开发态脏树。

| 人工验证产物 | SHA-256 |
| --- | --- |
| [macOS Release ZIP](/Users/mac/src/openmuse-io/Muse-Client/dist/OpenMuse-spreadsheet-0.1.9-macos.zip) | `c8f43464d715ef8e6a57b0aa2a14738997bfe8747e250dcb8b76cbdd0c07cd5e` |
| [Android arm64 Release APK](/Users/mac/src/openmuse-io/Muse-Client/dist/OpenMuse-spreadsheet-0.1.9-android-arm64.apk) | `f7c5870c560ed94600b3b7ccd8e081fb74ebe3c36cabde96b36396cbf8f6c0c7` |
| [签名 Spreadsheet 产品包](/Users/mac/src/openmuse-io/Muse-Plugin-Ecosystem/plugins/spreadsheet-product/dist/spreadsheet-0.1.9.mcpb) | `ffda40e2609ebfd480072e0cef918e19c82fb8a346867e38760e3cffcdb4c9cf` |

## 下一轮差距

当前仍未达到 GenOffice 1:1。对象快照限每个工作表前 16 个图表、16 个形状、8 张图片，超出数量或媒体预算时状态栏给出预览受限提示；需要按可视范围分页获取。对象拖拽、缩放、层级调整和图片插入文件选择尚待接入；复杂形状几何与格式保真需要扩大语料。下一轮应取得 GenOffice 与 OpenMuse **同一复杂 XLSX、同视口、同缩放**截图，再逐项调整 Ribbon 控件尺寸、公式栏和底栏，并补全对象交互与保存保真门禁。
