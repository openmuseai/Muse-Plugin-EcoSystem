# Spreadsheet 壳第一轮：视觉对比和构建证据（2026-10-23）

## 证据图

| 来源 | 图 | 验证点 |
| --- | --- | --- |
| GenOffice 参考，2750×1706 | [参考截图](evidence/round-1/genoffice-reference.png) | 深色主题、顶部七个常驻标签、双层开始 Ribbon、公式栏、网格/图表对象、工作表标签、底部状态栏 |
| OpenMuse Desktop Flutter 表面，1365×860 | [开始](evidence/round-1/desktop-home.png)、[插入](evidence/round-1/desktop-insert.png)、[数据](evidence/round-1/desktop-data.png)、[边框三级菜单](evidence/round-1/desktop-border-submenu.png) | 同序标签/组、35/80px 上壳、40px 公式栏、原生网格、底部表签和 24px 状态栏；真实 XLSX 的 Region/North/公式结果 267，菜单浮层及嵌套路径 |
| OpenMuse Android 真实 Host，1080×2340 | [打开 XLSX](evidence/round-1/android-open-xlsx.png)、[保存反馈](evidence/round-1/android-save.png)、[二级菜单](evidence/round-1/android-menu.png) | APK 安装、离线签名包、系统文件选择器、GridCraft arm64 原生库、手机宽度横向可达 Ribbon 与工作表；本地 XLSX 副本保存反馈；菜单浮层不被网格裁剪 |

同一份输入样本为 `Muse-Client/app/openmuse_host/test/fixtures/spreadsheet-shell.xlsx`；参考图中的图表和第 40 行不是这个样本的内容，故本轮只比较壳几何、层次、颜色和入口位置，不用它判断图表渲染保真。

## 对齐结果与差异

| 区域 | GenOffice 基准 | 第一轮结果 | 后续工作 |
| --- | --- | --- | --- |
| 顶部标签 | 7 常驻 + 4 选区上下文；选中绿色下划线 | 资源中覆盖 11 标签；7 常驻可切换，下划线/间距和深色 token 接近 | 由图表/表格/对象选区驱动 4 个上下文标签；适配折叠屏与高字体缩放 |
| 开始 Ribbon | AI、剪贴板、字体、对齐、数字、样式、单元格、编辑，大小控件混排 | 8 组按序登记，横向滚动、下拉及递归菜单可用 | 逐控件还原两层密度、字型/字号输入框、图标和 hover/选中状态；目前材料图标是占位 |
| 其他 Ribbon | 插入/页面布局/公式/数据/审阅/视图及多级菜单 | 产品资源含 55 组、157 个控件、62 棵菜单；Flutter 由资源绘制，屏幕宽度不足时横滚 | 逐项核对源码命令参数、弹窗和三级路径；未接引擎命令保持禁用并显示原因 |
| 编辑区 | 名称框、公式栏、行列标题、虚拟网格、对象层 | 真实 XLSX 的值与公式结果可见，点选与单元格对话框编辑、公式栏输入可写入 GridCraft | 可视范围虚拟化、图表/图片对象层、冻结、合并、原位 IME、列宽行高、完整选区 |
| 底部 | 工作表标签、状态/聚合、视图开关、缩放 | 表签、Ready/已修改、视图图标、缩放条与百分比位置已接 | 工作表增删改、聚合统计、视图模式、缩放与网格几何一致性 |

本轮截图显示结构已形成，但**尚未达到一比一视觉或功能验收**。尤其参考图含大图表、分栏对象和行 40 起始滚动，我们当前仅显示单元格层；这些差异不能由替换截图素材掩盖。

## 可复现的验证

1. `npm run generate && npm run validate && npm run pack -- --private-key ... --key-id spreadsheet-local-v1 && npm run verify`：签名资源包生成及验证通过；篡改字节的 Dart 验签测试拒绝加载。
2. `cargo build --release` 与 `cargo ndk -t arm64-v8a ... build --release`：同一 GridCraft 桥接代码分别生成 macOS/Android 库，ABI 1。
3. `flutter test test/spreadsheet_product_e2e_test.dart`：1 项端到端组件测试通过，验证签名包、路由、真实 XLSX 的 Region/North/公式值 267、改单元格为 126、导出与重开、边框的三级菜单；七个常驻标签截图及 390×844 小屏截图保存在 `Muse-Client/dist/spreadsheet-evidence-2026-10-23/`。
4. Android arm64 Release APK 构建后以本机 Android 开发证书签名：`apksigner verify` v2/v3 通过；模拟器安装并在 Host 内选择 XLSX、保存本地副本，见上方设备截图。此证书仅用于本地人工验证。
5. macOS Release `OpenMuse.app` 构建、DSH closure 的无密钥运行检查、完整包的 `codesign --verify --deep --strict` 均通过。包内含 `libopenmuse_gridcraft_bridge.dylib`、签名 `spreadsheet.mcpb`、公钥及版本身份。Release ZIP 位于 `Muse-Client/dist/OpenMuse-macos.zip`。

一键复现：在工作区执行 `bash Muse-Client/scripts/spreadsheet-product-e2e.sh all`。它依次生成/签名/验签产品包、编译两端 Rust 库、运行 XLSX 端到端测试、构建两端 Host、校验 macOS 签名和 Android APK 的原生库/资源，并写出 `Muse-Client/dist/spreadsheet-evidence-2026-10-23/report.json`（版本、源码/产物哈希、截图清单）。

## 下一轮退出条件

以相同文档和同尺寸画布重测：先实现可视范围虚拟网格与对象层接口，再精确对齐 Ribbon 的双层控件形状/图标/状态和三级菜单；接入上下文选区触发，覆盖平板、折叠、小屏和 200% 字体；补齐撤销/重做、保存失败回滚、断网重启及 CSV/多 sheet 语料。每次迭代将新截图、差异及构建哈希放到 `docs/evidence/round-N/`，保留历史证据。
