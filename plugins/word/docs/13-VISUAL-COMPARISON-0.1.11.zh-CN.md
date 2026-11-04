# Word 壳层 0.1.11：艺术字图库视觉对比

本轮对照 GenOffice `packages/ui/src/wordart-presets.ts`、`apps/docs/src/renderer/components/ribbon-insert-tab.tsx` 和 `styles.css` 的“插入 → 艺术字”。源码定义 12 个共享预设，四列、44px 正方形卡片、5px 间距、26px Georgia 字形；每个卡片有独立的填充、粗斜体和可选的 1pt/1.5pt 描边。以下三图使用相同的 220×190 像素画布。左、中两图是同一 Flutter 测试窗口前后版本；右图是从上述源规则构造的独立 HTML/CSS 参考，**不是 GenOffice 应用运行截图**。

| 0.1.10 Flutter | 0.1.11 Flutter | GenOffice 源规则参考 |
| --- | --- | --- |
| ![旧艺术字图库](evidence/0.1.11/before-0.1.10-wordart-gallery.png) | ![新艺术字图库](evidence/0.1.11/after-0.1.11-wordart-gallery.png) | ![源码 CSS 参考](evidence/0.1.11/source-css-wordart-reference.png) |

旧版只改变了普通“艺”字的填充，白色填充卡片在白底上不可辨。新版使用源预设的描边颜色/宽度、粗体和斜体。HTML/CSS 参考保存在[可检查的源规则页面](evidence/0.1.11/source-css-wordart-reference.html)。两端的字形光栅化和边框色仍受 Flutter/Chrome 的字体与渲染差异影响；这组截图用于逐项视觉核对，不声称像素级一致。

同轮 macOS Host 测试在原生 Word 窗口中打开 8 页 DOCX，再打开艺术字弹层。测试最初暴露 Host 中文字体未进入预览回退链，方框字形已修复；下图是修复后重新通过的端到端截图：

![macOS Word 壳与艺术字弹层](evidence/0.1.11/after-0.1.11-desktop-wordart-in-shell.png)

Android API 34 ARM64 模拟器在关闭 Wi-Fi 与移动数据后，从本地文件打开同一份 8 页 DOCX。第一张展示顶部多级 Ribbon、中间页面与底部状态栏；第二张展示“插入 → 艺术字”的触控弹层及全部 12 个预设。触控弹层采用小屏布局，因而不会与 GenOffice 桌面浮层像素一致。

| Android 离线打开文档 | Android 艺术字弹层 |
| --- | --- |
| ![Android 文档页面与状态栏](evidence/0.1.11/after-0.1.11-android-open.png) | ![Android 艺术字触控弹层](evidence/0.1.11/after-0.1.11-android-wordart.png) |

## 模型与边界

- `scripts/sync-wordart-previews.mjs` 读取共享 `WORDART_PRESETS`，按 ID、顺序和填充色核对 12 张插件卡片，再生成签名 `previewWordArt`。`npm run audit:wordart-previews` 在一键流水线复算并拒绝源数据漂移。
- 插件验证器把预览结构限制为填充、粗斜体和可选描边，检查描边色与 EMU 宽度。`word_editor` 通过不可变的 `WordArtPreviewStyle` 绘制字形。旧签名包未提供该字段时保留旧预览回退。
- 预览只读取产品资源；`word-core` 是唯一文档模型与排版内核。艺术字插入命令仍由 Host 能力门禁决定，预览可见不代表插入能力已启用。中间文档区与底部状态栏不被菜单数据重绘逻辑接管。

## 构建与验证

最终桌面流水线 `npm run stack:e2e -- --platform desktop --scope render --suite quick` 运行 ID 为 `2026-10-23T07-01-43-586Z-66d6c14a`，插件源审计、签名测试、Rust FFI、Flutter、macOS 构建、DOCX 渲染、离线重开、独立/嵌入窗口和 DSH 面板检查通过。macOS Debug ZIP、Android Debug APK、包内签名资源摘要与设备截图记录在[平台验证清单](evidence/0.1.11/platform-verification.json)。同轮保存[流水线报告](evidence/0.1.11/stack-report.json)和[桌面端到端用例](evidence/0.1.11/desktop-e2e.json)。

两个安装包都内置同一份 0.1.11 签名插件。macOS ZIP 通过 `codesign --verify --deep --strict` 和压缩包校验；Android Debug APK 已安装于上述模拟器并完成本地文档打开、页面渲染与艺术字弹层检查。签名密钥是该轮流水线生成的开发测试密钥，交付给人工验证使用，不作为市场正式发布签名。

## 后续 1:1 销项

GenOffice 的“开始 → 样式”不是固定六项，它按文档样式表、使用情况、选区和默认字体动态生成。后续需要由 `word-core`/Host 提供只读样式与选区快照，插件只声明图库布局和命令入口，再逐项做源运行金图及键盘/触控轨迹对照。公式 MathML 预览、字体列表、最近颜色和上下文状态也仍待处理。
