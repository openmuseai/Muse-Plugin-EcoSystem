# Spreadsheet 产品壳第十七轮：名称框定位与实机视觉对照

## 实现范围和设计边界

本轮对照 GenOffice `apps/sheets/src/renderer/ExcelShell.tsx` 的名称框定位入口、`GoToDialog.tsx` 和 `styles.css` 的弹窗布局，并在已安装的 GenOffice 0.11.919 中打开同一份 `spreadsheet-geometry.xlsx` 实测。此前 OpenMuse 的名称框箭头只有图标；输入远处引用虽可改变引擎选区，网格不会滚动到目标。

签名产品包 `0.1.16` 在 `goToDialog` 声明入口文案、错误提示、颜色和 `selection.set` 命令；通用 Flutter 表面 `0.1.15` 负责对话框、A1 矩形引用的边界校验与可视区滚动。旧版签名资源不含 `goToDialog` 时仍可解析并沿用旧名称框显示，以保持包回滚兼容。工作簿选区仍由 GridCraft 引擎独占写入，Host 继续只做验签、装载和路由。Ribbon 的“查找和选择→定位”与名称框箭头共用同一产品声明入口。

定位到远处单元格时，列在可视区右端出现，目标行上方保留一行；这与 GenOffice 实机打开 `Z100` 的位置一致。支持 `A1`、`B2:D20` 和合法的绝对引用；定义名称、跨工作表引用、整行/列以及非连续区域尚未接入此对话框，输入时不会错误跳转。

## 同一工作簿视觉对比

以下图像均使用 SHA-256 `1fc6494d21318665ee225486dcfa749b2125ee6cd92cb1d0828d458f2144591a` 的测试工作簿。GenOffice 实机截图为 2720×1770 物理像素，OpenMuse Flutter 测试截图为 1365×860 逻辑像素；GenOffice 图含原生标签栏，因此只能按约 2:1 缩放进行目视对照，不能宣称逐像素通过。

| 场景 | GenOffice 0.11.919 实机 | OpenMuse 本轮 |
| --- | --- | --- |
| 顶部 Ribbon、编辑区、底栏 | ![GenOffice 同一工作簿](evidence/round-17/genoffice-same-workbook.png) | ![OpenMuse 同一工作簿](evidence/round-17/openmuse-home.png) |
| 定位对话框 | ![GenOffice 定位](evidence/round-17/genoffice-go-to-dialog.png) | ![OpenMuse 定位](evidence/round-17/openmuse-go-to-dialog.png) |
| 定位到 Z100 | ![GenOffice Z100](evidence/round-17/genoffice-go-to-result.png) | ![OpenMuse Z100](evidence/round-17/openmuse-go-to-result.png) |

OpenMuse 对话框[改前截图](evidence/round-17/openmuse-go-to-before.png)使用 400px 宽、小圆角及默认紫色焦点线；本轮按 GenOffice 实机与 CSS 校准为 420px、16px 圆角、蓝色焦点线、150px 内容区和小号双按钮。顶部[边框二级菜单](evidence/round-17/openmuse-border-submenu.png)、底部[状态菜单](evidence/round-17/openmuse-status-menu.png)与[手机宽度](evidence/round-17/openmuse-mobile-view.png)亦在本轮回归截图中保留。

仍可见的差异：GenOffice 弹窗遮罩有背景模糊，OpenMuse 目前只有遮罩；GenOffice 按 Normal 字体计算默认列宽，OpenMuse 当前工作簿 B/C/D 自定义列宽正确，但无显式默认列宽的列仍偏窄；应用原生标签栏和状态文案由不同容器提供。当前不能标记为整个壳的 1:1 完成。

## 验证与人工安装包

产品资源生成、Schema 校验、Ed25519 开发密钥签名与验签通过。通用表面静态分析和八项几何／引用／旧包兼容测试通过；Host 六项真实 XLSX 端到端测试通过，覆盖无效引用留在对话框、Z100 命令选区与可视位置、编辑保存重开、对象、Ribbon 与状态栏回归。macOS Release 签名验证和 Android arm64 APK 内嵌产品包哈希验证见构建报告。Android APK 使用本地调试签名，仅供人工验证。

APK 已通过 `adb install -r` 安装到 `emulator-5556`，包管理器返回 `Success`；本轮没有把模拟器内人工打开定位对话框记为已完成测试。macOS ZIP 与 Android APK 内嵌 `spreadsheet.mcpb` 的 SHA-256 均与独立签名产品包一致。

| 产物 | SHA-256 |
| --- | --- |
| [macOS Release ZIP](/Users/mac/src/openmuse-io/Muse-Client/dist/OpenMuse-spreadsheet-0.1.16-macos.zip) | `0ad5a9cc5f3069cb2533718fde3965f0be606e780414f452f5917f988fa8a94a` |
| [Android arm64 Release APK](/Users/mac/src/openmuse-io/Muse-Client/dist/OpenMuse-spreadsheet-0.1.16-android-arm64.apk) | `fc87153b049e446cf4d62aa2e0473c5307889fc7bc30d026c3c549b174e899e1` |
| [签名产品包](/Users/mac/src/openmuse-io/Muse-Plugin-Ecosystem/plugins/spreadsheet-product/dist/spreadsheet-0.1.16.mcpb) | `1d1168db3c5fe8f09211ad6e3d2e8e68baef172f4568d431934c3fdbe267d338` |
| [构建报告](evidence/round-17/build-report-all.json) | 含源码、原生库、测试工作簿、54 张截图和以上产物的哈希 |

下一轮继续按同一 XLSX 对照默认列宽、字体度量、遮罩和完整壳细节，并逐项接通仍被禁用的 Ribbon 控件；冻结窗格、RTL、复杂对象保真仍按开发计划推进。
