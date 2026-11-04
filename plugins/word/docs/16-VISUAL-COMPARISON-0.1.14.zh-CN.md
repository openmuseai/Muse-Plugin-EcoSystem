# Word 壳层 0.1.14：真实文档字数进入状态栏

本轮核对 GenOffice `apps/docs/src/renderer/App.tsx` 的状态栏与 `word-count.ts`：左侧依次为页码、文档或选区字数、修订状态；右侧是视图模式和缩放。其总字数在文档变化后以 400 毫秒节流更新，选区字数随选区变化。`styles.css` 为状态栏定义 24 像素高度、11.5 像素字体、12 像素水平内边距。我们在共用 Flutter 编辑面保持这些布局值，移除原先的“— 个字”占位，显示从 `word-core` 当前文档会话读取的字数。

## 视觉对比

两张桌面图均使用同一份 8 页 `sample2.docx`、1365×860 窗口和“开始”Ribbon。0.1.13 的状态栏只显示占位值；0.1.14 显示 `5654 个字`。页内容、Ribbon 与视图控件保持原有位置，便于直接比对。

| 0.1.13 | 0.1.14 |
| --- | --- |
| ![旧版桌面状态栏](evidence/0.1.14/before-desktop-home.png) | ![新版桌面状态栏](evidence/0.1.14/after-desktop-home.png) |

窄屏 Flutter 渲染采用同一插件定义和编辑面源码。375 逻辑像素以上显示总字数；更窄时优先保留页码与缩放，不让状态栏溢出。下图是 390 逻辑像素宽的自动化截图。

![新版窄屏状态栏](evidence/0.1.14/after-mobile-width.png)

Android ARM64 模拟器上关闭 Wi-Fi 和移动数据，从本地 Downloads 打开相同 DOCX。旧版状态栏只有页码与缩放；新版还显示 `5654 个字`，正文和 8 页分页可见。

| Android 0.1.13 | Android 0.1.14 |
| --- | --- |
| ![旧版 Android 文档](evidence/0.1.14/before-android-open.png) | ![新版 Android 文档](evidence/0.1.14/after-android-open.png) |

下图依据 GenOffice 源 CSS 独立重建，仅辅助对照尺寸和颜色；它不是 GenOffice 运行截图，也不能作为所有 Ribbon 菜单像素级一致的证明。

![GenOffice 源 CSS 局部参考](evidence/0.1.14/source-css-reference.png)

## 领域边界与更新路径

- `word-core` 仍是唯一文档模型。`WordStatistics` 从主文档文本绳读取指定半开区间，按 GenOffice 的中日韩字符与非亚洲词规则计数；不依赖插件或 Flutter，使用固定大小缓冲区扫描。Rust FFI 的 `WordSession.wordCount(start,end)` 只读当前会话。
- `word_render` 只转发只读查询。`word_editor` 保存展示值，在打开 DOCX 时取总数，编辑或选区变化后以 400 毫秒节流刷新。计数不进入排版和逐字输入的插件命令路径。
- 签名产品包的 `chrome.json` 提供总字数与选区字数文案；它不保存文档状态。Desktop、Android 使用同一版产品包和 Flutter 编辑面。桌面宽屏显示选区字数；小屏显示总字数。

## 验证与交付

[联合流水线报告](evidence/0.1.14/stack-report.json)记录 18 个阶段通过；[真实 DOCX 端到端证据](evidence/0.1.14/render-evidence.json)记录 8 页、187 条绘制命令与 5654 字。[桌面端到端清单](evidence/0.1.14/desktop-e2e.json)包含插件签名安装、离线重开、嵌入式原生窗口、Ribbon 和 DSH 验证。macOS 与 Android 的打包、离线启动及截图结果见[平台验证清单](evidence/0.1.14/platform-verification.json)。

本轮字数只覆盖主文档文本；页眉页脚、批注、域更新等与 GenOffice 的统计口径仍需对照。状态栏中的修订和视图按钮仍有未实现行为。Ribbon 的多级菜单在既有版本逐步接入，但本轮没有取得 GenOffice 同文档的实际运行截图，不能宣称整套壳已达 1:1。下一轮应补选区统计的端到端拖选证据、字数统计弹窗，以及逐菜单运行图对照。
