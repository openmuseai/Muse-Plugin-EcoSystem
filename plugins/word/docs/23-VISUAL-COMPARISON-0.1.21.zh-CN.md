# Word 壳层 0.1.21：GenOffice 深色页面

## 本轮源码对照与实现

GenOffice 的 [`ViewTab`](../../genoffice-pptx/vendor/genoffice/apps/docs/src/renderer/components/ribbon-tabs.tsx) 将“深色模式”放在“视图 → 外观”组；[`dark-page.ts`](../../genoffice-pptx/vendor/genoffice/apps/docs/src/renderer/editor/dark-page.ts) 用色彩矩阵仅对屏幕上的文档颜色做反转和压缩，纸张色为 `#1e1e1e`，工作区为 `#3d3d3d`。原始文档颜色保留，打印与文件模型不变，图片不反转。

本轮启用签名插件资源中的 `word.view.darkMode` 低频视图命令。`word_editor` 持有开关与响应式画布，`word_render` 在绘制文字、矩形和线条时使用 GenOffice 的色彩矩阵；`word-core` 的文档模型、页面布局和绘制命令仍为唯一真源。插件只包含菜单与命令声明，不执行逐字输入或排版。`word_render` 0.1.2、`word_editor` 0.4.17、产品插件 0.1.21 由兼容性清单约束。

## 同文档视觉对比

以下两图都来自本轮桌面端到端测试，同为 `sample2.docx` 第 2 页，1365×860、166% 缩放，Ribbon 与状态栏位置相同。切换后纸张由白变为 `#1e1e1e`，工作区变为 `#3d3d3d`，黑色正文成为浅色；深色按钮显示选中态。文档仍为 8 页、187 条绘制命令、5654 字。

| 深色模式关闭 | 深色模式打开 |
| --- | --- |
| ![白色页面](evidence/0.1.21/light.png) | ![深色页面](evidence/0.1.21/dark.png) |

两张 1365×860 截图有 984386 个像素发生变化，平均每色彩通道绝对差为 184.58/255；这是画布和正文的大范围色彩切换，不能作为与 GenOffice 的像素误差指标。Flutter 像素测试另行验证白纸/深色纸张分别为 `#ffffff`/`#1e1e1e`，黑色线条转浅色而原始命令未改。窄屏基线见[390×844 截图](evidence/0.1.21/mobile-width.png)，它是桌面 Flutter 的窄窗口截图，不是 Android 实机截图。

## 构建与验证

[一键流水线报告](evidence/0.1.21/stack-report.json)记录 20 个阶段和 8 个桌面端到端用例通过，包括插件资源审计、签名安装与离线重开、Rust FFI、Flutter、macOS Host、原生文档窗口、嵌入窗口及 DSH。[真实 DOCX 渲染证据](evidence/0.1.21/render-evidence.json)确认 8 页、187 条绘制命令；[端到端结果](evidence/0.1.21/desktop-e2e.json)包含各场景的签名和哈希。

[包验证](evidence/0.1.21/package-verification.json)确认 ZIP CRC、内嵌插件与源签名包字节一致、内嵌 Rust 动态库与封装后应用一致、macOS 严格代码签名通过。原生库在封装时重新签名，Mach-O 字节哈希因而与编译输出不同。[封装后启动检查](evidence/0.1.21/packaged-smoke.json)直接运行 `dist/OpenMuse.app`，确认 DOCX 渲染、DSH HTTP 200 与 WebView 加载。

| 人工验证包 | SHA-256 |
| --- | --- |
| [macOS Apple Silicon Debug ZIP](../../../../Muse-Client/dist/OpenMuse-word-0.1.21-macos-debug.zip) | `64431de0ba6b82f4e093c21d8ef32d8cdeb4c5f9649b0ebd6a2d6c8a17df23e6` |

解压后打开 `OpenMuse.app`，在 Word 中打开文档并选择“视图 → 深色模式”检查切换。此包使用开发测试密钥与临时签名，供本地人工验证。

## 后续差距

这一轮对照了 GenOffice 源码行为和 OpenMuse 同文档前后图；尚无**同文档、同窗口的 GenOffice 运行金图**，不能宣称完整壳层像素级 1:1。标尺、导航窗格、分页预览、Web 版式、大纲和窗口操作仍需要各自的内核只读快照或 Host 能力合同，再逐项完成命令、交互与视觉验收。共享工作树中的 `core_libs_kfc_main` 原生字符表仍是未入库的生成文件，干净环境应将生成过程纳入上游构建流程。
