# Word 首版双端渲染验证（2026-10-22）

## 交付边界

- `ioffice` 的 `word-core` 是文档解析和排版内核；`word_editor`、`word_render` 是 Host 内的 Flutter 编辑表面。Android Host 随包提供 arm64 Rust `.so`，macOS Host 提供 arm64/x86_64 通用动态库。
- `plugins/word` 只交付已签名的 Ribbon、菜单、状态栏、命令与资源。Host 验证 Ed25519 目录签名及每个资源摘要。产品版本是 `0.1.2`；内核和画布不在 `.mcpb` 内。
- 本次验收范围是**只读打开和渲染**。保存、编辑、在线协作、生产密钥分发以及 GenOffice 壳的逐像素 1:1 仍由既定 G2–G5/M1 计划推进。

## 本次故障与修复

Android 截图中的 `Word 功能包安装失败：FormatException: Word product archive invalid` 来自拼图图标的 `.mcpb` 安装流程，说明被选择的文件不是合法 Word 产品包；DOCX 尚未送给内核。实机复核发现 ColorOS 文件选择器会忽略调用方传入的 `.mcpb` 扩展名筛选，甚至列出 PNG。现在手机标题栏提供独立的文件夹“打开 DOCX 文档”入口，空工作区也提供同名按钮；拼图入口保留为“安装已签名 Word 功能包”，会在解析前拒绝非 `.mcpb` 文件并提示使用文档入口。真机选取 PNG 后，已验证出现这条明确提示。macOS 打包还修复了 `archive` 3.6 与 4.x 对 ZIP 查找方法的 API 差异，统一使用经路径及大小校验的文件索引。

## 实测结果

| 平台 | 验证路径 | 结果 |
| --- | --- | --- |
| Android 16 / PKM110 / arm64 | 独立包名 Release QA 应用 → Word 文档 → 系统文件选择器 → `sample3.docx` | 真实 Rust/Flutter 链路绘制 1 页表格，状态栏显示“第 1 页，共 1 页”；标题栏两个入口区分明确 |
| macOS Debug / arm64 | 原生 OpenMuse → 签名产品资源 → `sample2.docx` | 8 页、187 绘制命令；同一窗口 DSH WebView HTTP 200、加载并显示 Agent 输入区 |
| macOS Release / 通用架构 | 启动正式构建 → 匿名工作台 → DSH 面板 | 不再停留于黑屏；DSH 页面显示并可跳过可选密钥配置；通用 Word 动态库含 arm64 和 x86_64，整包 `codesign --verify --deep --strict` 通过 |

桌面端 `word_product_e2e_test.dart` 同时通过签名 MCPB 加载、安装收据、能力路由、原生打开/渲染与离线重开。移动端签名包及全部常规 Ribbon 标签测试通过，目标文件静态检查通过。

## 本地产物

标准 Android Release APK：`Muse-Client/dist/OpenMuse-android-arm64-release.apk`。macOS 通用应用：`Muse-Client/app/openmuse_host/build/macos/Build/Products/Release/OpenMuse.app`；压缩包：`Muse-Client/dist/OpenMuse-macos.zip`。Android 真机使用同一 Release 配置、附加 `.wordqa` 包名的 `Muse-Client/dist/OpenMuse-android-arm64-wordqa-release.apk`，以保留设备上原有不同签名的 OpenMuse。两份 Android 包目前均由本地 QA 密钥签名，尚非市场发行包。

截图与 SHA-256 清单在 `Muse-Client/dist/word-validation/report.json`。重新验收时对比该清单以及当前三仓提交/源码指纹；发行构建需要重新签名和生成新的报告。

## 下一轮门禁

1. 把 Android 设备安装、签名包校验、文件选择、页数和截图自动写入 `word:e2e --platform android --scope render` 报告；当前编排器仍只允许 Desktop `render`，不能把本次人工步骤误报为自动钩子通过。
2. 在 G2–G5 逐项核对 63 棵菜单、四档响应式布局、上下文页签、选区状态和状态栏。当前常规标签、递归菜单结构已就绪，但视觉和命令能力尚未全部完成。
3. `word-core` 完成 DOCX 保存、编辑及保真后，运行 M01 的 Android 断网编辑、杀进程、保存重开；再推进 iOS 与 Web 的对应验证。
