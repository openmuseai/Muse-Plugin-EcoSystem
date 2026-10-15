# 第三方插件生态产品方案

## 目标与用户旅程

开发者选择目标客户端版本（默认公开兼容矩阵的最新版本），用任意语言实现 MCP Server，运行公开 MCP TCK，打包并上传标准交付物，提交标准 `server.json`，等待自动检查和人工审核。审核通过后，用户在客户端的在线目录看到同一个插件名称，选择适合其平台的交付方式，一键安装或连接，并能发现 MCP tools/resources/prompts。撤回版本立即停止新的分发；既有安装收到撤回提示。

手机上的轻量创作流程：用户向 Agent 描述一个表单助手 → Agent 生成 MCP 工具和 A2UI 表单或 MCP Apps 界面 → 在受限预览中试用 → 用户确认权限和公开资料 → 运行 TCK → 提交审核。创作发生在云端工作区，手机只需要浏览器/客户端；用户可以导出源码和标准 `server.json`，不被本商店锁定。

## 身份与多端发布

一个逻辑插件使用一个 MCP Registry `server.name`，例如 `io.openmuse/genoffice-pptx`。同一版本的 `server.json` 可列出多个 `packages` 或 `remotes`；客户端按照标准包类型、MCPB `compatibility.platforms/runtimes` 和 MCP 协议协商选择。不同能力或不同发布节奏可发不同 SemVer。没有可运行交付物的平台不标记可安装。平台能力不是营销字段。

Desktop：下载 MCPB、核验 `fileSha256`、检查标准 `manifest.json`，以隔离进程运行 MCP stdio Server。Host 可以根据标准 MCP 工具 JSON Schema 的 `contentEncoding` 与 `contentMediaType` 提供用户选文件入口；不读取插件私有命令。

独立进程是本轮第三方 MCPB 的 Host 执行策略，不是所有 Desktop 插件的协议强制要求。客户端已有的内置热插拔组件仍可在其内部生命周期中运行；第三方开发者面对的公开合同始终是 MCP/MCPB，不能依赖该内部热插拔机制。

Mobile：首选远端 MCP Streamable HTTP 服务和 A2UI over MCP 的标准交互；复杂 HTML 采用 MCP Apps 的沙箱 WebView。现有 QuickJS 可以作为客户端内部执行手段，但不得作为第三方接口或下载包约定。离线可用需要单独的、公开且经 TCK 证明的移动交付规范；当前不承诺手机本地执行 GenOffice Node 引擎。

Web：远端 MCP + OAuth，界面采用 MCP Apps 的沙箱 iframe 或 A2UI 渲染器。第三方代码不进入主应用同源特权上下文。

## 市场审核与信任

上传后状态为 `pending`，此时目录和包下载均不可见。审核要覆盖命名空间所有权、许可证、恶意代码、依赖、供应链来源、实际 MCP 能力、资源与网络行为、平台设备矩阵、隐私声明。人工审核与自动检查均留证据；批准的是固定 digest 和元数据快照，不能修改原版本。服务运营人员可拒绝或撤回。客户端只安装已批准版本并固定 SHA-256。

当前服务实现上传、待审、批准/拒绝、公开目录与包下载；生产审核基础设施见[架构](ARCHITECTURE.zh-CN.md)。
