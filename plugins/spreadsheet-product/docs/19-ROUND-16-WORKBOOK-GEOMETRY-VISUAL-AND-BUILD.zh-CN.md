# Spreadsheet 产品壳第十六轮：工作簿行列尺寸与统一坐标

## GenOffice 源码和设计边界

本轮核对 GenOffice `apps/sheets/src/renderer/univer-sync.ts` 对 XLSX 默认行高、列宽、逐行列覆盖值和隐藏状态的导入，以及 `visual-geometry.ts`、`WorkbookVisuals.tsx` 中浮动对象沿工作表真实行列尺寸定位的路径。此前 OpenMuse 只按固定 104×28 逻辑像素绘制网格；即使工作簿存有宽窄列、不同高度和隐藏行，编辑区仍显示等宽等高格子。

GridCraft 桥接 `0.1.7` 在快照输出默认尺寸与稀疏覆盖值，继续由单一工作簿模型决定几何。Flutter 通用表面 `0.1.14` 新增独立的 `SheetAxisGeometry`：通过稀疏前缀差值计算远处单元格起点、位置反查和可见范围；网格、标题、选区、滚动、缩放和浮动对象共用该坐标。签名产品资源 `0.1.15` 声明行列标题尺寸，继续声明 Ribbon、菜单和底栏；它不存工作簿数据，也不嵌入桥接或 Flutter 代码。Host 只验签、装载、路由和交付，保持 Everything is plugin 的边界。

本轮把对象锚点的单位与 GridCraft 模型使用的 96 DPI 工作簿像素对齐。对象拖动和缩放先在共享坐标里定位，再写回工作簿锚点。行列标题文字保持固定字号，避免高缩放时挤出标题栏。

## 同一工作簿的前后视觉对比

测试工作簿 `spreadsheet-geometry.xlsx` 含 154px 的 B 列、28px 的 C 列、112px 的 D 列；第 1 行 40px、第 2 行 12px、第 4 行隐藏。两张 OpenMuse 截图均在 1365×860 视口、100% 缩放下拍摄。

| GenOffice 整体壳参考 | 第十五轮 OpenMuse：忽略工作簿尺寸 | 第十六轮 OpenMuse：使用工作簿尺寸 |
| --- | --- | --- |
| ![GenOffice Ribbon、编辑区与底栏参考](evidence/round-16/genoffice-reference.png) | ![同一可变尺寸工作簿旧版](evidence/round-16/desktop-variable-geometry-before.png) | ![同一可变尺寸工作簿新版](evidence/round-16/desktop-variable-geometry.png) |

旧版 B、C、D 均为固定宽度，第 4 行也继续显示；新版 B 列扩宽、C 列收窄，第 1/2 行高度不同，第 4 行不占显示高度。端到端测试直接断言 A1、B1、C1、D1 的矩形宽度、前两行高度，以及 A5 紧接 A3 的位置。

| 壳区域 | 本轮证据 |
| --- | --- |
| 顶部多级 Ribbon | [开始页](evidence/round-16/desktop-home.png)、[插入页](evidence/round-16/desktop-insert.png)、[边框二级菜单](evidence/round-16/desktop-border-submenu.png)回归；菜单仍由签名产品树驱动。 |
| 中间编辑区 | [普通工作簿前后](evidence/round-16/desktop-home-before.png)与[新版](evidence/round-16/desktop-home.png)、[适配选区 400%](evidence/round-16/desktop-zoom-fit-selection.png)、[图表/形状/图片](evidence/round-16/desktop-objects.png)及[75% 对象](evidence/round-16/desktop-objects-zoom-75.png)。 |
| 底部状态栏与响应式 | [状态菜单](evidence/round-16/desktop-status-menu.png)、[手机宽度](evidence/round-16/mobile-view.png)、[平板宽度](evidence/round-16/tablet-view.png)，继续显示视图与缩放。 |

GenOffice 参考图与本轮测试使用不同工作簿，尚不能作同工作簿逐像素差异计算；表中前后对比仅针对同一 OpenMuse 测试 XLSX。当前壳仍不应标为 1:1 验收完成。

## 测试和人工验证产物

签名包生成、Schema 校验和 Ed25519 开发密钥验签通过。五项纯几何测试及六项 Host 端到端测试通过，包括签名资源、可变行列与隐藏行、真实 XLSX 编辑保存重开、对象几何、缩放和既有 Ribbon／底栏路径。macOS 与 Android 流水线报告分别记录两份测试工作簿、源码、截图、原生库和产物哈希。Android Release APK 使用本地调试密钥签名，供人工验证。

| 产物 | SHA-256 |
| --- | --- |
| [macOS Release ZIP](/Users/mac/src/openmuse-io/Muse-Client/dist/OpenMuse-spreadsheet-0.1.15-macos.zip) | `9a189feb7e1a30510445d47641d297bc382fb104b2a6edcff3be7b736e484ca0` |
| [Android arm64 Release APK](/Users/mac/src/openmuse-io/Muse-Client/dist/OpenMuse-spreadsheet-0.1.15-android-arm64.apk) | `e0eddbdc6d8645aa550600d3427d938a4eb7a64ecb3cd8e3060f8a2bd77d3a44` |
| [签名产品包](/Users/mac/src/openmuse-io/Muse-Plugin-Ecosystem/plugins/spreadsheet-product/dist/spreadsheet-0.1.15.mcpb) | `f5afa3506ab42e3e7fc8f4d83b3624adf2a3be7efabd52f587853f7fb4736300` |
| [macOS 构建报告](evidence/round-16/build-report-macos.json)、[Android 构建报告](evidence/round-16/build-report-android.json) | 包含上述 SHA-256 与截图清单 |

## 剩余差距

行尺寸稀疏列表最多传输 65,536 个覆盖值；极端工作簿超过上限时快照标记不完整，状态栏显示“行尺寸预览受限”。GenOffice 对默认列宽还会按 Normal 字体的最大数字宽度校准，当前 GridCraft 导入模型与它未做同文件差分；冻结窗格、RTL、旋转对象及复杂图表保真也仍需继续实现。下一轮应先取得同一 XLSX 的 GenOffice 实机截图，再校准默认列宽、字体与可视窗口滚动，并形成逐像素差异图。
