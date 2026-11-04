# Spreadsheet 产品壳第六轮：快捷栏、原位编辑与工作表菜单

## 源码依据与交付边界

本轮对照 GenOffice Sheets 的 `apps/sheets/src/renderer/ExcelShell.tsx` 顶部快捷栏、公式栏、状态栏，以及 `SheetTabContextMenu.tsx` 的工作表标签交互；现有 11 个一级标签、55 个组、183 个控件继续由签名资源包声明。产品包版本为 `0.1.5`，Flutter `spreadsheet_editor` 为 `0.1.4`，GridCraft Rust 桥接为 `0.1.2`。产品资源包现有 **66 棵菜单**，新增的是工作表标签菜单及其标签颜色级联菜单。

分层仍按 Everything is plugin 执行：可热安装的产品包只声明快捷操作、Ribbon 布局、命令和菜单；Flutter 编辑面在 Host 中解释资源并处理输入、焦点、画布；固定的 Rust 桥接负责工作簿状态、XLSX 读写和命令执行。`sheetStates`、`view` 由 Rust 快照提供，Flutter 没有另建工作簿模型。`ss-core` 仍未达到替换 GridCraft 的条件。

本轮可用交互：顶部保存、撤销、重做、自动保存开关；单元格双击后原位输入；工作表标签右击或长按后的插入、重命名、隐藏、取消隐藏与删除确认；底栏普通视图和分页预览状态切换。自动保存通过 Host 的保存回调落盘，850 毫秒防抖；真实 XLSX 回读测试覆盖了修改后的 `B2=126`。桥接命令成功但返回 JSON `null` 时，Flutter 现在将其视为成功并刷新快照，修复了重命名等命令执行后界面未更新的问题。

## 视觉对比证据

GenOffice 参考图为用户提供的复杂工作簿，Flutter 自动截图使用 1365×860 逻辑像素与双工作表样本；文档内容不同，因此以下证明壳层结构与交互状态，**不证明像素级一致**。

| GenOffice 参考壳 | OpenMuse 第六轮壳 |
| --- | --- |
| ![GenOffice Sheets 参考](evidence/round-6/genoffice-reference.png) | ![OpenMuse Spreadsheet 第六轮](evidence/round-6/desktop-home.png) |

| 对照 | GenOffice / 上轮 | 本轮截图 | 结论与差异 |
| --- | --- | --- | --- |
| 顶部多级 Ribbon、公式栏、中央网格、底部状态栏 | [GenOffice 参考图](evidence/round-6/genoffice-reference.png)、[第五轮开始页](evidence/round-5/desktop-home.png) | [第六轮开始页](evidence/round-6/desktop-home.png) | 四层结构保留，顶部增加独立“另存为”入口和自动保存开关；小屏以横向滚动保持命令可达。参考图的图表对象层尚未实现。 |
| Ribbon 一级与级联菜单 | GenOffice `ExcelShell.tsx` 的 Home、Insert、Page Layout、Formulas、Data、Review、View，以及对象上下文页 | [插入页](evidence/round-6/desktop-insert.png)、[边框子菜单](evidence/round-6/desktop-border-submenu.png)、[表格上下文](evidence/round-6/desktop-table-context.png) | 11 个声明标签与 66 棵菜单可显示；高级命令的部分叶子仍为禁用占位。 |
| 单元格编辑 | GenOffice 在网格原位编辑 | [原位输入状态](evidence/round-6/desktop-inline-editor.png)、[提交后网格](evidence/round-6/desktop-sheet-tab-menu.png) | 双击 B2 出现网格内输入控件，提交后数值从 125 改为 126；字体、选区与编辑光标仍需同尺寸细调。 |
| 工作表标签右键/长按 | GenOffice `SheetTabContextMenu.tsx` | [桌面菜单](evidence/round-6/desktop-sheet-tab-menu.png)、[插入后](evidence/round-6/desktop-sheet-inserted.png)、[重命名后](evidence/round-6/desktop-sheet-renamed.png)、[隐藏后](evidence/round-6/desktop-sheet-hidden.png)、[取消隐藏后](evidence/round-6/desktop-sheet-unhidden.png) | 插入、重命名、隐藏/取消隐藏由 Rust 工作簿命令驱动；标签颜色子菜单有结构但颜色动作未接入。 |
| 底栏视图 | GenOffice 底栏视图按钮与缩放 | [分页预览状态](evidence/round-6/desktop-page-break-view.png) | 视图状态由 Rust 回传，底栏高亮正确；中央网格尚无分页线绘制。 |
| 响应式 | 桌面 GenOffice 参考 | [平板](evidence/round-6/tablet-view.png)、[折叠屏](evidence/round-6/foldable-view.png)、[手机](evidence/round-6/mobile-view.png) | 保留 Ribbon、公式栏、网格、工作表标签与底栏，小屏 Ribbon 横向滚动。 |
| Android Host 实际路径 | 上轮 [Android XLSX](evidence/round-5/android-xlsx-open.png) | [本轮 XLSX](evidence/round-6/android-xlsx.png)、[长按菜单](evidence/round-6/android-sheet-menu.png)、[插入后](evidence/round-6/android-inserted.png) | arm64 模拟器安装 Release APK，经 OpenMuse 文件选择器打开 XLSX，看到 `Region/Q1/Q2/North/125/142`；长按标签并插入新工作表成功。 |

## 构建与验证

执行 `bash Muse-Client/scripts/spreadsheet-product-e2e.sh all`，完成产品资源生成/校验、桥接编译、3 项 Flutter Host 端到端测试、macOS Release 和 Android arm64 Release 构建。测试覆盖签名与篡改拒绝、XLSX 打开/编辑/导出/重开、Ribbon 与菜单、工作表结构命令、自动保存回读。macOS 签名严格校验、ZIP 完整性、APK 签名校验通过；Android 模拟器 `emulator-5556` 安装、打开 XLSX、长按菜单与插入工作表已截图。macOS 真实窗口的逐项人工点击仍留给验收。详情见 [机器可读报告](evidence/round-6/build-report.json)。

| 供人工验证的产物 | SHA-256 |
| --- | --- |
| [macOS Release ZIP](/Users/mac/src/openmuse-io/Muse-Client/dist/OpenMuse-spreadsheet-0.1.5-macos.zip) | `bea931575f8e1131867a010b7d89f3c92c8fadc5a1d70291b689aa1bd1b7f491` |
| [Android arm64 APK](/Users/mac/src/openmuse-io/Muse-Client/dist/OpenMuse-spreadsheet-0.1.5-android-arm64.apk) | `cd20248f5987ce562e98709048ff9992e04c05a00edeb355ee1914b56fea9f87` |
| [签名产品包](/Users/mac/src/openmuse-io/Muse-Plugin-Ecosystem/plugins/spreadsheet-product/dist/spreadsheet-0.1.5.mcpb) | `95adf5694d804725bdd119360649b04d46b8c44ffa573c1b06e180d0ccbe11cd` |

两个安装包内嵌的产品资源 SHA-256 都等于上表插件包哈希。使用本地开发签名，适合人工验证。

## 未完成项与下一轮

GenOffice 的移动/复制工作表、标签颜色、保护、分组选择，另存为的 Host 文件目标接口，分页线绘制，以及图表与对象层尚未接通；对应入口保持禁用或仅显示视图状态。下一轮应优先实现可验证的工作表标签颜色和移动/复制，再用同一复杂工作簿、相同逻辑尺寸对齐 Ribbon 图标、间距、弹出层定位、状态栏密度，并继续交付双端截图及版本化构建。
