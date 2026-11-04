# Spreadsheet 产品壳第十九轮：弹窗遮罩与双位置状态消息

## 实现与边界

对照 GenOffice `apps/sheets/src/renderer/styles.css` 的 `.dialog-backdrop` 和 `ExcelShell.tsx` 的 `statusMessage`：遮罩是 50% 深色并对背景施加 4px 模糊；同一状态消息显示在顶部 Ribbon 右侧及底部状态栏。签名产品包 `0.1.18` 声明 `dialogBackdropBlur`、`dialogBackdropOpacity`、遮罩颜色和工作簿状态文案。Flutter 通用表面 `0.1.16` 根据工作簿快照的 `dirty`、对象预览及行几何状态生成一条消息，并在顶部与底部共用；弹窗使用模糊背景层和独立对话框层。旧签名资源缺少新字段时仍有兼容默认值。

GenOffice 实机的“公式实时重算”属于其运行时能力；OpenMuse 当前只显示“工作簿已加载，行列可编辑。”，避免向用户承诺尚未核实的计算行为。文件名继续由 Host 标签承载，在 Flutter 表面顶部作为状态消息的提示保留。Ribbon、菜单、底栏的文案和遮罩参数来自产品插件；工作簿状态仍由 GridCraft 引擎提供，Host 只验签、装载和路由。

## 同工作簿视觉对比

以下图片的工作簿均为 `spreadsheet-geometry.xlsx`，SHA-256 `1fc6494d21318665ee225486dcfa749b2125ee6cd92cb1d0828d458f2144591a`。GenOffice 0.11.919 实机截图为 2720×1770 物理像素，OpenMuse Flutter 测试截图为 1365×860 逻辑像素；GenOffice 包含原生标签栏，按约 2:1 对照内容区，不宣称逐像素通过。旧弹窗截图取自第十七轮，当时列宽尚未修正；同工作簿的壳改前截图取自第十八轮。

| 场景 | GenOffice 实机 | OpenMuse 改前 | OpenMuse 本轮 |
| --- | --- | --- | --- |
| 顶部 Ribbon、编辑区、底栏 | ![GenOffice 壳](evidence/round-19/genoffice-same-workbook.png) | ![OpenMuse 改前壳](evidence/round-19/openmuse-before-shell.png) | ![OpenMuse 本轮壳](evidence/round-19/openmuse-after-shell.png) |
| 定位弹窗 | ![GenOffice 定位](evidence/round-19/genoffice-go-to-dialog.png) | ![OpenMuse 改前定位](evidence/round-19/openmuse-before-dialog.png) | ![OpenMuse 本轮定位](evidence/round-19/openmuse-after-dialog.png) |

本轮弹窗后方的 Ribbon、公式栏、网格与状态栏均被模糊；弹窗内容保持清晰，点击遮罩或 Esc 仍可关闭。顶部与底部改为共用产品声明的工作簿状态消息。[Ribbon 二级菜单](evidence/round-19/openmuse-ribbon-submenu.png)、[底栏统计菜单](evidence/round-19/openmuse-status-menu.png)及[手机宽度](evidence/round-19/openmuse-mobile.png)保留为跨区域回归截图。

尚有可见差异：GenOffice 的原生标签栏和若干图标、文案密度与 OpenMuse 不同；名称框定位仍只支持单元格及矩形区域，更多 Ribbon 控件尚未接通。当前整个壳仍不能标记为 1:1 完成。

## 验证与人工安装包

产品资源生成、Schema 校验、Ed25519 开发密钥签名与验签通过；Flutter 表面静态分析和 8 项测试、Host 6 项真实 XLSX 端到端测试通过。Host 测试验证双位置状态消息、模糊遮罩、定位到 Z100、编辑保存重开、对象、Ribbon 二级菜单和底栏统计菜单。macOS Release 通过 `codesign --verify --deep --strict`，Android arm64 APK 通过 `apksigner verify`；ZIP 与 APK 内嵌的产品包 SHA-256 均与独立签名包一致。[构建报告](evidence/round-19/build-report-all.json)记录了源码、测试工作簿、54 张截图及产物哈希。APK 使用本地调试签名，仅供人工验证。

本轮 `adb` 只检测到一台物理设备，原有 `emulator-5556` 未运行，因此没有安装或执行模拟器内人工操作；交付 APK 供用户自行安装验证。

| 产物 | SHA-256 |
| --- | --- |
| [macOS Release ZIP](/Users/mac/src/openmuse-io/Muse-Client/dist/OpenMuse-spreadsheet-0.1.18-macos.zip) | `5de057d7fe993939c27f3718ec35a75c8744617d781eabe07ee43443a0323516` |
| [Android arm64 Release APK](/Users/mac/src/openmuse-io/Muse-Client/dist/OpenMuse-spreadsheet-0.1.18-android-arm64.apk) | `e58ae0cda6cfc4e26a552ec9555b6da816baef4ec11897e112c9d26bfa0074c3` |
| [签名产品包](/Users/mac/src/openmuse-io/Muse-Plugin-Ecosystem/plugins/spreadsheet-product/dist/spreadsheet-0.1.18.mcpb) | `736b602508f2495e1f817496d93a70a7cb3f4008f94007fe9fdefccf4c642300` |
