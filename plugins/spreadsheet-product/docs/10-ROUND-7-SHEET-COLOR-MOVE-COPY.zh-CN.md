# Spreadsheet 产品壳第七轮：工作表颜色、移动与复制

## 源码对照与实现

本轮继续逐项对照 GenOffice Sheets 的 `apps/sheets/src/renderer/SheetTabContextMenu.tsx`、`sheet-tab-actions.ts` 和 `styles.css`。GenOffice 通过工作表上下文菜单提供“移动或复制”和标签颜色，结构变化进入工作簿命令。OpenMuse 的签名产品包 `0.1.6` 将主题色、标准色和自定义色入口声明为带参数的菜单节点；通用 Flutter 表面 `0.1.5` 解释菜单、显示深色对话框与标签颜色；固定的 GridCraft Rust 桥接 `0.1.3` 提供 `sheet.move`、`sheet.tabColor`、`sheetStates.tabColor`。产品包仍不包含网格绘制、逐格编辑或工作簿数据。

工作表移动会换序；勾选“建立副本”会复制工作表并生成独立标签。标准色在标签底边可见，“无颜色”清除颜色，“更多颜色”接受 `#RRGGBB` 输入。命令参数随签名资源发布，资源校验器检查菜单参数结构；Flutter 仅通过版本化引擎接口发命令。GridCraft 导出 XLSX 后重开，工作表顺序、复制件和标签颜色均保留。顶端多级 Ribbon、公式栏、中央可视网格及底栏沿用上轮布局。

## 逐轮视觉对比

GenOffice 参考图与 OpenMuse 测试工作簿内容不同；以下截图比较壳层与交互可达性，不代表像素级一致。

| GenOffice 参考壳 | OpenMuse 第七轮壳 |
| --- | --- |
| ![GenOffice Sheets](evidence/round-7/genoffice-reference.png) | ![OpenMuse Spreadsheet](evidence/round-7/desktop-home.png) |

| 对照点 | GenOffice 源码或上轮 | 第七轮证据 | 结论与差异 |
| --- | --- | --- | --- |
| 多级 Ribbon、公式栏、编辑网格和底栏 | `ExcelShell.tsx`；[第六轮开始页](evidence/round-6/desktop-home.png) | [桌面开始页](evidence/round-7/desktop-home.png)、[手机](evidence/round-7/mobile-view.png)、[平板](evidence/round-7/tablet-view.png)、[折叠屏](evidence/round-7/foldable-view.png) | 11 个标签、55 个组、183 个控件、66 棵菜单保持可达；图表对象层和部分菜单动作仍未完成。 |
| 工作表标签颜色 | `SheetTabContextMenu.tsx` 中的 `ColorPicker` 与 `setTabColor` | [三级色彩菜单](evidence/round-7/desktop-sheet-color-palette.png)、[红色标签](evidence/round-7/desktop-sheet-colored.png) | 主题/标准色、自定义十六进制色和清除颜色可执行；当前菜单以文字色块级联呈现，尚未还原 GenOffice 的平铺调色盘。 |
| 移动或复制 | `MoveCopySheetDialog` 和 `sheet-tab-actions.ts` 中的命令 | [深色对话框](evidence/round-7/desktop-sheet-move-dialog.png)、[复制后](evidence/round-7/desktop-sheet-copied.png)、[重排后](evidence/round-7/desktop-sheet-moved.png) | 复制得到 `Sheet1 (2)`，移动后顺序变为 `Sheet1 / Forecast / Sheet1 (2)`；GenOffice 使用常驻列表，此版使用下拉选择，仍有外观差异。 |
| Android Host 实际路径 | [第六轮 Android 打开 XLSX](evidence/round-6/android-xlsx.png) | [打开 XLSX](evidence/round-7/android-xlsx.png)、[长按菜单](evidence/round-7/android-sheet-menu.png)、[移动或复制对话框](evidence/round-7/android-move-dialog.png)、[复制后](evidence/round-7/android-copied.png)、[三级色彩菜单](evidence/round-7/android-color-palette.png)、[着色后](evidence/round-7/android-colored.png) | arm64 模拟器安装本轮 APK，经 OpenMuse 文件选择器打开真实 XLSX，复制工作表并将原标签设为红色。 |

## 构建与验证

在同一工作区运行 `bash Muse-Client/scripts/spreadsheet-product-e2e.sh all`，完成产品资源生成、校验与签名，Rust 桥接编译、3 项 Flutter Host 端到端测试、macOS Release 与 Android arm64 Release 构建。测试覆盖签名/篡改拒绝、XLSX 编辑导出回读、工作表颜色与移动复制的 XLSX 往返、Ribbon/状态栏/响应式截图。macOS App 严格签名验证、ZIP 完整性和 APK 签名验证通过；两个安装包内的签名产品包 SHA-256 一致。详情见 [构建报告](evidence/round-7/build-report.json)。

| 供人工验证的产物 | SHA-256 |
| --- | --- |
| [macOS Release ZIP](/Users/mac/src/openmuse-io/Muse-Client/dist/OpenMuse-spreadsheet-0.1.6-macos.zip) | `814409bbad22d5fc28009f4c0a9046e05b4923482d196f9d2eb9d9aaca8290d1` |
| [Android arm64 APK](/Users/mac/src/openmuse-io/Muse-Client/dist/OpenMuse-spreadsheet-0.1.6-android-arm64.apk) | `4f87c2d8f8d5d0bb3618b9937280e09e4468785542c4d17758e3a80574b318d0` |
| [签名产品包](/Users/mac/src/openmuse-io/Muse-Plugin-Ecosystem/plugins/spreadsheet-product/dist/spreadsheet-0.1.6.mcpb) | `cbc977911784ce9d4636a70cb1044fa920e054c668446749b068d64bcabb231d` |

构建使用本地开发签名，产物供人工验证。macOS 真实窗口仍需人工逐项验收；Flutter Host 端到端测试已覆盖编辑面流程。下一轮应将调色盘改为 GenOffice 的平铺色块布局、把移动或复制下拉框改为常驻列表，并继续核对 Ribbon 控件尺寸及底栏密度。图表/对象层、工作表分组选择和保护功能仍未达到一比一。
