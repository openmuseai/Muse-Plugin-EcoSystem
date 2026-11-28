# GenOffice PPTX 拆分与适配

上游固定提交与许可见 [`plugins/genoffice-pptx/UPSTREAM-NOTICE`](../plugins/genoffice-pptx/UPSTREAM-NOTICE)。拆分只带入 PPTX 引擎及其必要依赖，不带 Electron/React/Konva 主界面。`pptx-engine` 负责 OOXML ZIP、XML 解析与保存；依赖 Node 的文件、压缩与加密 API，因此无法把同一 bundle 直接交给 QuickJS。旧客户端私有 worker/Manifest 包装已移除。

当前 Desktop 插件把 GenOffice 引擎封装为标准 MCP `inspect_pptx` tool，参数由 JSON Schema 声明为 base64 PPTX 内容，返回 slide 数、页面元素数、大小和 SHA-256。服务端不读 Host 工作区路径。官方 MCP TypeScript SDK 负责 stdio 协议；标准 MCPB 装载该服务。独立 MCP 客户端与 Desktop Host 均用真实 5 页样本验证了调用。Engine roundtrip 另有回归测试，但没有向用户开放保存工具；目前不是完整图形编辑器。

Mobile 通过远端 MCP Streamable HTTP 调用同一 `inspect_pptx` tool，并读取 A2UI 资源；Android 真机安装、页面点击和 PPTX 调用已通过，当前 Host 显示结构化结果，尚未完整绘制 A2UI。若要求离线原生编辑，必须单独评估将 OOXML 核心移植到 Rust/WASM 或 Dart、字体与图片渲染、触控编辑、内存与电量预算；QuickJS 仅承载轻量脚本，不能充当 Node runtime。iOS 真机与应用商店政策仍待验证。Web 可选择远端 MCP + MCP Apps；复用原 Electron UI 需要隔离沙箱和适配，不是本轮完成项。
