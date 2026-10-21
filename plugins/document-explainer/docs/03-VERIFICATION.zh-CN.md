# Desktop 讲解插件：验收记录与继续入口

> 本文保留首轮 Desktop 验收快照；其中版本和阻塞状态属于当时记录。后续 Mobile 0.2.1 / PPTX 0.7.1 发布与 Android 验收见 [04-MOBILE](04-MOBILE.zh-CN.md)。用户已明确暂缓 PDF 真机验收，不能以此推定 PDF 已通过。Desktop DSH 黑屏也仍须单独定位。

## 当前结论

**完整端到端验收尚未完成。** macOS 原生 PPTX → DSH 已验证；PDF 原生流程、新修订最终包的原生复验，以及生成工程的双资料报告/`muse submit` 尚待完成。桌面工具两次确认 Mac 已锁屏，已请求用户手动解锁；不能把浏览器 PDF 测试或独立插件待审回执当成完整闭环通过。

## 已完成

- Client / Ecosystem 均在 `feat/document-explainer-live`；按模块细粒度提交，作者和提交者 Alexixixi。
- DSH 消失根因：持久布局缺少 DSH binding；补标题栏恢复入口，不重置文档/终端。原生新构建中 DSH 实际显示，布局恢复回归测试通过。
- 生产市场安装 DevKit 0.3.0，并在已有 explainer Workspace 使用 CLI 安装 PPTX 0.7.0、PDF 0.2.0；初始化 `live-narration-acceptance` 双能力工程，在应用终端修改 main.js，通过 muse check / muse dev，把消费者 UI 挂在原版 GenOffice 上。
- 原生观察到完整 23 页 DSH 输入/模型输出与同步导航；另由自动化显式验证「从当前页」第 23 页、暂停（DSH 显示已停止）、继续。23 页整轮的启动包含人工操作，不称作无人值守自动化启动。
- 首轮原生证据来自 Host `0b58d69`、DevKit 0.3.0 生成的候选 b8b986…，见 first-desktop-build-info.txt 和图片。后来修正当前页/下一页显示、交互授权超时、终端保留和资源工具声明，需要在最终版本复验，不能沿用旧截图宣称新二进制已经原生通过。
- Host 为通用 Resource Extensions v1 组合多个 sandbox iframe；讲解条、状态机、提示词在讲解插件；PPTX/PDF 工具在资源插件；DSH 私有 session/HTTP/SSE 适配在 DSH 插件。
- 原版 GenOffice 独立 MCP Apps 23 页渲染、实时页读取/导航、编辑/保存重开、冲突与撤销通过。本轮未提供上游 PNG 基准，不宣称零像素差异。
- PDF.js 独立 MCP Apps 两页渲染、文字和导航通过；原生 PDF + DSH 尚未验收。

## 最终产物与发布状态

| 产物 | 状态 |
| --- | --- |
| DevKit 0.3.3 | 已审核并在生产目录可见；包含 document-explainer 模板、交互超时修正和资源工具声明；尚待最终原生安装复验 |
| GenOffice PPTX 0.7.0 | 已审核，生产安装及原生讲解使用了该版 |
| PDF Reader 0.2.0 | 已审核、生产安装；独立浏览器测试通过 |
| Document Explainer 0.1.1 | 已上传，待审核 f46f0144-76db-46c7-b291-4c7dbb00bca2；公开包下载 404，不宣称上架 |
| macOS arm64 完整包 | Client `ba01981`，构建/分析/签名权限门禁通过；最终原生复验待解锁 |

包：`Muse-Client/dist/OpenMuse-macos.zip`。ZIP SHA-256：`73a44b231590c5b07d4d072f6da966822f975dc4421eb6b7ff9bdf9d53f50b3f`。运行程序必须使用 `app/openmuse_host/build/macos/Build/Products/Release/OpenMuse.app`，不要启动其他旧副本。精确 Host binary digest 与市场 SHA 见 [verification.json](evidence/2026-10-21-desktop/verification.json)。

## 修复的验收中问题

1. 隐藏终端后关闭最后文档会移除整个编辑器窗格，销毁终端和开发授权。现在已打开的终端保留其 Dock；回归测试确认隐藏前后的 State 为同一个对象。
2. 原授权窗口等待计入 120 秒 RPC 超时。DevKit 0.3.3 给安装/开发候选十分钟交互时间；新版 Host 对同一 SHA 复用原回执，替换变更后的候选时清理旧资源扩展，防止重试和四次上限阻断开发。
3. 等待下一页时计数提前加一。讲解插件分开记录当前显示页和下一待讲页。
4. 讲解不应获得编辑/保存权。不可变包在公开 resourceTools 中只声明读取与导航；Host 不解释工具业务字段，拒绝未声明的写入工具。Agent 本身仍遵循其已有权限设置，不能把资源路由允许列表称作 Agent 的无工具沙箱。

## 解锁后的继续步骤

1. 在最新完整 macOS 包中登录原账号，点标题栏 Agent 恢复入口，确认 DSH / 文件 / 终端保留。
2. 从生产市场更新 DevKit 0.3.3。在 `plugins/explainer/live-narration-acceptance` Workspace 新终端运行 `muse check`、`muse dev`。旧实验候选没有 resourceTools，必须用新 DevKit 重新打包。
3. PPTX 从当前第 23 页完成一次输出；开始/暂停/继续；在后续页间等待时核对计数；重复相同 muse dev 应复用 runRef，修改源码后只替换浮层。
4. 打开同一工程 `quarterly-brief.pdf`，使用 PDF Reader；从第一页开始，核对两页 DSH 输入/输出及导航。切换/关闭资源后不继续发送任务。
5. `muse report` 必须在同一候选内收集到 PPTX 与 PDF 的真实完成结果，才能 `muse pack` / `muse submit`。提交只进入待审核，不把本地旧 partial 报告修改成 passed。
6. 独立审核 Document Explainer 发行包；批准后通过原生市场安装正式插件，并关闭开发终端，确认正式插件仍能工作。测试卸载/禁用的撤权与浮层移除。当前不自动批准未完成原生验证的讲解发行包。

本批不声称语音播放、Mobile/Web、完整依赖图或公开 npm SDK 发布已完成。
