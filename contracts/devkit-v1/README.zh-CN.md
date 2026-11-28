# OpenMuse capability profile v1（Desktop 内测）

本 Profile 是公开生态语义，不是 MCP 保留方法或 MCPB 私有字段。它通过标准 MCP Apps `tools/list`、`tools/call`、`resources/read` 承载。任何其他 Host 均可按相同合同实现；Provider 无需导入 OpenMuse 源码。

## Provider 发现

Provider 用普通 MCP 资源发布 `application/vnd.openmuse.capabilities+json`，内容为 `{ "profile": "openmuse-capabilities/1", "contracts": [...] }`。每项合同包含稳定 `id` URI、独立 `version`、说明、`mediaType`、业务 `operations` 到工具名称的映射，以及允许导出的 `tools`。工具完整输入输出 Schema 由 `tools/list` 提供。文件输入用 JSON Schema 的 `contentEncoding: base64`、`contentMediaType`。

当前 GenOffice Slides Read v1 与 PDF Read v1 只提供已授权文件的不可变只读快照，不表示正在编辑的未保存会话。业务语义、工具和输出均由各 Provider 维护。

## Host 通用工具

| 普通 MCP 工具 | 输入 / 输出 | 权限语义 |
| --- | --- | --- |
| `host_describe` | 无输入；实现版本、当前执行文件与 Flutter App 二进制的组合摘要、支持的 Profile | 显式记录当前测试构建，旧 Host 缺失时阻止调试 |
| `capabilities_list` | 无输入；已安装 Provider、精确版本/包摘要、合同、标准工具 Schema | 不提供代码、安装路径或 Agent token |
| `resources_choose` | 标题、MIME；不透明 ref、标题、大小、文件摘要 | 原生选择单份文件，只属于当前 View；内容不会送到消费者 |
| `capabilities_bind` | Provider ID、合同 ID、resourceRef、工具集；binding 与精确回执 | 原生授权提示；检查工具属于合同，文件 MIME 与 Schema 一致 |
| `capabilities_call` | binding、tool、arguments；原始 MCP tool result | 最末转发前检查帐号、绑定、Provider 摘要；Host 注入已授权文件内容；禁止覆盖 content/name |
| `capabilities_release` | binding；released | 释放当前调用者的绑定与 Provider 连接 |
| `development_open_bundle` | MCPB base64、SHA-256；runRef、摘要、开发渠道 | 用户确认后临时安装、独立 View/服务端进程与资源授权；不替换市场安装 |
| `development_read_resource` | runRef、普通资源 URI；标准 resources/read 结果 | 只能读取当前调用者自己创建的开发运行，不理解业务报告字段 |

每个 View 持有独立 Gateway；消费者与 DevKit 不共享授权。最多 8 个资源、8 个绑定；资源 64 MiB、调用输出 4 MiB，候选包 32 MiB；Provider 可进一步收紧。关闭 View、切换帐号、Provider 变更会阻止旧绑定调用；标签焦点不影响绑定。Host 不认识 PPTX、PDF、项目生成、讲解逻辑或审核结果字段。

MCP Apps 原始绑定服务端的工具和资源也可调用；只转发协商实现的方法。Host 仅把 `user_config` 声明映射到该包 `mcp_config.env`；不继承账户令牌。敏感配置当前仅在应用进程内保留，重启需重新输入，未使用明文持久化替代 Keychain。

## 开发产物与证据

项目文件、依赖锁、候选资源 `devkit://run/report` 和报告内容属于 DevKit/模板合同；Host 只做资源路由。报告固定代码摘要、Provider 包摘要和实际页数，不包含原文。当前报告是开发客户端报告，**不是服务端可信执行证明**；审核端仍需独立复测。固定构建器只拼装浏览器 JavaScript 与已发行的通用 MCP runtime，不执行项目 shell。

当前 Node 进程隔离不等于 OS 级沙箱。独立 Dev Host 应用身份/数据目录、通用 OS 权限沙箱、完整传递依赖解析、OIDC 开发者身份与审核自动认证仍需后续任务，不能把此 Desktop 内测 Profile 视作整个 M0–M4 已完成。

规范依据：[MCP Apps](https://apps.extensions.modelcontextprotocol.io/api/documents/overview.html)、[MCPB manifest 0.3](https://github.com/modelcontextprotocol/mcpb/blob/main/MANIFEST.md)。

## Workspace / CLI Profile（Desktop 0.2.0）

CLI 是 DevKit 包的一部分，使用根 `package.json` 的 npm `bin` 约定声明 `muse -> cli.mjs`。Host 可对任意审核包提供相同命令启动，校验回执文件摘要、入口和元数据，不识别 DevKit 子命令。该约定不是 MCPB 内建字段。

每个新 Workspace 终端获得短期 `MCP_HOST_URL` / `MCP_HOST_TOKEN`（4 小时、当前账号、固定根目录）。它们是本公开生态 Profile 的环境名，不是 MCP 保留字段。CLI 使用官方客户端，以标准 Bearer 和 MCP Streamable HTTP 调用 Host；随机 loopback 端口不对外监听，拒绝浏览器 Origin。终端关闭撤销，候选 View 独立授权，不继承令牌。CLI 不调用 Client 的私有命令代理。

| 普通工具 | 输入/输出 | 授权与范围 |
| --- | --- | --- |
| `workspace_describe` | 无输入；`roots: [{uri, name}]` | 终端只看到其授权根目录；View 看到用户当前 Workspace |
| `registry_search` | `query`；`onlineAvailable`、`plugins` | 搜索本机安装及当前服务商已审核目录；离线仍返回本地，listed 为 null |
| `registry_install` | `name`；安装回执 | 仅当前服务商已上架版本；原生确认后按真实摘要安装 |

CLI 通道还提供 `host_describe`、`capabilities_list`、`development_open_bundle` 和 `development_read_resource`；它不提供资源选取/调用代理，资料授权留在候选 View。后者通过 Apps 和自己的 Gateway 选择资料，避免终端/DevKit 继承消费者文档授权。

`muse init` 由 DevKit 在当前 cwd 事务生成文件，校验 cwd 的真实路径位于公开 roots 下。Host 不提供生成模板、编译项目、PPTX/PDF 字段解析或提交审核工具。

实际开发格式为 [project.schema.json](project.schema.json) 与 [lock.schema.json](lock.schema.json)，仅表达本期直接依赖快照。更复杂的传递依赖、Agent/Voice、设备解析格式仍是后续设计。SDK/CLI 当前捆绑发行，不表示已在 npm 公开发布。
