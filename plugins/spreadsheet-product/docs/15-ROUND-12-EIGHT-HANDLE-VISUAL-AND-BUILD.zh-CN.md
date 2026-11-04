# Spreadsheet 产品壳第十二轮：八方向对象缩放

## 源码对照与领域边界

继续核对 GenOffice `apps/sheets/src/renderer/WorkbookVisuals.tsx` 的 `EditableShapeVisual`、`walkMarker`，以及 `styles.css` 的 `.shape-handle`。参考实现选中时显示八个 9px 白底圆点；从任一边/角拖动时移动该边，保持对侧边界，最小边长 24px，提交后才修改工作簿锚点。本轮 OpenMuse 通用表面 `0.1.10` 补齐八个控制点，使用纯 `VisualGeometry` 建模八方向、工作表起点和最小尺寸。签名产品包 `0.1.11` 继续声明 `visualActions.resize → object.move`，由 GridCraft 桥接 `0.1.5` 持有对象、撤销和 XLSX 保存。指针识别、几何计算、命令绑定与工作簿写入各处于独立层。

## 视觉对比证据

GenOffice 参考图为 2750×1706，OpenMuse 桌面视口为 1365×860。**两者仍不是同一 XLSX**，此处只对照壳的 Ribbon、编辑区与底栏；八控制点则按 GenOffice 源码的尺寸和颜色对照 OpenMuse 实际截图。同工作簿的前后截图验证本轮交互效果，不能代替 GenOffice 同工作簿逐像素验收。

| GenOffice 壳参考 | OpenMuse 本轮壳与对象层 |
| --- | --- |
| ![GenOffice 顶部 Ribbon、中间内容、底部状态](evidence/round-12/genoffice-reference.png) | ![OpenMuse 顶部 Ribbon、真实 XLSX 对象层、底部状态](evidence/round-12/desktop-objects.png) |

| 选中形状：八个控制点 | 左上角缩放后：右下边界不变 |
| --- | --- |
| ![八个缩放控制点](evidence/round-12/desktop-shape-eight-handles.png) | ![从左上角扩大形状](evidence/round-12/desktop-shape-northwest-resized.png) |

| 区域 | 本轮证据与差异 |
| --- | --- |
| 顶部多级 Ribbon | [开始](evidence/round-12/desktop-home.png)、[插入](evidence/round-12/desktop-insert.png)、[形状菜单](evidence/round-12/desktop-shape-menu.png)、[形状格式](evidence/round-12/desktop-shape-context.png)。11 个标签、55 组、183 控件、66 棵菜单由签名资源组织；部分图标、组宽和格式命令仍未对齐。 |
| 中间编辑区 | [初始](evidence/round-12/desktop-objects.png)、[移动](evidence/round-12/desktop-shape-moved.png)、[右下缩放](evidence/round-12/desktop-shape-resized.png)、[左上缩放](evidence/round-12/desktop-shape-northwest-resized.png)、[左侧缩放](evidence/round-12/desktop-shape-west-resized.png)。图表、形状、图片仍按工作簿锚点绘制。八个控制点均显示，纯几何测试逐一验证对侧边界；Host 实际手势测试覆盖右下、左上和左侧。旋转、RTL 与可变行列尺寸尚未还原。 |
| 底部状态和响应式 | [状态菜单](evidence/round-12/desktop-status-menu.png)、[手机宽度](evidence/round-12/mobile-objects.png)、[平板宽度](evidence/round-12/tablet-view.png)。表签、状态、视图与缩放保留；手机截图是 Flutter Host 组件测试。 |

## 验证与人工产物

三项几何测试验证八方向对侧边界不变、最小 24px、工作表起点和规范化锚点；五项 Host 端到端测试覆盖签名包、真实 XLSX、对象交互、保存重开、删除撤销及自动保存。此轮的 [原始对象 XLSX](evidence/round-12/objects-roundtrip.xlsx) 和 [编辑后 XLSX](evidence/round-12/objects-edited.xlsx) 可供人工复核。联合流水线新增通用表面的静态分析与几何测试，随后构建并核验双端包。初次 macOS 构建遇到共享 Xcode 构建数据库占用，进程退出后重试成功。构建哈希、源码和仓库状态分别见 [macOS 报告](evidence/round-12/build-report-macos.json) 和 [Android 报告](evidence/round-12/build-report-android.json)。

| 人工验证产物 | SHA-256 |
| --- | --- |
| [macOS Release ZIP](/Users/mac/src/openmuse-io/Muse-Client/dist/OpenMuse-spreadsheet-0.1.11-macos.zip) | `aa9046678c031cf352708f15ff1ab8aa105c750000152c4fb150a5c19bd0ce57` |
| [Android arm64 Release APK](/Users/mac/src/openmuse-io/Muse-Client/dist/OpenMuse-spreadsheet-0.1.11-android-arm64.apk) | `42e98c525de45377f553bc9e0af1117e74f35b2454e77883142caebcf21e007a` |
| [签名产品包](/Users/mac/src/openmuse-io/Muse-Plugin-Ecosystem/plugins/spreadsheet-product/dist/spreadsheet-0.1.11.mcpb) | `0a427d307186ca2ddd00d56cc5f89d2fb76887f5880e176198b7690748a3bfde` |

## 后续差距

目前尚未达到 GenOffice 1:1。OpenMuse 的对象坐标仍按固定默认行高和列宽换算；GenOffice 会逐格计算可变行列尺寸、处理 RTL、旋转对象的真实框架及拖动中的滚动。Ribbon 图标、组间距、公式栏、状态栏也需要在同一工作簿、同视口与同缩放下逐项校准。Android APK 本轮用于人工安装验证，手机编辑区截图仍来自组件测试。
