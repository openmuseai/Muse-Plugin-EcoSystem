# Spreadsheet 产品壳第十三轮：Ribbon 带内布局

## 源码对照与实现

对照 GenOffice `apps/sheets/src/renderer/styles.css` 的 `.ribbon`、`.ribbon-group`、`.ribbon-tool`：桌面 Ribbon 为 80px 带，顶部标签与 Ribbon 融合；组之间使用内缩细分隔线，带内没有组标题。第十二轮 OpenMuse 截图仍显示“字体”“对齐”等组标题，分隔线跨满 Ribbon，且大按钮和字体字段过宽，导致右侧控件较早被水平裁切。

本轮签名产品包 `0.1.12` 新增 `showRibbonGroupCaptions` 和五项 Ribbon 控件宽度指标，由产品资源生成与校验。Flutter 通用表面 `0.1.11` 按这些指标呈现；旧资源包缺少指标时保留原尺寸。组标题移除后，按钮获得完整带高；分隔线随组内容内缩。Ribbon 的内容声明、展示指标、通用布局和工作簿命令各在独立层，保持 Everything is plugin。

## 视觉对比

GenOffice 参考为 2750×1706 截图，OpenMuse 测试视口为 1365×860，宽高约为参考截图的一半。参考和本地截图仍使用不同 XLSX，因此只能比较壳的结构与控件密度，不能声称逐像素一致。

| GenOffice 参考 | OpenMuse 第十二轮 | OpenMuse 第十三轮 |
| --- | --- | --- |
| ![GenOffice Ribbon、编辑区和状态栏](evidence/round-13/genoffice-reference.png) | ![OpenMuse 调整前](evidence/round-13/desktop-home-before.png) | ![OpenMuse 调整后](evidence/round-13/desktop-home.png) |

| 区域 | 本轮证据与剩余差距 |
| --- | --- |
| 顶部多级 Ribbon | [开始](evidence/round-13/desktop-home.png)、[插入](evidence/round-13/desktop-insert.png)、[形状上下文](evidence/round-13/desktop-shape-context.png)。11 标签、55 组、183 控件、66 棵菜单仍由签名资源声明；带内组标题已移除，按钮宽度更接近源码。图标形态、局部行距及部分命令仍未对齐。 |
| 中间编辑区 | 同一测试 XLSX 的网格、公式栏和对象层保持可见；本轮不改变工作簿读写。可变行列尺寸、RTL、旋转对象及图表复杂样式仍待实现。 |
| 底部状态与移动宽度 | [状态菜单](evidence/round-13/desktop-status-menu.png)、[手机宽度](evidence/round-13/mobile-view.png)、[平板宽度](evidence/round-13/tablet-view.png)。手机和平板图来自 Flutter Host 组件测试。 |

## 验证与人工产物

产品资源生成、校验、签名验证通过；三项几何测试和五项 Host 端到端测试通过，Host 测试额外断言产品配置生效且“字体”组标题没有出现在桌面壳。[联合构建报告](evidence/round-13/build-report-all.json) 记录源码、截图和产物哈希。macOS ZIP 通过应用签名与压缩包校验，Android APK 通过签名和 arm64 原生库检查；两端内嵌的签名产品包哈希均与下表一致。

| 人工验证产物 | SHA-256 |
| --- | --- |
| [macOS Release ZIP](/Users/mac/src/openmuse-io/Muse-Client/dist/OpenMuse-spreadsheet-0.1.12-macos.zip) | `7337c02ed3c5678fa60edc213397e3b1fdf87767d574bebcd83271dfd34205f5` |
| [Android arm64 Release APK](/Users/mac/src/openmuse-io/Muse-Client/dist/OpenMuse-spreadsheet-0.1.12-android-arm64.apk) | `dce18fda426504c8475cc8609e3e590413135d2481d8d1daddbab6358d922576` |
| [签名产品包](/Users/mac/src/openmuse-io/Muse-Plugin-Ecosystem/plugins/spreadsheet-product/dist/spreadsheet-0.1.12.mcpb) | `e441e5321a5cd6149f8db1b5e3727a48d6b0706004ede86989d88380c1f4b535` |

## 下一步

需要使用同一复杂 XLSX、相同视口与缩放的 GenOffice 和 OpenMuse 截图做逐项对齐。Ribbon 的 SVG 图标、局部间距、公式栏和状态栏仍未达到 1:1；对象层还需支持可变行列尺寸、旋转和 RTL。
