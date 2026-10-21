# Android PPTX 讲解验收记录

## 当前结论

**部分通过，最终版本完整真机闭环待完成。** 生产已发布文档讲解 0.2.1 与 GenOffice PPTX 0.7.1；最终 Android APK 已安装，设备拉取包与发行包摘要一致。当前镜像自动化无法读取 Android Studio 窗口，连续返回 `timeoutReached`；ADB 仍在线。尚未通过最终包界面安装讲解 0.2.1，不将旧版本截图作为新版验收。

用户确认解锁并显示镜像后仍超时。诊断时 Android Studio 约占用 1122% CPU、13.1 GB RSS，系统空闲内存 79%；JVM attach 也在 10.5 秒后超时。已请求手动重启 Studio。尚未获得线程栈，因此不能断言具体由索引或 GC 引起。

重启后曾恢复 AX 和镜像，市场仍显示 0.2.1「安装」。坐标点击连续返回 `windowNotFoundAtPosition`，Raise 与 Window 菜单激活均未修复；Studio 自动恢复 Android 工程和 Gradle 导入后 AX 又出现超时。没有一次成功的安装点击，因此最终版本安装/浮窗验收仍保持待完成。

## 版本与构建

- Client：`cbd243e35446dbded217d7c1676128d2c5c5af41`，分支 `feat/document-explainer-live`。
- 完整 APK：`Muse-Client/dist/OpenMuse-Android-arm64.apk`，SHA-256 `bfb7cf0aed6fe9a622ff8c4a25e753d9e00823457de4ae78267c1dd568b48b2d`。
- 手机：OPPO PKM110 / API 36；使用已有登录和配对数据，没有清除用户数据。
- 生产插件版本与摘要见 [production-catalog.json](production-catalog.json)。
- 0.7.1 的渲染 HTML 与 0.7.0 完全相同，见 [pptx-renderer-identity.json](pptx-renderer-identity.json)。本次没有改写上游 PPTX 引擎。

## 已观察到的真机行为

| 证据 | 证明范围 | 限制 |
| --- | --- | --- |
| [01](01-pptx071-production-installed.png) | 手机从生产市场安装 GenOffice 0.7.1，显示本机文件能力 | 未证明所有 PPTX 布局无差异 |
| [02](02-pptx-live-dsh-narration.png) | 23 页 PPTX 在原版编辑器中显示，浮窗有真实 DSH 输出和逐页进度 | 讲解插件为 0.2.0，启动含人工操作 |
| [03](03-paused-page9.png) | 页 9 显示「已暂停 / 继续」 | 后续存在并发人工操作，未证明暂停后持续不翻页 |

已观察过浮窗缩小；最终包中连续、独占控制的缩小/展开/关闭验收仍需完成。

## 自动验证

| 检查 | 结果 | 实际覆盖 |
| --- | --- | --- |
| [离线发行包发现](offline-artifact-tests.log) | 2 passed | 校验正式 PPTX MCPB、离线 App 发现、扩展与文件处理器分离 |
| [全局层 Widget](floating-widget-tests.log) | 1 passed | 跨路由、缩小/展开保留同一 Flutter State，关闭仅撤销自己的调用者；不替代 Android 原生 View 实测 |
| [DSH 适配器](dsh-adapter-tests.log) | 1 passed | 合成 HTTP/SSE 的任务归属、忽略历史、会话复用和清理；不是真实模型证据 |
| [通用资源路由](shared-router-tests.log) | 4 passed | 当前资源、不可变包工具允许列表、令牌/来源边界 |
| [讲解状态机](narrator-tests.log) | 3 passed | 逐页流程、暂停取消、失活处理 |
| [Mobile 分析](mobile-analyze.log) / [Host 分析](host-analyze.log) | 无问题 | Dart 静态分析 |
| [taste lint](taste-lint.log) | 0 FAIL / 0 WARN | 源码样式规则；最终真机视觉仍需复验 |
| 完整 Android 构建 | passed | Rust 原生库、Flutter release、签名与平台门禁；见 [构建信息](android-build-info.txt) |

## 接续验收清单

1. 保持 Mac 解锁，Android Studio 的 Running Devices 镜像在当前桌面。手机生产市场搜索「PPTX」，安装文档讲解 0.2.1，保存版本与安装证据。
2. 工作台 → Workspace 文件 → explainer → live-narration-acceptance → Sample_ppt.pptx。该文件是原始样例的已有副本，摘要见 [verification.json](verification.json)。旧 `assets` 挂载指向的 `/Users/mac/src/ioffice/...` 当前不存在，避免将路径失效误判成插件失败。
3. 从第一页启动，完成当前文档与 Agent 协作授权；若出现 DSH Workspace 选择，选择本次测试工作区。核对 DSH 真实输入、输出与页码。
4. 暂停，记录页码，独占控制等待至少 15 秒，确认迟到输出不会继续翻页。缩小、展开后保持同一页和输出，不重载编辑器。
5. 继续，确认产生下一次真实输出。停止后切到非第一页，选择「从当前页」，核对提示词与当前页一致。
6. 任务运行时关闭浮窗，确认取消自己的任务，编辑器仍在、不继续翻页。用编辑页「显示插件扩展」重新打开，新浮窗空闲且编辑器页码保持。
7. 返回工作台，确认浮窗属于应用全局层；文档关闭后浮窗失活，不能再发起翻页。缩小、展开、关闭均不影响工作台导航。
8. 补充最终版本截图、更新时间和验证状态，再将最终真机项标为 passed。

PDF 真机验收按用户要求暂缓。Desktop DSH 黑屏尚未独立定位；本次移除通用工具路由改变 DSH 可见性的副作用，不等于已修复黑屏。
