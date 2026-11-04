# Spreadsheet 产品壳第十五轮：缩放对话框与编辑区实际缩放

## 源码核对与插件边界

本轮核对 GenOffice `apps/sheets/src/renderer/ZoomDialog.tsx`、`zoom-range.ts`、中文对话框文案和 `styles.css`：点击底栏百分比打开深色对话框，选项依次为 200%、100%、75%、50%、25%、恰好容纳选定区域、自定义；自定义值限 10–400%，越界显示错误。其顶部 Ribbon、编辑区和底栏仍以 `ExcelShell.tsx` 及既有参考截图为整体对照。

签名产品资源 `0.1.14` 新增 `chrome.zoomDialog` 的文案、预设、范围、命令 ID 和按钮颜色；生成器和校验器验证声明及对应命令。Flutter 通用表面 `0.1.13` 的独立对话框组件只消费该声明，调用工作簿命令，不持有缩放业务状态。GridCraft 桥接 `0.1.6` 继续是工作簿尺寸与缩放状态的来源，并在快照增加当前选区尺寸。Host 仍负责验签、装载和交付；签名包不嵌入 Flutter 或 Rust 实现。这保持 Everything is plugin 的可替换合同与关注点分离。

原先底栏数值变化后网格和对象仍按 100% 绘制。本轮让行列、文本、图表、形状、图片与对象手柄按同一缩放比例布局，窗口快照范围随视口调整。适配选区仍通过插件声明的 `view.zoomToSelection` 命令执行；表面依据桥接返回的工作簿选区尺寸与当前固定格子显示尺寸换算视口参数，避免选区被右侧裁掉。

## 视觉对比证据

| GenOffice 整体参考 | 第十四轮 OpenMuse | 第十五轮 OpenMuse |
| --- | --- | --- |
| ![GenOffice 顶部 Ribbon、编辑区、底栏](evidence/round-15/genoffice-reference.png) | ![旧版同一测试工作簿](evidence/round-15/desktop-home-before.png) | ![新版同一测试工作簿](evidence/round-15/desktop-home.png) |

| 本轮入口与状态 | 视觉证据及核对点 |
| --- | --- |
| 底栏百分比打开弹窗 | [缩放对话框](evidence/round-15/desktop-zoom-dialog.png)：七项选择、深色边框、右下按钮与 GenOffice 源码结构对应。GenOffice 弹窗的实机截图尚未取得，本项属于源码结构对照。 |
| 预设与校验 | [75% 编辑区](evidence/round-15/desktop-zoom-75.png)可见更多行列，底栏显示 75%；[999 越界错误](evidence/round-15/desktop-zoom-range-error.png)阻止提交。 |
| 适配选区 | [A1:D2 适配选区](evidence/round-15/desktop-zoom-fit-selection.png)约 308%，四列全部落入视口；测试同时断言 D1 标题在右边界以内。 |
| 浮动对象 | [75% 图表、形状、图片](evidence/round-15/desktop-objects-zoom-75.png)随网格一同缩放；Host 测试量测形状宽度为原来的 0.75。 |
| 整体壳回归 | [插入 Ribbon](evidence/round-15/desktop-insert.png)、[状态统计菜单](evidence/round-15/desktop-status-menu.png)、[手机宽度](evidence/round-15/mobile-view.png)、[平板宽度](evidence/round-15/tablet-view.png)。 |

GenOffice 参考与 OpenMuse 使用不同工作簿，参考截图的视口也不同。本轮可证明入口结构、交互与同一 OpenMuse 工作簿的缩放前后变化；不能据此宣称同工作簿逐像素 1:1 完成。

## 验证与人工产物

产品包生成、Schema 校验、Ed25519 开发密钥签名与验签通过。四项几何测试和五项 Host 端到端测试通过，覆盖缩放预设、范围错误、适配选区、对象几何及既有真实 XLSX 往返。联合流水线的机器报告记录源码、截图和产物 SHA-256。macOS 和 Android 均为本地人工验证构建；Android Release APK 使用本地调试密钥签名。

| 人工验证产物 | SHA-256 |
| --- | --- |
| [macOS Release ZIP](/Users/mac/src/openmuse-io/Muse-Client/dist/OpenMuse-spreadsheet-0.1.14-macos.zip) | `f41ce9ab7f7b67ce8e537e2c24b56354166c3f33c2c77d1c984efb9c5baae489` |
| [Android arm64 Release APK](/Users/mac/src/openmuse-io/Muse-Client/dist/OpenMuse-spreadsheet-0.1.14-android-arm64.apk) | `4ed7b66dfce1fa1245d6ff8d78b95c154526b7f9d5dc02240bc03f4e11410f79` |
| [签名产品包](/Users/mac/src/openmuse-io/Muse-Plugin-Ecosystem/plugins/spreadsheet-product/dist/spreadsheet-0.1.14.mcpb) | `92d57292130f6241c3fadc0b275c86cd051fd846cb10a152e53f38fda381d892` |
| [联合构建报告](evidence/round-15/build-report-all.json) | 包含签名包、原生库、macOS ZIP、Android APK 哈希 |

## 后续差距

编辑区仍以固定行高和列宽绘制，尚未从工作簿逐行逐列取得可变尺寸；冻结、RTL、旋转对象和复杂图表保真也未完成。下一轮应先补工作簿行列尺寸在桥接和 Flutter 表面的同源几何模型，再用同一 XLSX、相同视口、相同缩放的 GenOffice 实机截图做逐像素差异报告。
