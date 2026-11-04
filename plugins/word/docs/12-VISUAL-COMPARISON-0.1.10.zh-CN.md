# Word 壳层 0.1.10：封面图库视觉对比

本轮以 0.1.9 为基线，针对 GenOffice `apps/docs/src/renderer/editor/cover-pages.ts` 的 12 个 `COVER_PRESETS` 和 `components/ribbon-insert-tab.tsx` 的 `CoverThumb` 完成一个可逐项验收的壳层销项。两张图库截图均由同一 Flutter 测试窗口生成，尺寸 520×550，字体相同。它们比较的是 OpenMuse 前后实现；尚无同条件运行的 GenOffice 金图。

| 0.1.9 通用缩略图 | 0.1.10 源预设缩略图 |
| --- | --- |
| ![旧封面图库](evidence/0.1.10/before-0.1.9-cover-gallery.png) | ![新封面图库](evidence/0.1.10/after-0.1.10-cover-gallery.png) |

按 RGB 单通道差值大于 12 判定，两图有 31,557 / 286,000 像素变化（11.03%）。之前 12 个条目几乎共用同一“文档标题/副标题/作者”框架；现在经典、色带、边框、侧线、现代、优雅、极简、深色块、强调色、徽标、切面、年度报告各自显示源码定义的段落布局。变化量只证明实现前后的区别，不是对 GenOffice 的相似度评分。

同轮 macOS Host 端到端测试在原生 Flutter Word 窗口中打开“插入 → 封面”，中央仍显示由 `word-core` 排版的 8 页 DOCX，底部状态栏保留页码和缩放：

![macOS 原生 Word 壳与封面图库](evidence/0.1.10/after-0.1.10-desktop-cover-in-shell.png)

## 模型与边界

- `scripts/sync-cover-previews.mjs` 从 GenOffice 源码提取封面段落数据，检查 12 个 ID 与插件菜单顺序一致，生成 `menus.json` 中的 `previewParas`；`npm run audit:cover-previews` 在流水线复算数据并检查未过期。日期和年份以 `{date}`、`{year}` 占位，运行时由 Flutter 本地化为当天显示，不使签名包每天变化。
- 插件验证器限制段落字段、长度、颜色、间距、边框与数量，并要求 12 个封面卡片都带有效预览。Host 对 `menus.json` 一并验签；Flutter `WordCoverPreviewParagraph` 为不可变展示模型，只绘制 88×116 缩略页，不访问 DOCX 正文或第二文档树。
- 桌面封面卡片采用源码的四列、104px 卡片宽、8px 间距和 88×116 纸页；触屏按可用宽度重排为 1–4 列，手机三列、窄屏两列，四列不再藏在无提示的横向滚动区。原有中间编辑区、`word-core` 排版与底部状态栏保持同一职责边界。
- 封面插入命令仍受 Host/内核能力门禁控制；预览可见不表示已支持插入封面。

## 构建与验证

一键桌面流水线 `npm run stack:e2e -- --platform desktop --scope render --suite quick` 最终运行 ID 为 `2026-10-23T06-39-33-439Z-66d6c14a`。插件资源、62 个源码下拉入口、63 棵菜单树、封面源数据审计、Rust FFI、Flutter 组件、macOS 原生 Host 构建、DOCX 渲染、离线重开、嵌入/独立窗口和 DSH 面板检查通过。测试公钥是本地验收用途。

macOS 和 Android 交付包、摘要及设备验证明细见[平台验证清单](evidence/0.1.10/platform-verification.json)；[流水线报告](evidence/0.1.10/stack-report.json)和[桌面端到端用例](evidence/0.1.10/desktop-e2e.json)也随本轮证据保存。

Android ARM64 模拟器关闭网络后用系统文件选择器打开 8 页 DOCX，文档正文、Ribbon 与页码/缩放状态可见：

![Android 离线打开 DOCX](evidence/0.1.10/after-0.1.10-android-open.png)

打开“插入 → 封面”后，手机显示三列；向上滚动可看到最后三张预设和“删除当前封面”入口，证明 12 张卡片均可触达：

| 封面图库首屏 | 向上滚动后 |
| --- | --- |
| ![Android 封面图库首屏](evidence/0.1.10/after-0.1.10-android-cover.png) | ![Android 封面图库底部](evidence/0.1.10/after-0.1.10-android-cover-scroll.png) |

## 未完成的 1:1 项

顶部其它图库（样式、艺术字、公式）尚待同等级别的源数据视觉销项；菜单 hover、focus、pressed 与动态状态仍需对照 GenOffice 运行画面。中央文档内容的排版保真需用独立 DOCX 金文件验收，不能由封面缩略图证明。
