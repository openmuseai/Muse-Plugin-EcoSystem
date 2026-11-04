# Spreadsheet 产品壳第九轮：工作簿图表视觉层

## 实现与边界

本轮继续对照 GenOffice `apps/sheets/src/renderer/WorkbookVisuals.tsx` 的工作簿浮动对象层。GridCraft 桥接 `0.1.4` 从当前工作表读取图表锚点、类型和标题，调用 `gridcraft-chart` 解析数据并生成绘制指令，随局部网格快照返回。Flutter 通用表面 `0.1.7` 用独立 `WorkbookVisualLayer` 在可滚动网格上方绘制这些指令；横纵滚动时对象跟随单元格锚点，点选图表后显示“图表设计”上下文 Ribbon。图表数据、位置和保存语义仍由唯一的 GridCraft 工作簿持有，UI 只维护临时选中状态。

签名产品包 `0.1.8` 为“插入→图表”九宫格和两级菜单声明图表类型参数；通用表面负责按命令 ID 派发，不内置按钮的图表种类。资源校验器约束控件参数类型与大小。首轮图表对象快照限制为当前工作表前 16 个图表、每图 1500 条绘制指令；超过预算的图表显示标题占位，快照带 `visualsOmitted`。这属于传输保护，仍需设计分页/可视对象查询才能完整覆盖大型工作簿。

## 视觉对照证据

GenOffice 参考图为 2750×1706，OpenMuse 桌面截图为 1365×860，接近 2 倍像素密度。参考图与本轮 [图表测试工作簿](evidence/round-9/chart-roundtrip.xlsx) 的内容不同，因此这里只对照壳的布局和图表浮层行为，**不宣称整页像素一致或同工作簿保真**。

| GenOffice 参考 | OpenMuse 第九轮 |
| --- | --- |
| ![GenOffice 顶部 Ribbon、图表编辑区与底部状态栏](evidence/round-9/genoffice-reference.png) | ![OpenMuse 同类壳布局与真实 XLSX 图表](evidence/round-9/desktop-chart.png) |

| 对照项 | 本轮证据 | 结果与差异 |
| --- | --- | --- |
| 顶部 Ribbon | [开始](evidence/round-9/desktop-home.png)、[插入](evidence/round-9/desktop-insert.png)、[图表二级菜单](evidence/round-9/desktop-chart-submenu.png) | 7 个常驻和 4 个上下文标签、55 组、183 个控件、66 棵菜单继续由签名资源组织；图表类型参数已可派发。图标、组宽、文字间距和部分高级命令仍与参考有差异。 |
| 中间编辑区 | [图表浮层](evidence/round-9/desktop-chart.png)、[点选图表](evidence/round-9/desktop-chart-context.png) | 真实 XLSX 单元格和图表同时可见；锚点与滚动关联，白色图表画布、边框和阴影可见，点选后出现“图表设计”。图表绘制采用 GridCraft 色板与布局，尚未与 GenOffice 的图表逐像素对齐。 |
| 底部状态栏 | [完整桌面视图](evidence/round-9/desktop-chart.png) | 工作表标签、状态文本、视图按钮、缩放条保留；参考图的图标细节、间距和当前工作簿内容不同。 |
| 响应式与实际安装 | [手机组件](evidence/round-9/mobile-view.png)、[平板组件](evidence/round-9/tablet-view.png)、[Android 模拟器启动](evidence/round-9/android-launch.png) | 同一 Flutter 表面在窄宽度可渲染；APK 在模拟器安装启动。模拟器截图是应用首页，手机组件截图是 Spreadsheet 壳；本轮尚无模拟器内打开图表工作簿的截图。 |

## 数据和构建验证

真实 `spreadsheet-shell.xlsx` 插入柱形图后，快照返回非空绘制指令；导出 XLSX、独立 GridCraft 会话重开后，图表与绘制指令仍存在。[往返工作簿](evidence/round-9/chart-roundtrip.xlsx) 可直接供人工打开。Host 四项 Flutter 端到端测试通过，覆盖验签/篡改拒绝、单元格编辑与导出、图表往返和上下文 Ribbon、表格上下文、自动保存；图表二级菜单展开也在测试与截图中验证。`cargo check`、`flutter analyze`、产品生成/校验均通过。

`spreadsheet-product-e2e.sh android` 和 `spreadsheet-product-e2e.sh macos` 分别完整通过。macOS 构建在其他任务占用共享 Xcode `build.db` 时重试一次，最终 `codesign --verify --deep --strict`、ZIP 完整性、APK 签名与双端内嵌 MCPB 哈希校验通过。Android APK 在 `emulator-5554` 安装并启动，进程保持运行；图表往返工作簿已放入该模拟器 `/sdcard/Download/OpenMuse-chart-roundtrip.xlsx` 供手动打开。详见 [macOS 构建报告](evidence/round-9/build-report-macos.json)和 [Android 构建报告](evidence/round-9/build-report-android.json)。本地开发密钥签名，供人工验证。

| 人工验证产物 | SHA-256 |
| --- | --- |
| [macOS Release ZIP](/Users/mac/src/openmuse-io/Muse-Client/dist/OpenMuse-spreadsheet-0.1.8-macos.zip) | `fdcedd7d2c9f09bf1a4bec0fc1c739768ff446f1f9ab174cdbdb58e6264a8266` |
| [Android arm64 Release APK](/Users/mac/src/openmuse-io/Muse-Client/dist/OpenMuse-spreadsheet-0.1.8-android-arm64.apk) | `f41061e05fb5552a60065a64bc6f9a822bdc8928f05951634d1595963625c33e` |
| [签名 Spreadsheet 产品包](/Users/mac/src/openmuse-io/Muse-Plugin-Ecosystem/plugins/spreadsheet-product/dist/spreadsheet-0.1.8.mcpb) | `077617597dc6564660d79b7837c8f781c73ab96abbb22486ce967a282b5ea344` |

## 后续差距

当前尚未达到 GenOffice 1:1：图表以 GridCraft 布局绘制，图片和形状未进入 Flutter 对象层；坐标轴文字宽度使用近似测量，虚线绘制和对象拖拽/缩放未接入；多图表快照仍有数量预算。下一轮用同一复杂 XLSX 在等视口对照 GenOffice/OpenMuse，补图片和形状快照及保存保真门禁，再逐项修正 Ribbon 图标、组间距和底栏细节。
