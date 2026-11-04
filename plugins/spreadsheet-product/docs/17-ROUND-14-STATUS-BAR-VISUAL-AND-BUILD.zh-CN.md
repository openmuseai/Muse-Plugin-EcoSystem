# Spreadsheet 产品壳第十四轮：底部状态栏

## GenOffice 源码与插件边界

核对 GenOffice `apps/sheets/src/renderer/ExcelShell.tsx` 的 `<footer className="status-bar">`、视图单选组和缩放控件，以及 `styles.css` 的 `.status-bar`、`.view-switch`、`.view-btn`、`.zoom-slider`。参考深色状态栏为 24px 高、`#252525` 背景、`#3a3a3a` 顶部分隔线；视图按钮为 22×20px，间距 2px，当前视图显示柔和绿色底；缩放滑块为灰色细轨和较小的圆形滑块。

本轮签名产品包 `0.1.13` 声明 `statusViews` 两个视图选项及状态栏颜色、尺寸。Flutter 通用表面 `0.1.12` 迭代产品声明的选项并分发对应命令，旧产品资源仍可使用原有默认视图。状态信息与当前视图来自工作簿快照，视图和缩放写入继续通过既有命令合同。底栏内容、展示、交互和引擎状态分层，保持 Everything is plugin。

## 视觉对比

| GenOffice 参考壳 | 第十三轮 OpenMuse | 第十四轮 OpenMuse |
| --- | --- | --- |
| ![GenOffice Ribbon、编辑区与底栏](evidence/round-14/genoffice-reference.png) | ![旧底栏和绿色滑块](evidence/round-14/desktop-home-before.png) | ![新底栏、视图按钮和灰色滑块](evidence/round-14/desktop-home.png) |

| 区域 | 本轮证据 |
| --- | --- |
| 顶部 Ribbon | [开始](evidence/round-14/desktop-home.png)、[插入](evidence/round-14/desktop-insert.png)，维持上轮签名布局。 |
| 中间编辑区 | 同一测试 XLSX 的网格与公式栏继续显示；[分页预览](evidence/round-14/desktop-page-break-view.png)切换后可返回[普通视图](evidence/round-14/desktop-status-normal.png)。 |
| 底部状态栏 | [普通视图](evidence/round-14/desktop-status-normal.png)、[状态统计菜单](evidence/round-14/desktop-status-menu.png)、[手机宽度](evidence/round-14/mobile-view.png)、[平板宽度](evidence/round-14/tablet-view.png)。灰色滑块和视图选中底色更接近参考；手机和平板为 Flutter Host 组件截图。 |

参考与 OpenMuse 截图使用不同工作簿。壳宽度接近但尚未在同一工作簿、同缩放下进行逐像素比较，不能视为 1:1 验收。

## 验证与人工产物

产品生成、校验和签名验证通过；三项几何测试、五项 Host 端到端测试通过。Host 测试核对签名资源的视图列表，实际点击分页预览与普通视图并截图。[联合构建报告](evidence/round-14/build-report-all.json)记录截图、源码及产物哈希。macOS 应用签名和 ZIP 完整性、Android APK 签名、arm64 原生库及两端内嵌插件包哈希均由流水线检查通过。

| 人工验证产物 | SHA-256 |
| --- | --- |
| [macOS Release ZIP](/Users/mac/src/openmuse-io/Muse-Client/dist/OpenMuse-spreadsheet-0.1.13-macos.zip) | `c05068b8a1d3454142d9fd6b3f589b555d0d3b2b74806901f8a7da3a450a7b28` |
| [Android arm64 Release APK](/Users/mac/src/openmuse-io/Muse-Client/dist/OpenMuse-spreadsheet-0.1.13-android-arm64.apk) | `4291d070d05883371823f6bff785dbcb180263f2f767f403b587f6b78d1d9d4a` |
| [签名产品包](/Users/mac/src/openmuse-io/Muse-Plugin-Ecosystem/plugins/spreadsheet-product/dist/spreadsheet-0.1.13.mcpb) | `ae8b8134904ce49291bebade893100ef9ca67c48585b0676337a4d83a49a5e43` |

## 后续差距

状态栏的缩放百分比按钮目前只显示值，GenOffice 点击后会打开缩放对话框。Ribbon SVG 图标、公式栏、可变行列尺寸和复杂对象仍需按同工作簿证据继续校准。
