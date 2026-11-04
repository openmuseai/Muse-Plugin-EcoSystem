# Word 壳层 0.1.17：阅读视图

## GenOffice 源码对照

`App.tsx` 的“视图”页签和状态栏均提供页面、Web、大纲、阅读四个视图入口。阅读视图会隐藏 Ribbon 等工作区组件，显示右上角退出按钮，并支持 Esc 返回；`styles.css` 将阅读视图纸页顶部留白设为 44px，退出按钮为 30px 高、圆角胶囊。本轮对照 `ribbon-tabs.tsx`、`App.tsx`、`styles.css` 和中文 `i18n` 标签，接通页面与阅读两种视图。

签名产品包只声明视图命令、图标和文案；Flutter `word_editor` 拥有视图状态、响应式壳与纸页滚动，`word-core` 独占文档模型和排版。Web 版式与大纲目前没有相应布局合同，保留不可用状态，避免把分页纸页误标为新布局。

## 同文档前后视觉对比

桌面使用同一份 8 页 `sample2.docx`。左图为 0.1.16 页面视图，右图为 0.1.17 阅读视图。

| 页面视图 | 阅读视图 |
| --- | --- |
| ![桌面页面视图](evidence/0.1.17/before-desktop-print.png) | ![桌面阅读视图](evidence/0.1.17/after-desktop-read.png) |

手机宽度下，“视图”功能区仍可触达阅读入口；进入后隐藏功能区，右上角保留退出按钮，状态栏仍显示页码与缩放。

| 手机页面视图 | 手机阅读视图 |
| --- | --- |
| ![手机页面视图](evidence/0.1.17/before-mobile-print.png) | ![手机阅读视图](evidence/0.1.17/after-mobile-read.png) |

Android ARM64 模拟器关闭 Wi-Fi 和蜂窝数据后，从本地 Downloads 打开同一 DOCX 并切换阅读视图。

| Android 页面视图 | Android 阅读视图 |
| --- | --- |
| ![Android 页面视图](evidence/0.1.17/after-android-print.png) | ![Android 阅读视图](evidence/0.1.17/after-android-read.png) |

[退出阅读视图后的 Android 截图](evidence/0.1.17/after-android-exit.png)显示 Ribbon 恢复，文档仍为 8 页、5654 字。

## 验证与边界

[联合流水线](evidence/0.1.17/stack-report.json)的 18 个阶段和 8 个桌面端到端用例全部通过。[DOCX 渲染记录](evidence/0.1.17/render-evidence.json)、[封包校验](evidence/0.1.17/package-verification.json)和[平台验证](evidence/0.1.17/platform-verification.json)记录签名产品包、Flutter 视图交互、原生渲染、DSH 面板、离线 Android 与两端安装包。macOS 打包应用启动后输出 `OPENMUSE_WORD_RENDER_READY:8:187`，DSH WebView 返回 HTTP 200 并完成加载；代码签名校验通过。Android 模拟器离线安装、打开本地 DOCX、进入及退出阅读视图均通过。

供本地人工验证的安装包：[macOS Debug ZIP](/Users/mac/src/openmuse-io/Muse-Client/dist/OpenMuse-word-0.1.17-macos-debug.zip)（SHA-256 `76f1385691c9412baa9d94e3bf184bb6d2bb48658a049ee58f1597ca3702f192`）和 [Android ARM64 Debug APK](/Users/mac/src/openmuse-io/Muse-Client/dist/OpenMuse-word-0.1.17-android-arm64-debug.apk)（SHA-256 `342e43eabe9b54393ea21d291d3645238ebb084c0979f45b416f5bedad0a9912`）。两包内置的 Word 产品资源均与 `word-0.1.17.mcpb` 字节相同，使用开发测试 Ed25519 密钥签名。

本轮没有 GenOffice 同文档运行金图，因此上述图片证明我们版本前后变化，不能作为整套壳像素级 1:1 的验收。阅读模式复用 `word-core` 的分页绘制；Web 版式、大纲结构视图、修订状态和编辑能力仍须后续逐项实现与对照。
