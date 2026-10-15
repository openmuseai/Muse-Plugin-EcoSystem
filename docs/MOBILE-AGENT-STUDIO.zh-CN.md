# 手机 + Agent 创建插件

普通用户用手机描述需求，例如“做一个收集访谈信息的表单助手”。Agent 在云端隔离工作区生成 MCP Server、A2UI 界面与公开源码，运行协议测试并返回可交互预览。用户修改文案和字段、确认数据去向与工具权限、选择私有/邀请/公开发布，再由 Agent 提交审核。手机无需 Node 编译环境，也不应接触审核员密钥。

小型表单助手：用标准 MCP tools 接收表单动作，A2UI v0.9.1 `createSurface`、`updateComponents`、`updateDataModel` 绘制表单；客户端上报动作仍走 A2UI 定义的客户端消息。Agent 只调用已经获得用户许可的工具。开发者可以导出标准 `server.json`、服务源码和测试报告，在其他 MCP 客户端继续运行。

当前实施顺序：

1. 云端受限预览：模板、A2UI Schema 校验、工具 Mock、无真实副作用。
2. 审核前 TCK：MCP 协商、A2UI 渲染、行动回执、弱网与权限拒绝。
3. 远端 MCP 服务部署：独立运行配额、OAuth、审计与撤回。
4. 手机商店接入 MCP Registry 的 `remotes`，连接 Streamable HTTP；完整 A2UI 绘制与复杂 HTML 的 MCP Apps 沙箱作为后续门禁。
5. 真机和渠道政策门禁后开放公开发布。

QuickJS 可以用于客户端内部的轻量表达式计算，但不存在面向第三方的 QuickJS 私有全局对象 API。PPTX GenOffice Node 引擎不能直接搬进 QuickJS；手机上的原生只读查看器与本仓库 MCPB 是两条不同实现路线。手机端在线 MCP Registry 连接和安装记录已实现；Agent Studio、A2UI 完整绘制和审核门户**未交付**。
