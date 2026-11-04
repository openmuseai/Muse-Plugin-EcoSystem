# Spreadsheet 产品壳第十八轮：Normal 字体列宽与同工作簿对照

## 本轮实现

研究 GenOffice `apps/sheets/src/renderer/univer-sync.ts` 中 `defaultColumnWidth`、`paddedBaseColumnWidth`、`characterWidthToPixels` 和 Normal 字体 MDW 的计算后，修正 GridCraft XLSX 导入：没有 `defaultColWidth` 时按 `baseColWidth`（缺省为 8）加单元格内边距推导默认宽度；显式列宽使用同一 Normal 字体度量。XLSX 导出使用对应的逆换算，避免保存重开后列宽漂移。Calibri 11 的 macOS 度量已经按 GenOffice 的实机证据校准为 MDW 8；其他字体暂用 7px 回退，后续需逐字体校准。

几何仍由工作簿引擎单一模型提供，桥接快照向通用 Flutter 表面输出默认宽度和稀疏覆盖列宽；网格、标题、选区、横向滚动及浮动对象共用它。签名产品资源升至 `0.1.17`，继续声明 Ribbon、多级菜单、状态栏和界面参数；Host 只负责验签、装载与路由。本轮没有把 XLSX 列宽规则写进 Host 或产品 UI 资源。

## 同一工作簿视觉证据

工作簿：`spreadsheet-geometry.xlsx`，SHA-256 `1fc6494d21318665ee225486dcfa749b2125ee6cd92cb1d0828d458f2144591a`。GenOffice 0.11.919 实机截图为 2720×1770 物理像素，OpenMuse 截图为 1365×860 逻辑像素；GenOffice 还包含原生标签栏，按约 2:1 缩放比较编辑区，不能据此宣称逐像素一致。

| 场景 | 证据 |
| --- | --- |
| GenOffice 顶部 Ribbon、编辑区、状态栏 | ![GenOffice 实机同工作簿](evidence/round-18/genoffice-same-workbook.png) |
| OpenMuse 修正前 | ![OpenMuse 修正前](evidence/round-18/openmuse-before-geometry.png) |
| OpenMuse 本轮 | ![OpenMuse 修正后](evidence/round-18/openmuse-after-geometry.png) |
| GenOffice 定位 Z100 | ![GenOffice 定位 Z100](evidence/round-18/genoffice-go-to-result.png) |
| OpenMuse 定位 Z100 | ![OpenMuse 定位 Z100](evidence/round-18/openmuse-go-to-result.png) |

同一文件中，OpenMuse 的默认列宽由 64px 改为约 69.33px；显式 B/C/D 列由 154/28/112px 改为 176/32/128px。修正后 A–D 的列边界与 GenOffice 实机图按 2:1 换算基本对齐；定位 `Z100` 后两者都从约 I 列显示至 Z 列。这里的对齐为视觉核对和模型数值核对，尚非自动逐像素差分。

[本轮完整桌面 Ribbon 与底栏](evidence/round-18/openmuse-ribbon-status.png)及[手机宽度截图](evidence/round-18/openmuse-mobile.png)用于回归检查。仍可见原生标签栏、状态文案和弹窗背景模糊等差异；其他 Normal 字体的 MDW、冻结窗格、RTL、复杂对象及尚未接通的 Ribbon 控件仍需后续轮次验收，当前整个壳不能标记为 1:1 完成。

## 验证与人工安装包

GridCraft XLSX 库 182 项测试通过，覆盖 Calibri 11 默认/显式列宽和导出逆换算；Flutter 通用表面 8 项测试、Host 6 项真实 XLSX 端到端测试通过。Host 测试包含同工作簿几何、`Z100` 定位、Ribbon、状态栏、编辑保存重开及对象回归，共生成 54 张截图。产品资源生成、Schema 校验、Ed25519 开发密钥签名与验签通过。macOS 应用通过 `codesign --verify --deep --strict`，APK 通过 `apksigner verify`；两个发布包中的签名 `spreadsheet.mcpb` 哈希与独立产品包一致，细节见[构建报告](evidence/round-18/build-report-all.json)。Android 包使用本地调试签名，仅供人工验证。

APK 已通过 `adb -s emulator-5556 install -r` 安装到模拟器，包管理器返回 `Success`；本轮没有把模拟器内人工操作记为已完成测试。

| 产物 | SHA-256 |
| --- | --- |
| [macOS Release ZIP](/Users/mac/src/openmuse-io/Muse-Client/dist/OpenMuse-spreadsheet-0.1.17-macos.zip) | `1cb1c9b8375fa6d5ed3915a221d2fef42dcdd41a411274f04bccc860308a627b` |
| [Android arm64 Release APK](/Users/mac/src/openmuse-io/Muse-Client/dist/OpenMuse-spreadsheet-0.1.17-android-arm64.apk) | `41bb8c2c3f20ad9e0bbf651618dc0ad5cbb98de930d68a05720e48ba676553af` |
| [签名产品包](/Users/mac/src/openmuse-io/Muse-Plugin-Ecosystem/plugins/spreadsheet-product/dist/spreadsheet-0.1.17.mcpb) | `2e77c5661ff7e57d18966d4838831cce0fea0ce6441cdf2b4b192d94454345c7` |
