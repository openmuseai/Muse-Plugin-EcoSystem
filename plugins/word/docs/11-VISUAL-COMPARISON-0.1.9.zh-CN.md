# Word 壳层 0.1.9 视觉对比与验收记录

本轮以 0.1.8 为基线，对照 GenOffice Docs 的 `apps/docs/src/renderer/components/icons.tsx`。桌面前后两图均为 1365×860、同一中文浅色 Flutter 原生窗口、同一 DOCX、同一视口。**这是 OpenMuse 迭代对比；尚无 GenOffice 同条件运行金图，不代表整套壳达到像素级 1:1。**

| 0.1.8 基线 | 0.1.9 源图标资源接入后 |
| --- | --- |
| ![0.1.8 桌面壳](evidence/0.1.9/before-0.1.8-desktop.png) | ![0.1.9 桌面壳](evidence/0.1.9/after-0.1.9-desktop.png) |

在相同像素坐标下，以单通道差值超过 12 作为变化判定：顶部 0–116px 有 4,323 / 158,340 像素变化（2.73%）；中央工作区 116–836px 为 0 / 982,800；纸页矩形 x=285–1080、y=142–836 为 0 / 551,730；底部状态栏 836–860px 有 320 / 32,760 变化（0.98%）。变化集中在操作图标，正文绘制未被本轮壳层修改。该指标只量化前后变化，不能用于评定与 GenOffice 的相似度。

## 源码与实现

| 领域 | GenOffice 对照 | OpenMuse 0.1.9 |
| --- | --- | --- |
| 顶部快速操作及 Ribbon | `icons.tsx` 的 SVG 几何、16 单位 viewBox、不同尺寸对应的细线宽度；各标签控件由 `Ribbon.tsx` 定义 | 将 63 个已映射语义图标提取成 `product/icons.json`，作为 Ed25519 签名产品资源安装。Flutter 壳按尺寸复现源线宽；缺少映射的控件暂用现有图标回退。`npm run audit:icons` 检查源文件与资源完全一致。 |
| 多级菜单 | `Ribbon.tsx` 与相邻菜单组件 | 0.1.8 的 62 个源码下拉入口、63 棵已签名菜单树继续由 `ribbon.json`、`menus.json` 驱动。本轮没有新增动态菜单行为。 |
| 中央内容区 | `styles.css` 的画布、页距、阴影；正文由 GenOffice 自身实现 | 保持 0.1.8 的几何与 `word_editor` / `word-core` 单一文档模型；插件仅提供壳资源，不读取或排版正文。 |
| 底部状态栏 | `App.tsx` 状态及视图按钮 | 四个视图入口和缩放图标优先使用签名 SVG；页数/缩放继续取 Host 会话和 Flutter ViewState。 |

GenOffice 图标原文件按 Apache-2.0 许可使用；产品包同时携带原许可和 `NOTICE`。`scripts/sync-genoffice-icons.mjs` 是可复现的提取器；安装时 Host 验签，Flutter 只解析受信任资源。产品包更新不会把 Dart 代码或 Rust 内核作为市场资源注入 Host。

窄屏组件截图用于检查功能区横向可达、画布和状态栏布局；它是 Flutter Widget 截图，**不是 Android 设备截图**：

![0.1.9 窄屏壳层](evidence/0.1.9/after-0.1.9-mobile-width.png)

Android API 34 ARM64 独立模拟器安装本轮 APK 后，关闭 Wi-Fi、无蜂窝连接，从本地 Downloads 打开 `sample2.docx`。页面正文实际渲染，状态栏显示“第 1 页，共 8 页”；“文件”和“粘贴”菜单均可打开。截图与窄屏 Widget 图分开保存，避免混淆设备验证与组件验证。

| Android 本地 DOCX | 文件菜单 | 粘贴菜单 |
| --- | --- | --- |
| ![Android Word 正文](evidence/0.1.9/after-0.1.9-android-open.png) | ![Android 文件菜单](evidence/0.1.9/after-0.1.9-android-file-menu.png) | ![Android 粘贴菜单](evidence/0.1.9/after-0.1.9-android-paste-menu.png) |

## 自动化与交付

- 一键流水线：`npm run stack:e2e -- --platform desktop --scope render --suite quick`，运行 ID `2026-10-23T03-59-34-816Z-66d6c14a`，报告位于仓库 `.word-stack-runs/` 下同名目录。插件 0.1.9、`word_editor` 0.4.5、Rust FFI、Flutter 组件、macOS Host、原生 DOCX 渲染、离线重开、独立/嵌入窗口和 DSH 面板门禁通过。
- 签名产品包：`plugins/word/dist/word-0.1.9.mcpb`，SHA-256 `4c3d04b76714c3159b023271bcf3f70ba4ba4616e522803c309a4e8a267dcea9`。测试公钥仅用于本地人工验收，不能作为市场发布密钥。
- macOS Debug ZIP：`Muse-Client/dist/OpenMuse-word-0.1.9-macos-debug.zip`，SHA-256 `8bdede1d0dbeb0d215dd8e58663ab12beddcf0e47e83b8475cd83a5ff6979927`；应用深度签名、ZIP 完整性通过。
- Android Debug APK：`Muse-Client/dist/OpenMuse-word-0.1.9-android-debug.apk`，SHA-256 `72d4023868f9044764b1fdfbd27f25c4e112db6a43c3960678dac71c0708f024`；含 ARM64 `libword_core_ffi.so`。两端包内签名插件摘要与上述 MCPB 完全相同。构建和设备验证明细位于运行目录 `platform-verification.json`。正式分发仍须生产签名。

## 后续销项

1. 补齐产品控件中未映射的图标，并逐控件核对源尺寸、颜色、hover、pressed、disabled、键盘焦点与触控目标。
2. 为全部一级/二级/三级菜单补运行截图与操作轨迹；封面、样式库、表格网格、公式预览、动态最近项目和选区状态仍需独立销项。
3. 取得同版本 GenOffice 的固定窗口金图后，对顶部、画布、状态栏分别做像素对齐报告；同时单独对比复杂 DOCX 的正文布局。
4. 页宽、文字宽度、整页、多页缩放以及字数、修订、选区格式等能力需 `word_editor` / 内核快照合同，再接入插件命令和状态。
