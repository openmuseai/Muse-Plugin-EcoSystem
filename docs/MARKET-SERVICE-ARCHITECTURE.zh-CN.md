# 独立插件市场服务：产品与技术方案

## 定位与边界

插件市场服务与 Muse-Server/AppFlowy-Cloud 平行部署，拥有独立域名、数据库、Redis、对象存储桶和发布流程。它不访问用户文档、Workspace、AppFlowy 的表或 Muse 私有插件字段。公开分发契约是 [MCP Registry](https://registry.modelcontextprotocol.io/)、[MCP Bundle](https://github.com/modelcontextprotocol/mcpb) 和 [MCP Apps](https://modelcontextprotocol.io/extensions/apps/overview)。管理 API 是服务自己的审核 API，不暴露给客户端。Desktop/Mobile/Web 可以用同一个 `namespace/name` 插件 ID，精确版本下选择标准交付字段：Desktop 选 MCPB/stdio，Mobile 可选已校验 MCPB 中的静态 Web/Wasm 站点或 Streamable HTTP，Web 选已声明的 MCP Apps UI。`web/` 站点目录是公开打包 profile，不是 MCPB 基础执行规范或客户端私有字段。

## 用户旅程

1. 开发者在公开兼容矩阵选择客户端版本，默认最新；使用独立 SDK/脚手架开发，运行 MCP 工具、资源和 Apps TCK。
2. 开发者按 SHA-256 上传 MCPB，提交标准 `server.json`。服务检查归属、语义版本、包清单/入口、体积、摘要与远程地址。版本一旦提交不可覆盖。
3. 审核员在后台看待审列表、包摘要、端点、版本、审核历史；批准、拒绝或填写下架原因。审核操作写入不可变审计事件。
4. 已批准版本出现在公开 Registry。Desktop 校验摘要后安装 MCPB；Android 可校验同一 MCPB 的 `fileSha256` 并安装包内静态站点，安装完成后应用内离线启动。需要远端工具的 Mobile 插件仍连接同一记录的 Streamable HTTP 端点；用户通过标准 MCP 工具和资源使用这些能力。
5. 下架版本即刻从发现目录和包下载入口消失，保留审计与已安装收据；已安装本地插件按 Host 原有卸载/禁用机制管理。重新上架须记录原因。

## 服务划分

| 组件 | 当前实现 | 正式部署要求 |
| --- | --- | --- |
| Registry API | Axum 0.7 + Tokio | 独立 HTTPS 域名、限流、访问日志 |
| 审核后台 | Askama 0.12 + 原生 JS/CSS | OIDC 登录、细粒度 reviewer 角色、双人复核策略 |
| 元数据 | SQLx 0.8，PostgreSQL；SQLite 开发模式 | 独立 PostgreSQL 集群/备份/迁移 |
| 包仓库 | S3 API；MinIO 本地模式；SHA-256 寻址 | 独立桶、版本化、生命周期管理、CDN |
| 限流 | Redis 0.25 | 独立 Redis 与失败监控 |
| 审核执行 | 手工审核 + 元数据/ZIP 校验 | 自动化恶意代码、许可证、依赖与 MCP TCK 扫描 |

表：`uploaded_packages` 记录哈希与大小；`market_versions` 记录不可变版本元数据及状态；`market_audit` 记录每次提交和审核动作。公开目录只读取 `approved`，每个 ID 默认输出最高语义版本。服务端不执行上传的 MCPB。包下载在返回对象存储字节前再次检查版本状态。

## 身份与隔离

当前本地试运行使用分别配置的 developer/reviewer Bearer token，并可限制开发者命名空间。正式环境必须接入**独立标准 OIDC**，使用 `issuer`/`audience`/JWKS 验证访问令牌，授权记录保存在市场自己的数据库；开发者只可提交其拥有的 namespace，审核员才可调用 `/internal`。前端需使用 HTTP-only SameSite 会话与 CSRF 防护。服务端不得复用 Muse-Server/AppFlowy-Cloud 的数据库、内部 token 或用户 profile。上传、审核与下载均记录可追溯 actor、时间、版本及摘要。

## 版本、撤回与兼容

插件 ID 跨端共用，版本与内容摘要不可变。分发目标由 MCP Registry 的 `packages` 与 `remotes` 标准字段给出；MCP Apps 工具使用 `_meta.ui.resourceUri` 引用 `ui://` HTML 资源。客户端声明支持的 MCP/MCP Apps 版本，市场执行对应 TCK；不支持的交付方式在该端不显示或不可安装。下架隐藏新安装并拒绝公开包下载，不强删用户已安装的文件。恶意内容需单独的撤回公告与 Host 本地阻断机制。

## 后台 UI

按 taste-skill 的 minimalist-ui 约束使用暖白底、木炭色文字、细边框、低饱和状态色、紧凑导航和克制动效。审核员先看状态与数量，再看提交表；详情抽屉汇集摘要、远程端点、包哈希和操作。拒绝/下架必须输入原因。键盘焦点明显，移动宽度下导航收窄且表格可横向滚动，遵守减少动态效果设置。

## 当前验收与差距

已实现本地端到端审核流以及 PostgreSQL/MinIO/Redis 形态验证，AppFlowy Editor 的标准 MCPB、远程 MCP 和 Web 编辑器可运行。当前仍是可验证的试运行服务：缺少正式 OIDC、多开发者 namespace 管理、扫描与审核策略、正式 HTTPS 部署、CDN、签名与持续兼容 TCK。生产开放上传前应把这些列为发布门槛。
