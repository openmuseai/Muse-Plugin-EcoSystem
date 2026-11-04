# Word 壳层 0.1.18：视图缩放组

## GenOffice 对照与职责

对照 `apps/docs/src/renderer/components/ribbon-tabs.tsx` 的 `ViewTab`：视图组依次为页面、Web、大纲、阅读、分页预览；缩放组依次为缩放弹窗、缩小、放大、100%、页宽、整页、多页。中文标签来自 `i18n/ribbon/zh.ts`，图标路径来自 `components/icons.tsx`。

签名 Word 产品包声明这些控件、稳定命令 ID 和源 SVG 图标。Flutter `word_editor` 接收已协商的低频视图命令，按**实际画布视口**计算页宽或整页比例；`word-core` 的文档模型、分页和绘制命令不因缩放选择而改变。没有双页排列合同的“多页”和独立预览页的“分页预览”保留禁用状态。

## 同文档视觉对比

以下截图使用同一份 8 页 `sample2.docx`，在相同尺寸的 OpenMuse 窗口或 Android ARM64 模拟器上采集。旧版缩放组只有“缩小、放大”，新版补齐弹窗、100%、页宽与整页，并保留源码顺序。

| 0.1.17 Android 视图组 | 0.1.18 Android 视图组 |
| --- | --- |
| ![旧版 Android 视图组](evidence/0.1.18/before-android-view.png) | ![新版 Android 视图组](evidence/0.1.18/after-android-view.png) |

| 0.1.18 桌面视图功能区 | 0.1.18 桌面“整页” |
| --- | --- |
| ![桌面视图功能区](evidence/0.1.18/after-desktop-view-ribbon.png) | ![桌面整页缩放](evidence/0.1.18/after-desktop-fit-page.png) |

| 0.1.18 Android“100%” | 0.1.18 Android“整页” |
| --- | --- |
| ![Android 100% 缩放](evidence/0.1.18/after-android-zoom100.png) | ![Android 整页缩放](evidence/0.1.18/after-android-fit-page.png) |

[Android 缩放组完整横向轨迹](evidence/0.1.18/after-android-zoom-ribbon.png)显示源顺序的七个入口；[缩放弹窗](evidence/0.1.18/after-android-zoom-dialog.png)显示“页宽”和“整页”已可选，“文字宽度”和“多页”明确禁用。状态栏从 100% 返回 43%，文档仍为 8 页、5654 字。

## 验证与剩余差距

[一键流水线](evidence/0.1.18/stack-report.json)的 18 个阶段和 8 个桌面端到端用例全部通过。[DOCX 渲染记录](evidence/0.1.18/render-evidence.json)、[封包哈希](evidence/0.1.18/package-verification.json)和[平台验证](evidence/0.1.18/platform-verification.json)记录了签名产品包、两端原生内核、离线安装和截图校验。打包后的 macOS 应用打开文档得到 8 页、187 条绘制命令；DSH 面板返回 HTTP 200 并加载完成。关闭 Wi-Fi 和蜂窝数据的 Android ARM64 模拟器打开同一文档得到 8 页、5654 字，并验证 100% 与整页缩放切换。

| 人工验证包 | SHA-256 |
| --- | --- |
| [macOS Debug ZIP](../../../../Muse-Client/dist/OpenMuse-word-0.1.18-macos-debug.zip) | `31c33b2f1c6e7c56e94e1d8e95d26221f5dac63d1a14819028ba9f908aabcb63` |
| [Android ARM64 Debug APK](../../../../Muse-Client/dist/OpenMuse-word-0.1.18-android-arm64-debug.apk) | `7bba0d892cf5663232c5513195e35acc0fa3797860950eac8ac71d12d7dbfbf9` |

两包内嵌 Word 产品包的 SHA-256 均为 `66958949457f8733809c50cac1ea87203de7283e51bba163a14b9148e9bb2fe5`。本轮使用开发测试签名，供本地人工验证。

“文字宽度”和“多页”还需要独立版式与多页排列；标尺、网格、导航、窗口组及上下文菜单也未整体完成。没有 GenOffice 同文档运行金图，本报告证明当前迭代的前后视觉变化，不宣称整套壳达到像素级 1:1。
