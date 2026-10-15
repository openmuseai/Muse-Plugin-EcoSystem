# 交付状态与后续门禁

| 能力 | 当前状态 | 下一门禁 |
| --- | --- | --- |
| 独立市场服务 | 本地可运行：上传、待审、批准/拒绝、公开目录、SHA-256 包 | OIDC、命名空间所有权、扫描、审计、Postgres/CDN、撤回 |
| PPTX Desktop | MCPB 已打包；官方 SDK、Host 在线下载与真实文件调用通过 | OS 沙箱、通用 UI 更完整、回滚与稳定性 |
| Desktop 插件市场 | 在线 MCP Registry 卡片、一键安装及 macOS GUI 集成测试通过 | 多 OS TCK、工具级授权 |
| Mobile | 标准 `remotes` 消费、远端 MCP 工具、A2UI 资源验证和安装记录已实现；Android 真机安装与调用通过 | iOS 真机 TCK、完整 A2UI 绘制、OAuth |
| Web | 标准协议和隔离方案 | Web Host 接入、CSP/OAuth/TCK |
| 手机 Agent Studio | 用户旅程与发布门禁设计 | 云端工作区、预览、导出、用户授权和审核台 |

本地验证命令及可复现步骤见仓库 README 和开发者指南。生产上线以服务身份、隔离、审核与移动设备矩阵为硬门禁；当前不宣称已公开部署或三端全部完成。
