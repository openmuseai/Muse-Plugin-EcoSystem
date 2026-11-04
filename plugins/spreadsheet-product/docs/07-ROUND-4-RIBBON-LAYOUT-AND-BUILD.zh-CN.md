# Spreadsheet 产品壳第四轮：全标签 Ribbon 布局

## 本轮范围与架构

对照 `genoffice/apps/sheets/src/renderer/ExcelShell.tsx` 的 Home、Insert、Page Layout、Formulas、Data、Review、View 及上下文 Ribbon 分支，给签名产品包的 **11 个标签、55 个组、157 个现有控件**全部定义混排布局。大按钮、竖列、双排由产品资源描述；Flutter `spreadsheet_editor` 只渲染通用布局，并在桌面显示组标题。产品版本 `0.1.3`、Flutter 表面 `0.1.2`；引擎 ABI 与表面主版本均保持 1。工作簿状态、公式计算和 XLSX 导入导出继续由 Host 随包的 GridCraft Rust 桥接负责。

`validate.mjs` 现在要求每一组都有布局，且每个控件在布局中恰好出现一次。产品包可更新 Ribbon 的编排而无需发布新的 Host；通用布局渲染器的改动则需要随 Host 更新。命令仍经有版本的产品命令表分派，扩展不进入单元格输入或计算热路径。

## 可视对照

参考截图与本轮测试工作簿的窗口尺寸、内容不同，下面检验的是壳的层次和组内结构，不作为像素级一致证明。

| 对照点 | 参考 / 上轮 | 本轮证据 | 观察 |
| --- | --- | --- | --- |
| 整体壳、开始页 | [GenOffice 参考](evidence/round-4/genoffice-reference.png)、[第三轮开始页](evidence/round-3/desktop-home.png) | [第四轮开始页](evidence/round-4/desktop-home.png) | 组标题与大按钮、双排、竖列同时出现；公式栏、网格、表签和状态栏保持分层。 |
| 插入 | [第三轮插入页](evidence/round-3/desktop-insert.png) | [第四轮插入页](evidence/round-4/desktop-insert.png) | 插图及图表组改为大按钮加小按钮，显示“表格/插图/图表”等组标题。 |
| 页面布局 | [第三轮页面布局](evidence/round-3/desktop-pageLayout.png) | [第四轮页面布局](evidence/round-4/desktop-pageLayout.png) | 主题、页面设置、缩放和工作表选项按组混排。 |
| 公式、数据、审阅、视图 | 源码中相应的 `RibbonGroup` | [公式](evidence/round-4/desktop-formulas.png)、[数据](evidence/round-4/desktop-data.png)、[审阅](evidence/round-4/desktop-review.png)、[视图](evidence/round-4/desktop-view.png) | 四个一级标签均由插件数据驱动，不再退化为全等大按钮。 |
| 多级菜单与上下文 | [第三轮边框子菜单](evidence/round-3/desktop-border-submenu.png) | [第四轮边框子菜单](evidence/round-4/desktop-border-submenu.png)、[表格设计](evidence/round-4/desktop-table-context.png) | 二级边框菜单仍可展开，真实表格选区仍显示上下文标签。 |
| 响应式 | [第三轮手机](evidence/round-3/mobile-view.png) | [平板](evidence/round-4/tablet-view.png)、[折叠屏](evidence/round-4/foldable-view.png)、[手机](evidence/round-4/mobile-view.png) | 小屏使用横向可滚动的图标带，中央编辑网格及底栏仍可操作。 |
| Android 运行路径 | Host 内的“添加内容”入口 | [APK 启动](evidence/round-4/android-launch.png)、[插件页面](evidence/round-4/android-spreadsheet-route.png)、[打开 XLSX](evidence/round-4/android-xlsx-open.png)、[插入页与 XLSX](evidence/round-4/android-insert-xlsx.png) | 在 arm64 模拟器上安装本轮 APK，经 Host 入口打开 `spreadsheet-shell.xlsx`，显示 `Region/Q1/Q2` 和数据行，并切换到“插入”。 |

## 验证与尚未完成的对齐

`bash Muse-Client/scripts/spreadsheet-product-e2e.sh all` 从同一 checkout 生成并验签资源包、执行真实 XLSX 导入/编辑/导出/重开测试、截图，并构建 macOS 与 Android。测试还确认 11 个标签的所有组都有布局；构建报告在 [机器可读证据](evidence/round-4/build-report.json)。

| 供人工验证的产物 | SHA-256 |
| --- | --- |
| [macOS Release ZIP](/Users/mac/src/openmuse-io/Muse-Client/dist/OpenMuse-spreadsheet-0.1.3-macos.zip) | `4f43a3e9fdc00583066436ca71320f2282bcd9fcd78bde0ce7be0cec7edd4106` |
| [Android arm64 APK](/Users/mac/src/openmuse-io/Muse-Client/dist/OpenMuse-spreadsheet-0.1.3-android-arm64.apk) | `d5140efe98fff1c6abe4ac7a744aa835cd602cfa81e9fddf9b5b35aa9b870ae8` |
| [签名产品包](/Users/mac/src/openmuse-io/Muse-Plugin-Ecosystem/plugins/spreadsheet-product/dist/spreadsheet-0.1.3.mcpb) | `25b1da2136405468e0a1de029bd84fec4107ca6226c28b73d654a0a25ab45571` |

macOS 应用通过 `codesign --verify --deep --strict`、DSH closure 检查，并已启动看到 Host 窗口；macOS 的 Spreadsheet 路由本轮未做手工点击。Android APK 通过 v2/v3 签名验证，模拟器安装、Host 入口与真实 XLSX 渲染已验证。两端内嵌的产品资源字节 SHA-256 均与上表签名包相同。

上述产品包使用本地开发用 Ed25519 密钥签名，APK 使用本地验证签名；面向商店的发行签名不在本轮范围内。

这一轮改进的是 **现有控件的组内布局**。GenOffice 源码中的部分控件尚未加入 157 项清单，例如“插入”中的更多图表类型、部分“视图”显示开关、主题图库等；部分菜单目前只是命令占位，不能宣称完整功能或逐像素一比一。参考截图包含真实图表、图片和更复杂的工作簿，而当前自研编辑面尚缺这些对象的绘制和选择层。后续按源码逐组补齐控件和多级菜单，再接入相应内核命令，并用相同工作簿、相同尺寸做视觉差异检查。
