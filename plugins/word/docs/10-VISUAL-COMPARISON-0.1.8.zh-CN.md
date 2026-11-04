# Word 壳层 0.1.8 视觉对比与验收记录

本轮基线为 OpenMuse Word 产品插件 0.1.7；参照对象为 `plugins/genoffice-pptx/vendor/genoffice/apps/docs/src/renderer` 中的 `styles.css`、`App.tsx` 和 `components/ZoomDialog.tsx`。两张桌面截图均为 1365×860、中文、浅色、同一 8 页 DOCX 和同一原生 Flutter 测试窗口。**下图是 OpenMuse 迭代前后对比，不是 GenOffice 运行截图，也不构成像素级 1:1 通过证明。**

| 0.1.7 交付基线 | 0.1.8 本轮实现 |
| --- | --- |
| ![0.1.7 桌面壳](evidence/0.1.8/before-0.1.7-desktop.png) | ![0.1.8 桌面壳](evidence/0.1.8/after-0.1.8-desktop.png) |

| 对照项 | GenOffice 源码证据 | 0.1.8 结果 |
| --- | --- | --- |
| 顶部标签与 Ribbon | `styles.css` `.ribbon-tabs`、`.ribbon-body`：36px 标签行、80px 主带、底部预留 5px 横向滚动轨道 | 尺寸保持；Flutter Ribbon 加底部滚动轨道，窄窗仍可横向到达后续控件。菜单树继续由签名 `ribbon.json`、`menus.json` 声明，非 Word 正文模型 |
| 中央纸页 | `styles.css` `.editor-scroll`：`26px 24px 140px`；`.doc-page` 使用两层阴影 | 工作区水平内边距改为 24px，纸页边缘从明显描边改为双层柔和阴影；页内容仍由 `word-core` 输出，壳资源不解释正文 |
| 底部状态栏 | `styles.css` `.status-bar`：24px；`.zoom-slider`：110px；`App.tsx` 百分比可打开缩放弹窗 | 24px 带和 110px 滑杆保留；缩小滑块，百分比可打开弹窗；最小/最大/步长/预设由已签名 `chrome.json` 提供 |
| 缩放弹窗 | `ZoomDialog.tsx`：200%、100%、75%，页宽、文字宽度、整页、多页，百分比框 10–500% | 原生 Flutter 弹窗按相同选项顺序、两列结构和 380px 最大宽度绘制；10–500% 数值缩放可用。四种适配模式缺少编辑表面计算合同，显示为不可用，避免错误操作 |

![0.1.8 桌面缩放弹窗](evidence/0.1.8/after-0.1.8-zoom.png)

Android API 34 ARM64 模拟器安装本轮 APK，关闭网络后经系统文件选择器打开本地 `complex-sample.docx`。纸页渲染、状态栏显示“第 1 页，共 28 页”；点击 43% 出现同一 Flutter 缩放弹窗，选择 100% 后页面和状态值同步变化。

| Android 本地 DOCX 打开 | Android 缩放弹窗 |
| --- | --- |
| ![Android DOCX 渲染](evidence/0.1.8/after-0.1.8-android-open.png) | ![Android 缩放弹窗](evidence/0.1.8/after-0.1.8-android-zoom.png) |

流水线报告：`../../../.word-stack-runs/2026-10-22T17-47-33-453Z-66d6c14a/report.json`（相对于本文档）。它记录插件 0.1.8、`word_editor` 0.4.4、签名包 SHA-256、Rust/Flutter 测试、macOS 原生 Host 构建、DOCX 打开、离线重开、内嵌窗口及 DSH 面板。测试公钥只用于本地验证，不是市场发布密钥。

打包验收记录：`../../../.word-stack-runs/2026-10-22T17-47-33-453Z-66d6c14a/platform-verification.json`。交付 `Muse-Client/dist/OpenMuse-word-0.1.8-macos-debug.zip` 与 Android Debug APK；两者均内置 SHA-256 为 `0426d631aabe3ae11c261f4f646ccec3e3e9ff7d189295ace42e5e701353577b` 的同一 Word 资源包。Mac 深度签名与版本化 ZIP 完整性通过，APK 包含 ARM64 `libword_core_ffi.so`。共享文件名 `OpenMuse-macos.zip` 被并行构建覆盖，不能用作本轮交付。

## 尚未对齐

- Ribbon 的部分图标仍是 Material 替代，颜色、图形细节、hover/pressed/focus 与 GenOffice 尚未逐像素核对。
- 63 棵菜单树的入口与层级已对照源码，但封面/样式缩略图、公式 MathML 预览和动态最近项目尚未逐项复刻。
- 页宽、文字宽度、整页、多页缩放以及字数、修订、选区格式等能力，等待 `word_editor`/内核快照合同；资源中的无效命令保持禁用。
- 本轮没有从同一版本 GenOffice 运行环境取得 1365×860 参考金图，因此目前只能确认源码几何与 OpenMuse 前后变化；后续应补 GenOffice 原生截图并做区域差异图、偏差阈值和逐控件销项。

下一轮按 [开发计划](07-GENOFFICE-CHROME-PLAN.zh-CN.md) 的 G2/G3 继续处理图标、图库、状态与多级菜单视觉，保持产品资源包与 Host 内置 Flutter 编辑面之间的责任边界。
