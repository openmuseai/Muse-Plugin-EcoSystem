# Word 壳层 0.1.20：GenOffice 多页视图

## 源码与边界

GenOffice 的 [`ViewTab`](../../genoffice-pptx/vendor/genoffice/apps/docs/src/renderer/components/ribbon-tabs.tsx) 将“多页”放在“缩放”组末尾；[`App.tsx`](../../genoffice-pptx/vendor/genoffice/apps/docs/src/renderer/App.tsx) 的 `zoomFit('multi')` 保存多页排列模式，先按整页高度计算缩放，放不下两列时改为双列宽度；[`multipage.ts`](../../genoffice-pptx/vendor/genoffice/apps/docs/src/renderer/multipage.ts) 随视口宽度与当前缩放计算列数，手动缩放后仍保留多页排列，页宽/整页则回到单列。

本轮在已签名 Word 产品资源包中增加低频 `word.view.fitMultiplePages` 命令并启用原有图标。Flutter `word_editor` 保存视图状态，按当前 `word-core` 页宽和视口将同一批页面绘制命令排成网格；页码导航按行定位，并保留右侧活动页。为保证小屏文字可读，宽度小于 600px 时保留“多页”选择但采用单列。`word-core` 仍是唯一文档模型和排版内核，插件不进入输入或逐字排版路径。

## 同文档、同窗口视觉对比

下面均使用 `sample2.docx`（8 页、5654 字），桌面窗口为 1365×860。左图是 0.1.19 的“整页”，右图是本轮“多页”；两图均为 60% 缩放，第 1 页内容相同。页面由一列变为两列；Ribbon 的“多页”高亮，底部状态栏保留页数、字数、视图和缩放控件。右图定位到第 2 页，状态栏显示第 2 页；测试还验证了滚动到第 4 页后不会误报第 3 页。

| 0.1.19：整页单列 | 0.1.20：多页双列 |
| --- | --- |
| ![单列基线](evidence/0.1.20/before-desktop-fit-page.png) | ![本轮双列](evidence/0.1.20/after-desktop-multiple-pages.png) |

同为 0.1.20 的[“整页”截图](evidence/0.1.20/after-desktop-fit-page.png)与上轮基线尺寸相同，平均每色彩通道绝对像素差约 0.016/255，说明未选择多页时原排版保持不变。[本轮完整视图 Ribbon](evidence/0.1.20/after-desktop-view-ribbon.png)可核对多级页签和组顺序。

390×844 的 Flutter 窄屏测试窗口中，用户仍可通过缩放对话框选“多页”；页面以单列呈现，未出现横向两页挤压或溢出：[窄屏截图](evidence/0.1.20/after-mobile-multiple-pages.png)。这张是桌面端 Flutter 窄窗口的测试截图，**不是 Android 设备截图**。

## 构建与验证

[一键流水线报告](evidence/0.1.20/stack-report.json)记录 20 个阶段和 8 个桌面端到端用例全部通过，包含签名安装、离线重开、原生编辑面与 DSH 面板。[渲染记录](evidence/0.1.20/render-evidence.json)确认真实 DOCX 为 8 页、187 条绘制命令；[桌面测试结果](evidence/0.1.20/desktop-e2e.json)包含双列与窄屏截图的生成路径。[macOS 包验证](evidence/0.1.20/package-verification.json)确认严格签名、ZIP CRC、归档内的产品包和原生库哈希；[封装后启动检查](evidence/0.1.20/packaged-smoke.json)确认文档渲染、DSH HTTP 200 和 WebView 加载。

| 人工验证包 | SHA-256 |
| --- | --- |
| [macOS Apple Silicon Debug ZIP](../../../../Muse-Client/dist/OpenMuse-word-0.1.20-macos-debug.zip) | `c8f43e5d5e5d2a3ed320625866dc58bf513692c5bd48bd87ae8f40fe0a6bdcbe` |

本包内嵌 SHA-256 为 `65b7cdf6fe94853cc417f4cfcff60937ad76d97e0a608762727ef3a95702538f` 的 0.1.20 签名 Word 产品资源包；使用开发测试密钥和临时签名，仅供本地人工验证。打开包后在 Word 中选择“视图 → 多页”可检查本轮行为。

## 仍需完成

本轮对照 GenOffice 源码行为及 OpenMuse 前后图；尚无同文档的 GenOffice 实际运行金图，**不能宣称整个壳像素级 1:1**。Web 版式、大纲、分页预览、深色页面、标尺、导航窗格和窗口操作仍待各自的状态/能力合同及视觉验收。共享工作树中的 `core_libs_kfc_main` 原生字符表目前为未入库生成文件；干净环境的一键构建应先把该表生成纳入上游构建流程。
