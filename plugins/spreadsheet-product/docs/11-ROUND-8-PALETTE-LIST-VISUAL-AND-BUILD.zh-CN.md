# Spreadsheet 产品壳第八轮：平铺色盘与工作表移动列表

## 源码与领域边界

继续对照 GenOffice `apps/sheets/src/renderer/SheetTabContextMenu.tsx`、`packages/ui/src/color-picker.tsx`、`color-picker.css` 和 `styles.css`。签名产品包 `0.1.7` 声明色盘标题、10 列主题基色、5×10 色阶、10 列标准色及清除/更多颜色入口；资源校验器检查色值与行列形状。Flutter 表面 `0.1.6` 解释该声明，绘制平铺色块并将所选 `#RRGGBB` 发送给 `sheet.tabColor`，选色后关闭整个标签菜单。旧产品包无该声明时仍按旧级联菜单呈现。色盘和对话框只维护展示/临时选择状态，标签颜色和工作表顺序仍由唯一的 Rust 工作簿会话持有。

移动或复制的目标由下拉框改为可滚动常驻列表，保留“移到最后”和“建立副本”。目标索引换算和 `sheet.move` 命令语义不变。顶部多级 Ribbon、公式栏、中央可视网格、工作表栏和底部 24px 状态栏沿用签名资源控制的布局；本轮复核的桌面高度为标签 35、Ribbon 80、公式栏 40、状态栏 24 逻辑像素。

## 逐轮视觉证据

参考截图为 2750×1706，OpenMuse 截图为 1365×860，约为 2 倍像素密度；工作簿内容不同，以下用于核对壳层结构和控件，不作为像素一致率。调色盘的具体布局另以 GenOffice `color-picker.css` 的 260px 面板、20px 色块、4px 间隙及 10 列栅格对照。Flutter 色盘外宽 262 逻辑像素，色块保持 20px、间隙 4px。

| GenOffice 参考 | OpenMuse 第八轮开始页 |
| --- | --- |
| ![GenOffice Sheets](evidence/round-8/genoffice-reference.png) | ![OpenMuse Spreadsheet](evidence/round-8/desktop-home.png) |

| 对照点 | 上轮 | 本轮证据与结论 |
| --- | --- | --- |
| 工作表标签色 | [三级文字菜单](evidence/round-7/desktop-sheet-color-palette.png) | [平铺色盘](evidence/round-8/desktop-sheet-color-palette.png)：完整主题色、五层明暗色和标准色可见；[红色标签](evidence/round-8/desktop-sheet-colored.png) 经命令回显。GenOffice 的原生颜色选择器与我们的十六进制输入框仍不同。 |
| 移动或复制 | [下拉目标](evidence/round-7/desktop-sheet-move-dialog.png) | [常驻目标列表](evidence/round-8/desktop-sheet-move-dialog.png)、[复制后](evidence/round-8/desktop-sheet-copied.png)、[换序后](evidence/round-8/desktop-sheet-moved.png)。GenOffice 的对话框边距/按钮外形仍有差异。 |
| 顶部与底部壳 | [GenOffice 参考](evidence/round-8/genoffice-reference.png) | [开始页](evidence/round-8/desktop-home.png)、[插入页](evidence/round-8/desktop-insert.png)、[状态菜单](evidence/round-8/desktop-status-menu.png)：11 标签、55 组、183 控件、66 棵菜单继续可达。 |
| 响应式与 APK | 上轮手机/平板组件截图 | [手机](evidence/round-8/mobile-view.png)、[平板](evidence/round-8/tablet-view.png)、[折叠宽度](evidence/round-8/foldable-view.png) 均由同一 Flutter 表面生成；[Android 模拟器启动](evidence/round-8/android-launch.png) 验证 APK 可安装启动。手机截图为 Flutter Host 组件测试，非本轮模拟器内打开 XLSX 的截图。 |

## 验证与人工安装包

`npm run generate && npm run validate`、`flutter analyze`、3 项 Host Flutter 端到端测试通过。真实 XLSX 测试覆盖签名包验签与篡改拒绝、编辑导出回读、工作表复制/移动/标签颜色往返、Ribbon/状态栏/多宽度截图。macOS Release 应用及 Android arm64 Release APK 已构建；应用严格签名、ZIP 完整性、APK 签名、两个安装包内的签名 MCPB 哈希一致性均单独复验通过。APK 另在 `emulator-5554` 安装和启动成功。构建详情见 [报告](evidence/round-8/build-report.json)。

| 供人工验证的产物 | SHA-256 |
| --- | --- |
| [macOS Release ZIP](/Users/mac/src/openmuse-io/Muse-Client/dist/OpenMuse-spreadsheet-0.1.7-macos.zip) | `bcbdef00a4201ada045e4d78b23b3e80b00eb9a429a112705e70beded5eb6c1f` |
| [Android arm64 APK](/Users/mac/src/openmuse-io/Muse-Client/dist/OpenMuse-spreadsheet-0.1.7-android-arm64.apk) | `1b9e2b71d09212511c0a407b18f96d77929518de87aafa3a84da63fa094fb7fb` |
| [签名产品包](/Users/mac/src/openmuse-io/Muse-Plugin-Ecosystem/plugins/spreadsheet-product/dist/spreadsheet-0.1.7.mcpb) | `3820e9a1c2279e9bf0f59d92e019dd506dcd1e56049745b7614b052970266004` |

最终 `bash Muse-Client/scripts/spreadsheet-product-e2e.sh all` 完整通过。此前一次共享输出目录并发写入导致 macOS 签名检查失败，完整重跑后未复现。构建使用本地开发签名，供人工验证。

当前仍不是 GenOffice 1:1 完成版：复杂工作簿中的图表/对象层、部分 Ribbon 高级命令、工作表分组选择和保护尚未实现；参考截图与测试工作簿不同，不能宣称整页像素一致。下一轮应对同一复杂工作簿做等视口对照，优先实现图表/对象快照与保真写回门禁，并继续调整 Ribbon 控件图标和组间距。
