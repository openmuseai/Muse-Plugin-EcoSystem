# OpenMuse PDF 产品插件

本目录交付 **PDF 产品插件** 的已签名资源包：七个 GenOffice PDF Ribbon 标签、83 个控件、转换/排列/缩略图菜单、70 色 Office 色板、状态栏/侧栏样式、命令目录与功能开关。它与已有的 [`pdf-reader`](../pdf-reader/README.zh-CN.md) 不同：后者是 PDF.js MCP 阅读能力 Provider；本产品的页面绘制与编辑使用 `ioffice` 的 PDFium 产品会话。OpenMuse Desktop/Mobile Host 验签后加载此包，PDF 编辑器源码和内核随 Host 发布。

本地快速验证：在三仓并列的工作区执行 `bash Muse-Plugin-Ecosystem/plugins/pdf-product/scripts/quick-verify.sh macos`；Android 使用 `android`，两端使用 `all`。脚本在用户目录保存本地测试密钥，生成 `.mcpb`，验证资源与签名，编译产品内核和 Host，运行已有端到端测试，macOS 路径还会自动截取七个标签、色板、菜单及平板/手机视口，并在 `dist/quick-verify-<platform>.json` 记录阶段结果、版本、产物与截图摘要。设置 `ANDROID_SERIAL` 才会把本地测试签名 APK 安装到指定设备。正式发布必须使用发行密钥和完整验收门禁。

最新 `0.1.18` 交付补齐桌面抽页结果的新标签导航；[视觉与行为对照](../../../Muse-Client/dist/pdf-product-evidence-0.1.18/VISUAL-COMPARISON.md)和[双端交付报告](../../../Muse-Client/dist/pdf-product-evidence-0.1.18/delivery-report.json)包含真实 PDF、macOS/Android 产物及截图证据。完整同条件逐像素 1:1 仍按开发计划继续验收。

- [架构、边界和合同](docs/01-ARCHITECTURE.zh-CN.md)
- [GenOffice PDF 壳逐区台账](docs/02-GENOFFICE-CHROME-INVENTORY.zh-CN.md)
- [阶段开发、联合验证与发布计划](docs/03-DEVELOPMENT-PLAN.zh-CN.md)
- [逐轮视觉对齐与截图证据](docs/04-VISUAL-PARITY-ROUNDS.zh-CN.md)

代码归属：`ioffice/koffice/pdf/rebuild/pdf-rebuild` 保留 PDFium/C++ 内核与版本化 C ABI；`ioffice/koffice/pdf/rebuild/pdf-flutter-app` 是 Desktop/Mobile 共用的 Flutter PDF 表面；`Muse-Client` 负责窗口、资源授权、可信安装和文件提交；本插件只交付 Ribbon/菜单/主题/命令目录/功能开关及显式低频扩展。尚未实现的业务能力保持禁用。
