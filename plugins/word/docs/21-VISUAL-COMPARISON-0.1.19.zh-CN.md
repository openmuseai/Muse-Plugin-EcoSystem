# Word 壳层 0.1.19：视图页签后半段与网格线

## GenOffice 源码对照

`apps/docs/src/renderer/components/ribbon-tabs.tsx` 的 `ViewTab` 在“视图、缩放”之后依次是“外观、显示、窗口”。“显示”组包含“标尺、网格线、导航窗格”；中文标签来自 `i18n/ribbon/zh.ts`，SVG 来自 `components/icons.tsx`。`styles.css` 的 `.show-grid .doc-page` 用 24px 间距、约 13% 透明度的蓝线绘制网格，范围限制在页面正文区域。产品包保持该顺序，七个新增图标由可复现脚本从 GenOffice 源 SVG 生成并验签。

本轮启用“网格线”：签名插件声明 `word.view.gridlines` 低频视图命令；Flutter `word_editor` 保存开关，`word_render` 使用 `word-core` 页边距绘制网格，文档模型和排版命令不变。深色模式、标尺、导航窗格及窗口组已按源码列出，但在对应真实行为和 Host 能力合同完成前保持禁用。

## 同文档、同窗口视觉证据

以下图使用同一份 8 页 `sample2.docx`。桌面网格关闭与开启两张图的窗口、文档、缩放和 Ribbon 横向位置相同；网格只进入正文范围，页边距外仍为白色。上一轮与本轮的视图页签图可检查新增分组及源码顺序。

| 0.1.18 视图页签 | 0.1.19 视图页签 |
| --- | --- |
| ![上一轮视图页签](evidence/0.1.19/before-desktop-view-ribbon.png) | ![本轮视图页签](evidence/0.1.19/after-desktop-view-ribbon.png) |

| 0.1.19 桌面：网格关闭 | 0.1.19 桌面：网格开启 |
| --- | --- |
| ![网格关闭](evidence/0.1.19/after-desktop-grid-off.png) | ![网格开启](evidence/0.1.19/after-desktop-grid-on.png) |

| 0.1.19 Android ARM64 模拟器：网格关闭 | 0.1.19 Android ARM64 模拟器：网格开启 |
| --- | --- |
| ![设备网格关闭](evidence/0.1.19/after-android-grid-off.png) | ![设备网格开启](evidence/0.1.19/after-android-grid-on.png) |

设备在关闭 Wi-Fi 和蜂窝数据后安装新版 APK，从本地 Downloads 打开 `sample2.docx`，显示 8 页、5654 字。两张设备图的文档、缩放和 Ribbon 横向位置相同。[390px Flutter 测试窗口截图](evidence/0.1.19/after-mobile-grid-on.png)另用于布局回归。

## 验证与差距

[一键流水线](evidence/0.1.19/stack-report.json)的 20 个阶段和 8 个桌面端到端用例全部通过，包括新增的 `word_render` 网格像素测试。[渲染记录](evidence/0.1.19/render-evidence.json)、[封包哈希](evidence/0.1.19/package-verification.json)、[平台验证](evidence/0.1.19/platform-verification.json)记录签名包、双端内核及设备截图。macOS 打包应用打开 DOCX 得到 8 页、187 条绘制命令，DSH 面板返回 HTTP 200 并加载完成。

| 人工验证包 | SHA-256 |
| --- | --- |
| [macOS Debug ZIP](../../../../Muse-Client/dist/OpenMuse-word-0.1.19-macos-debug.zip) | `efec5f8642bd7bce26865a058a87725c8d52b92675274292b736f17d8aa78192` |
| [Android ARM64 Debug APK](../../../../Muse-Client/dist/OpenMuse-word-0.1.19-android-arm64-debug.apk) | `4ca1ecce542f362dbb55bb68eee3526e11c1044de47b9f6143d5bfd5e152b992` |

两个包都内嵌 SHA-256 为 `ba600afc13ae69f459b354c36e81693e538356f8583c03d9584f8618a9b95bbe` 的同一签名 Word 产品包。此版本使用开发测试密钥，仅供本地人工验证。

尚未有同文档的 GenOffice 运行金图，以上对比证明源控件顺序、源码几何及本轮前后视觉变化，**不宣称整套壳像素级 1:1**。深色页面、可编辑标尺、标题导航和多窗口交互需要进一步的只读状态及 Host 窗口合同；Web 版式、大纲、分页预览与多页也尚需独立布局。
