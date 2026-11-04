# Spreadsheet 壳第三轮：可视网格、上下文标签与状态栏（2026-10-23）

## 本轮实现

继续核对 GenOffice Sheets 的 `ExcelShell.tsx` 顶部 `visibleTabs`、`HomeRibbon`、底部 `status-bar`，以及 GridCraft 的 `display::stats`、工作表表格模型。本轮没有移动文档模型：Rust GridCraft 桥接 `0.1.1` 仍是 Host 随包的唯一工作簿会话；Flutter `spreadsheet_editor` `0.1.1` 仍是共用编辑表面；市场可热安装的签名产品资源包升至 `0.1.2`，仍声明引擎 ABI 1、表面主版本 1。

- 编辑区以懒构建的行列视口替换前 100 行×32 列的预建网格。行和列可滚动到 XLSX 上限，桥接层每次只取附近最多 120 行×40 列；可见格子继续由 Flutter 表面绘制和点击编辑。
- Rust 快照增加选区范围、选区统计和表格上下文。Flutter 画出多格选区的填色和外边界；状态栏显示多格选择的计数与求和；进入表格区域时显示插件资源中的「表格设计」标签，离开时回到常驻标签。
- 带命令及菜单的 Ribbon 控件区分主按钮和箭头菜单。菜单树仍由签名包定义，Flutter 只负责通用的拆分点击与递归浮层。

## 视觉对比证据

| 区域 | GenOffice / 上轮 | 本轮 | 结论 |
| --- | --- | --- | --- |
| 整体壳 | [GenOffice 参考](evidence/round-3/genoffice-reference.png)、[第二轮开始页](evidence/round-2/desktop-home.png) | [第三轮开始页](evidence/round-3/desktop-home.png) | 35px 标签带、80px Ribbon、公式栏、网格、表签和状态栏层次保持；插件定义的开始页混排仍在。参考和测试工作簿、屏幕尺寸不同，不能据此宣布像素级一致。 |
| 多格选区与底部统计 | [第二轮桌面](evidence/round-2/desktop-home.png) | [A1:D2 选区](evidence/round-3/desktop-selection-stats.png) | 整体选区、活动格、状态栏「计数 8 / 求和 534」同屏可见；统计来自 GridCraft，而不是 UI 估算。 |
| 离屏编辑 | 第二轮仅前 100 行×32 列快照 | [手机第 501 行 A501](evidence/round-3/mobile-row-501.png)、[第 501 行 CV501](evidence/round-3/mobile-row-501-col-CV.png) | 垂直与水平滚动后均请求新窗口快照；公式栏输入的值在远处单元格渲染出来。 |
| 上下文 Ribbon | 第二轮资源里有 4 个上下文标签但全部隐藏 | [表格设计](evidence/round-3/desktop-table-context.png) | 真实 XLSX 表格区域选中后展示并切换「表格设计」；图表、图片、形状选中仍缺对象选择层。 |
| 多级菜单与响应式 | [第二轮菜单](evidence/round-2/desktop-border-submenu.png) | [第三轮边框菜单](evidence/round-3/desktop-border-submenu.png)、[平板](evidence/round-3/tablet-view.png)、[折叠](evidence/round-3/foldable-view.png)、[手机](evidence/round-3/mobile-view.png) | 多级菜单仍可达；桌面混排、窄屏横滚保持同一份 Flutter 源码。 |

截图使用真实 XLSX 样本，但 GenOffice 参考图是含图表的另一文档。本轮测试不能证明图表/对象层保真，也没有把尚不支持的内容伪装成渲染结果。

## 验证和交付

- [机器可读报告](evidence/round-3/build-report.json)含产品、Rust 库、Host、APK 和 XLSX 样本的 SHA-256。产品包 SHA-256 为 `6118caad85a427bb43d2bc2718fa3c9950aa922bb885b048492f155dfa5cd74b`；macOS 包和 APK 内嵌的资源哈希相同，身份均为 `0.1.2`。
- 产品资源校验及 Ed25519 打包/验签通过：11 标签、55 组、157 控件、62 棵菜单。篡改包加载被拒绝。
- `flutter test test/spreadsheet_product_e2e_test.dart` 两项通过：真实 XLSX 公式值、改值、导出重开、嵌套菜单、A1:D2 聚合、A501 与 CV501 的离屏编辑渲染，以及表格上下文标签。
- macOS Release `OpenMuse.app` 和 ZIP 完成，`codesign --verify --deep --strict` 通过；DSH closure 的无密钥运行检查通过。
- Android arm64 Release APK 完成，内含 Rust `.so` 与签名资源包，`apksigner verify` 的 v2/v3 检查通过。本轮没有在当前连接的实体手机上安装或启动 APK；截图中的手机宽度画面来自 Host Flutter 组件测试。

一键重建：`bash Muse-Client/scripts/spreadsheet-product-e2e.sh all`。脚本为每次运行创建带时间戳的独立证据目录。此产物使用本地开发签名证书，仅供人工验证。

## 下一轮优先项及验收差距

1. 中间内容区仍缺图表、图片、形状对象层，以及合并单元格、冻结窗格、可变行高列宽、原位 IME 和完整键鼠/触控选区。当前可见窗口懒加载解决了远处行列的可达性，尚未完成性能基线和大表格连续滚动帧率门禁。
2. 「插入、页面布局、公式、数据、审阅、视图」及上下文 Ribbon 目前有全部资源入口，但尚未逐项达到 GenOffice 的控件尺寸、组合、选中回显和弹窗形态。图表/图片/形状上下文标签需对象选择模型驱动。
3. 底部统计只接入计数与求和；视图模式及缩放百分比的实际网格几何、菜单自定义统计仍待实现。字体、数字字段也需读取选中单元格实际格式并绑定命令参数。

第三轮仍是持续迭代版本，**未达到整套 GenOffice 壳的一比一验收**。下一轮按同尺寸、同工作簿分别拍摄 GenOffice 和 OpenMuse，以控件位置和对象绘制结果逐项关闭差异。
