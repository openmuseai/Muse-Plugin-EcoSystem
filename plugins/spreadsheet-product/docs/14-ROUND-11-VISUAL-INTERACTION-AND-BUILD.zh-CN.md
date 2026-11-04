# Spreadsheet 产品壳第十一轮：浮动对象移动、缩放与删除

## GenOffice 源码对照与方案

本轮继续核对 GenOffice `apps/sheets/src/renderer/WorkbookVisuals.tsx` 的 `EditableShapeVisual` 和 `styles.css` 的 `.shape-editable`：对象在拖动时预览，释放时提交锚点；选中框有 2px 描边、白底蓝边圆形控制点，Delete/Backspace 删除对象。GenOffice 使用八个缩放点、可变行列尺寸、旋转对象的真实边框尺寸及 RTL 坐标。OpenMuse 本轮实现右下角缩放点、自由拖动和删除/撤销，后几项仍待分批对齐。

签名产品包 `0.1.10` 声明 `visualActions.move/resize/delete` 对应的引擎命令；通用 Flutter 表面 `0.1.9` 识别指针与键盘交互，并用独立 `VisualGeometry` 把屏幕位移换算成工作表锚点和尺寸。GridCraft 桥接继续使用 `0.1.5`，工作簿对象由唯一内核保存、撤销与重开。旧签名包没有 `visualActions` 时，表面不会显示缩放控制点，也不会启用对象变更手势。

## 视觉对照证据

GenOffice 参考图与测试 XLSX 内容不同，因此下表只对照壳区域；第二张同工作簿对比展示本轮对象交互前后的真实变化。OpenMuse 截图视口为 1365×860，参考图为 2750×1706。当前仍**不能宣称同工作簿逐像素 1:1**。

| GenOffice 参考 | OpenMuse 第十一轮 |
| --- | --- |
| ![GenOffice Ribbon、内容区和状态栏](evidence/round-11/genoffice-reference.png) | ![OpenMuse Ribbon、编辑区对象和状态栏](evidence/round-11/desktop-objects.png) |

| 同一 XLSX 初始位置 | 拖动并缩放后的保存状态 |
| --- | --- |
| ![形状初始位置](evidence/round-11/desktop-objects.png) | ![形状移动和缩放](evidence/round-11/desktop-shape-resized.png) |

| 对照项 | 本轮证据与差异 |
| --- | --- |
| 顶部 Ribbon | [开始](evidence/round-11/desktop-home.png)、[插入](evidence/round-11/desktop-insert.png)、[多级形状菜单](evidence/round-11/desktop-shape-menu.png)、[形状格式](evidence/round-11/desktop-shape-context.png)：11 个标签、55 组、183 控件、66 棵菜单继续由产品资源声明；部分图标、间距和格式命令仍未还原。 |
| 中间编辑区 | [拖动后](evidence/round-11/desktop-shape-moved.png)、[缩放后](evidence/round-11/desktop-shape-resized.png)、[Delete 删除图片后](evidence/round-11/desktop-picture-deleted.png)：图表、形状、图片仍共享网格锚点；选中框增加一个圆形缩放点。GenOffice 的其余七个缩放点、对象多选、旋转和层级操作尚未实现。 |
| 底部状态栏与窄屏 | [状态菜单](evidence/round-11/desktop-status-menu.png)、[手机宽度](evidence/round-11/mobile-objects.png)、[平板宽度](evidence/round-11/tablet-view.png)：状态、表签、视图切换、缩放保留。手机截图来自 Flutter Host 组件测试，不代表 APK 内实机截图。 |

## 功能与产物验证

在 [原始对象工作簿](evidence/round-11/objects-roundtrip.xlsx) 中拖动并缩放圆角矩形后，通过 Host 保存成 [编辑后工作簿](evidence/round-11/objects-edited.xlsx)。独立 GridCraft 会话重新打开，核对锚点行列、宽高；图片删除后用撤销恢复。五项 Host 端到端测试覆盖签名验证、真实 XLSX 编辑导出、图表和对象往返、上下文 Ribbon 与自动保存。产品校验、Flutter 静态分析、macOS/Android Release 构建和签名验证见双端报告。

双端[联合构建报告](evidence/round-11/build-report-all.json)记录产物、源码和样本哈希。产物用于本地人工验证，使用开发密钥；报告保留仓库提交及脏树状态。macOS ZIP 与 APK 均已验签，ZIP 完整性和两端内嵌产品包哈希已由流水线核对。

| 人工验证产物 | SHA-256 |
| --- | --- |
| [macOS Release ZIP](/Users/mac/src/openmuse-io/Muse-Client/dist/OpenMuse-spreadsheet-0.1.10-macos.zip) | `d844a1e39115852317559b8dfe8585c6107584501fa4657d35c72463fd42849c` |
| [Android arm64 Release APK](/Users/mac/src/openmuse-io/Muse-Client/dist/OpenMuse-spreadsheet-0.1.10-android-arm64.apk) | `d1bbe65373c6b37511e7c8bc1cf339db5859f1fa103026783193f5b1ad32b251` |
| [签名产品包](/Users/mac/src/openmuse-io/Muse-Plugin-Ecosystem/plugins/spreadsheet-product/dist/spreadsheet-0.1.10.mcpb) | `7eafbcae4a12820ffcdac4afb0e92e10de9a753ed7423565c58ef0931d3e5d0b` |

## 未验收项

目前仍不是 GenOffice 1:1。需要拿到同一复杂 XLSX、同视口与同缩放的 GenOffice 截图，对齐 Ribbon、公式栏、网格、底栏与对象样式。对象层还缺七个方向的缩放、跨可变行列尺寸移动、旋转、RTL、拖动时滚动、层级调整和复杂图片/形状的保存保真门禁。单个当前工作表的对象预览数量预算仍需改为可视范围查询。
