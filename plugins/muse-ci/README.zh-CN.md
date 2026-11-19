# Muse CI 产品插件

Muse-CI 是可安装到 OpenMuse Desktop 和 Mobile 的 AI 原生交付插件，从需求计划到执行证据、人员决策和发布记录形成同一条交付链。

本目录交付 0.2.0 开发里程碑：版本主流程、需求子流程、Step 画布、人工标过、原生 SmartDoc 与 Agent 委托协作，并延续真实 Temporal/PostgreSQL 的执行和证据闭环。已完成 macOS/Android 开发构建中的通用 MCP Apps 接入，真实 DSH AI 可跨端查询、修改计划并重跑节点；生产市场后装、OAuth、iOS 真机与正式签名/商店发布尚未通过验收。DSH 工具编排与节点后端 AI 代码执行分别验收。

- [版本/需求生命周期与 SmartDoc 新规范](docs/07-LIFECYCLE-AND-SMARTDOC.zh-CN.md)
- [本轮测试用例](docs/08-LIFECYCLE-TEST-CASES.zh-CN.md)
- [0.2.0 生命周期交付与验证报告](docs/09-LIFECYCLE-ACCEPTANCE.zh-CN.md)
- [Desktop/Mobile 国内服务真机验收](docs/DESKTOP-MOBILE-HOST-E2E.zh-CN.md)
- [开发计划](docs/05-DEVELOPMENT-PLAN.zh-CN.md)
- [实现与端到端验收](docs/06-IMPLEMENTATION-AND-ACCEPTANCE.zh-CN.md)
- [Web/Desktop 节点流程编辑器](docs/04-WORKFLOW-EDITOR.zh-CN.md)
- [产品功能](docs/01-PRODUCT.zh-CN.md)
- [交互规范](docs/02-INTERACTION.zh-CN.md)
- [设计与验证](docs/03-DESIGN-AND-VALIDATION.zh-CN.md)
- [交互原型](web/index.html)
- [完整架构](../../../Muse-CI/docs/Architectur-Discussion.md)
- [Host 协议与能力明细](../../../Muse-CI/docs/HOST-PROTOCOL-CAPABILITY-DETAILS.zh-CN.md)

## 实际开发服务

先在本目录 `npm run pack`；在 `Muse-CI/` 执行 `npm ci && npm run stack:up && npm run dev`。打开 `http://127.0.0.1:4180/`；`/host` 验证沙箱 MCP App。`npm run e2e` 运行真实持久执行验收，`node scripts/host-conformance.mjs` 验证实际 Desktop Host 安装后调用。详见实现文档。

标准开发包为 dist/muse-ci-0.2.0.mcpb，远端发行输入为 dist/release.development.json；均未发布到市场。

## 离线交互预览

在本目录执行 `npm run preview`，浏览器打开 `http://127.0.0.1:4178`（开发服务存在时跳转至 4180；`?demo` 强制离线示例）。也可以直接打开 web/index.html；页面不依赖在线字体、图片或 CDN。`npm run build` 生成内联资源的 dist/index.html，作为实际 MCP App UI artifact；`npm run pack` 另生成标准 Node MCPB。

Web/Desktop 默认进入分阶段节点画布，支持添加节点/阶段、配置 Skill/工具/材料、依赖连接、节点重跑与历史产物。Mobile 显示同一流程的阶段列表。

旧版交付级操作也可体验：新建交付、保存计划、运行示例、暂停恢复、取消确认、阶段浏览、证据筛选与查看、人员决策、示例后端连接及断线状态、重置。数据仅存当前浏览器；后台可靠运行及跨设备同步需要正式执行后端。
