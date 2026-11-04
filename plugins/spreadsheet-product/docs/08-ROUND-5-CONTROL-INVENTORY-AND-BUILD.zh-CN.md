# Spreadsheet 产品壳第五轮：补齐 Ribbon 入口与状态栏菜单

## 源码对齐与分层

本轮逐组核对 `genoffice/apps/sheets/src/renderer/ExcelShell.tsx` 的七个常驻 Ribbon 标签及 `status-bar-stats.ts`。签名产品包升为 `0.1.4`，Flutter `spreadsheet_editor` 升为 `0.1.3`。产品资源现有 **11 个标签、55 个组、183 个控件、65 棵菜单**；新增的 `grid` 布局描述“插入”页的 3×3 图表类型区。`validate.mjs` 检查每个格位和每组控件的覆盖关系；Flutter 只解释该通用布局。状态栏六种统计项及默认勾选集也由产品资源声明，数值来自 Host 随包的 Rust 工作簿会话。

本轮新增或校正的入口主要包括：插入页九类图表、数据透视图、时间线、公式、截图；页面布局的打印标题；公式页的函数类别、名称创建、公式审核和工作表重算；数据页的数据导入、透视表刷新、排序筛选和快速填充；审阅页的工作簿统计、批注与注释；视图页的显示开关。状态栏长按或右击可切换平均值、计数、数值计数、最小值、最大值、求和；选区数值由内核快照提供。资源中的未接入命令继续显示禁用态及原因，不向用户伪装成可执行功能。

工作簿唯一模型、计算、导入导出仍在固定的 GridCraft Rust 桥接；Flutter 编辑面仍编译进 Host。签名产品包只含低频壳配置与命令声明，不包含逐字输入、单元格绘制或公式计算代码。`ss-core` 尚未达到替换条件。

## 逐轮视觉对照

参考图来自用户提供的 GenOffice 工作簿，分辨率 2750×1706（约 1375×853 逻辑像素）；本轮 Flutter 测试窗口为 1365×860。两者文档内容不同，因此比较壳层结构、密度和菜单可达性，**不构成逐像素一致性证明**。

| 对照点 | GenOffice / 上轮 | 第五轮证据 | 观察与差异 |
| --- | --- | --- | --- |
| 顶部开始页、公式栏、中央网格、底栏 | [参考图](evidence/round-5/genoffice-reference.png)、[第四轮开始页](evidence/round-4/desktop-home.png) | [开始页](evidence/round-5/desktop-home.png) | 四层结构、深色主题、分组 Ribbon、行列标题、工作表标签和缩放条均可见；参考文件的图表与对象尚未在自研表面实现。 |
| 插入多级 Ribbon | `ExcelShell.tsx` 的 `chart-grid` 九项与分组菜单；[第四轮插入页](evidence/round-4/desktop-insert.png) | [第五轮插入页](evidence/round-5/desktop-insert.png) | 图表九宫格、数据透视图、时间线、公式等入口已进入签名资源；图标、标签间距、图表对象功能仍有差异。 |
| 其他一级标签 | `ExcelShell.tsx` 的 Page Layout、Formulas、Data、Review、View 分支 | [页面布局](evidence/round-5/desktop-pageLayout.png)、[公式](evidence/round-5/desktop-formulas.png)、[数据](evidence/round-5/desktop-data.png)、[审阅](evidence/round-5/desktop-review.png)、[视图](evidence/round-5/desktop-view.png) | 各页补充缺失入口；较宽的 Ribbon 可横向滚动，部分菜单叶子仍是禁用占位。 |
| 二级菜单与上下文 | GenOffice 下拉菜单与选区相关标签 | [边框二级菜单](evidence/round-5/desktop-border-submenu.png)、[表格上下文](evidence/round-5/desktop-table-context.png) | 产品资源驱动级联菜单；真实选区触发上下文标签。 |
| 状态栏统计 | `status-bar-stats.ts` 的六项、默认平均值/计数/求和 | [选区统计](evidence/round-5/desktop-selection-stats.png)、[六项菜单](evidence/round-5/desktop-status-menu.png)、[勾选最大值后](evidence/round-5/desktop-selection-stats-max.png) | 测试选区 A1:D2 显示求和 534、最大值 267；菜单全部可见且可勾选。 |
| 响应式 | 桌面参考图与第四轮设备截图 | [平板](evidence/round-5/tablet-view.png)、[折叠屏](evidence/round-5/foldable-view.png)、[手机](evidence/round-5/mobile-view.png) | 小屏使用横向控件带，工作簿网格和底栏仍可操作。 |
| Android 实机路径 | 第四轮安装运行截图 | [Host 启动](evidence/round-5/android-launch.png)、[Spreadsheet 路由](evidence/round-5/android-spreadsheet-route.png)、[真实 XLSX](evidence/round-5/android-xlsx-open.png)、[插入页与 XLSX](evidence/round-5/android-insert-xlsx.png) | arm64 模拟器安装本轮 APK，经 Host 文件选择器打开 2 sheet 样本，显示 `Region/Q1/Q2/North/125/142` 并切换“插入”。 |

## 构建与验证

在本工作区执行 `bash Muse-Client/scripts/spreadsheet-product-e2e.sh all`：重新生成并验签 0.1.4 资源包，构建原生桥接，执行两个 Flutter 端到端测试（签名/篡改拒绝、真实 XLSX 打开与编辑导出重开、11 个标签及菜单），再构建 macOS Release 和 Android arm64 Release。Flutter 静态分析、`codesign --verify --deep --strict`、APK 签名校验通过。版本化 macOS ZIP 独立从验签 App 生成，`unzip -tq` 通过；ZIP 和 APK 内嵌产品包的 SHA-256 均与签名包一致。详情见 [构建报告](evidence/round-5/build-report.json)。

| 供人工验证的产物 | SHA-256 |
| --- | --- |
| [macOS Release ZIP](/Users/mac/src/openmuse-io/Muse-Client/dist/OpenMuse-spreadsheet-0.1.4-macos.zip) | `38a11fe9877044465c7c589b22be9629de628fbaad2f1f290f5f9c8c040aca3c` |
| [Android arm64 APK](/Users/mac/src/openmuse-io/Muse-Client/dist/OpenMuse-spreadsheet-0.1.4-android-arm64.apk) | `368d9560a89638324baf884e5e1fe9d7b0ef6a394dbc92c430d29c5dc1b4fb52` |
| [签名产品包](/Users/mac/src/openmuse-io/Muse-Plugin-Ecosystem/plugins/spreadsheet-product/dist/spreadsheet-0.1.4.mcpb) | `3dbf51f337752c09f7516c8695dd7ec2eb9147106a47d0c05ba7060f2aa842b8` |

本轮使用本地开发用 Ed25519 密钥及 Android 验证签名，产物供本地人工验证。macOS 的 Spreadsheet 路由本轮由 Flutter Host 组件端到端测试覆盖，尚未在真实 macOS 窗口手工逐项点击。GenOffice 的图表、对象、格式对话框、完整快捷键与复杂工作簿编辑仍未达到一比一；本轮完成的是这些入口的壳层资源和可见布局。下一轮应使用同一复杂工作簿、同一逻辑尺寸检查图标/间距，并逐项将已声明的菜单叶子接入内核能力或清晰的禁用说明。
