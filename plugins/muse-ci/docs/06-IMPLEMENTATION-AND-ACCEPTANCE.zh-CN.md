# Muse-CI 开发闭环实现与验收

> 2026-11-19 更新：当前版本/需求双层流程、Step 规则、人工标过及 SmartDoc 文档协作以 [生命周期新规范](07-LIFECYCLE-AND-SMARTDOC.zh-CN.md) 为准。以下旧画布和原型记录作为历史基线保留。

日期：2026-11-18。当前交付为 **0.1.0 开发里程碑**：从产品、UI 和架构材料，到真实检查/构建、人员开发验收和证据的链路。它已经连接真实后端；正式市场、真实 AI 服务和商店发布的验收状态单独列出。

## 可操作交付

- Web/Desktop：保留分阶段画布、同列上游在前、显式连线、配置抽屉、节点日志与产物。产品稿和 UI 稿无依赖时并行，架构依赖二者，开发依赖架构。
- Mobile：同一插件 UI 的阶段列表、计划、运行、证据和更多入口；各页面读取同一服务端项目，不再各自推进本地演示任务。
- 产品、UI、架构三种节点可直接添加。已绑定 Skill 有固定版本和摘要；工具从已绑定目录配置。自定义但未绑定的能力明确失败。
- 材料包括文字、64 KiB 以内的文字文件（最多 16 个唯一内容对象）和上游产物引用。真实文字文件经 MCP 保存到当前项目，按 SHA-256 固定；原型文件名占位不能作为真实输入。
- 每次执行保留 Attempt、配置版本、上游尝试、Skill 定义、材料正文快照、输入摘要、日志和产物摘要。改产品/设计/依赖使相关结果过期，重跑保留旧产物。
- 完整计划自动推进选定 DAG；“运行就绪节点”只运行点击时的就绪集合。真实检查可并行。暂停停止新任务，取消阻止迟到结果；额度按节点派发次数计算，不冒充模型账单。
- 节点超时取配置值；检查进程非零退出可按配置的重试上限新增尝试，保留失败历史并计入额度。未配置 Provider、过期材料和正式发布缺项不自动重试。
- 签名、设备或渠道回执缺失时，发布页和发布检查保持阻塞；开发验收不是商店发布授权。

## 代码边界

| 位置 | 职责 |
| --- | --- |
| `web/graph-model.js` | 本地预览和后端共用的 DAG 基础逻辑 |
| `web/runtime.js` | 唯一服务端状态 adapter、连接、项目、命令和游标恢复 |
| `web/bridge.ts` | 官方 MCP Apps SDK；嵌入态仅使用 Host serverTools |
| `web/live-app.js` | 七个实际服务页面，复用画布和配置 UI |
| `mcp/proxy.ts` | Desktop 本机 stdio → 受信后端 MCP，UI 固定为包内 resource |
| `host/index.html` | 通用开发验证 Host：无 CI 工具名分支，来源/方法/工具白名单，沙箱 connect-src none |
| `Muse-CI/apps/api` | MCP tools/resources、开发 Web Host、项目 ACL、命令、版本冲突、事务存储与 Outbox |
| `Muse-CI/apps/worker` | Temporal 工作流、并行 Activity、超时、心跳与执行恢复 |
| `Muse-CI/packages/contracts` | openmuse.ci/1 Schema 和共用图模型适配 |
| `Muse-CI/packages/policy` | 确定性准入、预算、依赖、决定、重试和旧 Runner 结果拒绝 |
| `Muse-CI/packages/providers` | 设计材料编译、已绑定 Skill、真实受控进程、AI MCP 提案适配、来源摘要 |
| `Muse-CI/deployment` | 独立 PostgreSQL 与持久化 Temporal 开发服务 |

Host 生产代码没有增加 CI 业务分支。Muse-Client 仅新增可选择环境变量启用的通用安装后工具调用验收测试。

## 已冻结的开发合同

| MCP tool | 用途 |
| --- | --- |
| ci_open | 零文件参数 MCP App 入口 |
| ci_capabilities | 真实已绑定工具、Skill、AI 接收方及能力边界 |
| ci_projects_list / ci_projects_create | 项目列表与幂等创建 |
| ci_project_get | 七个页面共用的项目/图/Run/证据快照 |
| ci_plan_save | 目标、类型、额度及输入版本更新 |
| ci_graph_save | 严格 Schema 的定义写入；不能上传执行成功状态 |
| ci_run_command | start/pause/resume/cancel/approve/reject/stop-node |
| ci_events_list | after 游标与服务端版本 |
| ci_material_put | 项目内按摘要保存文字内容 |
| ci_artifact_get | 按节点、Attempt、序号读取并核验 SHA-256 |
| ci_ai_consent | 限定模型接收方和数据类别的授权/撤回 |
| ci_release_check | 十二阶段缺项及正式发布阻塞 |
| ci_coding_apply | 当前成功编码尝试的候选补丁受控应用，校验范围、输入与文件基线，保留应用事件 |

写命令绑定 projectId、commandId、expectedVersion。相同命令重复投递返回同一业务操作；重用 ID 搭配不同参数被拒绝。服务端忽略网页的执行事实，只接收定义与操作意图。开发验收决定必须匹配当前 Attempt 的 inputDigest。

当前开发实现将图、Run 和命令保存在 PostgreSQL 聚合，由 Temporal 持久驱动策略/Provider Activity。目标架构的 Workflow Update、完整事件投影分离和生产 reconciliation 尚未全部实现；开发重启测试不代表目标生产内核已经交付。

一个数据库事务保存命令、项目变更和 Outbox。dispatcher 幂等启动同一个 Temporal workflowId，worker 把 accepted 应用为实际状态并追加事件。页面关闭不取消后端 Run。Runner 使用短期 lease；旧 token、过期 lease、取消后的结果不能覆盖当前尝试。

## 可复现启动与验证

环境：已验证 macOS、Node 24.16.0、Docker。首次构建需要生态仓库已有锁定依赖；后端依赖单独锁在 Muse-CI/package-lock.json。全部开发端口绑定 127.0.0.1，不更改既有业务数据库。

```sh
# 插件目录；使用生态仓库依赖
cd Muse-Plugin-Ecosystem/plugins/muse-ci
npm run pack
npm test

# 后端目录
cd ../../../Muse-CI
npm ci
npm run stack:up
npm run dev
```

Web 为 `http://127.0.0.1:4180/`，通用 MCP Apps 验证 Host 为 `/host`，MCP 为 `/mcp`。旧 4178 预览入口在开发服务存在时跳转至 4180；`?demo` 保留离线示例。

独立运行验收：

```sh
cd Muse-CI
npm run typecheck
npm test
npm run e2e
node scripts/host-conformance.mjs
```

e2e 启动独立 4181 API 和独立 Temporal task queue，测试后关闭其进程，保留项目和证据；不会取消其他项目。`npm run stack:stop` 仅停止本轮开发容器，保留卷。令牌只存在忽略提交的 `.data/development.env` 和后端/Host 配置，不写入 UI、截图或验收日志。

## 验收事实与证据

- 插件模型测试：22 项，覆盖原演示与 DAG、产品/设计输入、同列顺序和并行。
- 后端测试：15 项，覆盖策略、权限、材料准入、取消、fencing、有界重试、JSON 键序稳定性与 AI MCP 合同。
- 真实开发 E2E：20 个检查点，包含并发建表、MCP 认证/Origin、幂等创建与启动、材料上传与 Skill 固定、暂停/API 重启/worker 重启、真实并行检查、输入绑定决定、产物 SHA、第二客户端、改目标/改 UI 后失效、单节点重跑、游标和取消。
- E2E 的四个进程真实执行：插件模型测试、后端核心测试、权限检查测试及 UI artifact 构建。没有把预置 JSON 当作执行结果。
- Desktop 实际 Host 安装器和 runtime 已安装本轮 MCPB，并完成工具发现、UI resource 读取及配置好的后端工具转发。测试不等同于市场审核批准或桌面生产 UI 全流程验收。
- 浏览器实际验收包含 Web 手机布局发起真实运行、七页同一项目状态、添加产品节点及 Skill/工具/材料配置、MCP Apps 沙箱读取真实项目与开发验收决定。细项及截图以浏览器验收记录为准。

[端到端报告](evidence/live-e2e/report.json) · [执行日志](evidence/live-e2e.log) · [后端测试](evidence/live-model-tests.log) · [Desktop 安装后调用](evidence/live-e2e/desktop-host-conformance.log) · [UI 构建](evidence/live-build.log) · [三尺寸检查](evidence/live-inspect.log)

## 尚未通过的产品关口

| 关口 | 当前状态 | 后续任务 |
| --- | --- | --- |
| 真实 AI/DSH 编码修复闭环 | AI MCP adapter 已实现；合同测试用明确标识 fixture，无真实模型调用 | 绑定实际 Provider、接收方/数据授权、代码提案审查、隔离执行与回归；不把本轮材料编译说成 AI 研发完成 |
| 身份与云端授权 | 本机开发身份、后端固定开发 token、项目 ACL 检查 | GoTrue 验证、MCP OAuth、账号隔离、撤回、生产密钥 Broker |
| Mobile 原生后装 | 共用 UI 与 MCP 沙箱已验证；未宣称 iOS/Android 原生安装通过 | P01–P08 通用 Host、发行目录信任、pin 策略、serverTools 与实际设备验收 |
| 远端 UI 安装 profile | 生成 development release 输入与 UI 摘要，不是批准 receipt | Schema/签名目录/事务安装/回退和两端实施 |
| 生产执行与存储 | 本机受控命令、数据库保存小产物；检查前后核验源码 manifest | 真正隔离/冻结 SourceSet、S3、保留与删除策略、跨租户、灾难恢复 |
| 正式渠道 | 永远不把开发结果写成提审/上线成功 | 签名、设备池、十二阶段 adapter、可信批准和渠道 reconciliation |

当前 `retries` 为检查失败的领域重试；Temporal Activity 基础设施重试单独处理崩溃/瞬断，不等同无限次重建。外部渠道不确定状态和生产故障收敛仍是后续发布阶段，不能用开发测试取代。

协议实现参考 [MCP Apps 官方构建文档](https://modelcontextprotocol.io/extensions/apps/build) 与 [Temporal TypeScript 官方文档](https://docs.temporal.io/develop/typescript)。开发 Temporal 使用官方持久化 start-dev；不是生产 Temporal 部署验收。


## 2026-11-18 最终 UI 复核

ROUND 3
Seen in one second: 产品/UI 输入、架构和真实检查组成可追踪的阶段画布。
Idea (one sentence): 需求与设计先变成固定材料，随后每项执行都可追溯输入和证据。
Live thing: 实际服务上的新建、配置、依赖、执行、开发决定与产物查看。
Layout words by section: toolbar=actions / canvas=stage-lanes / mobile=grouped-list / inspector=configuration。
Scores: design 6.5 · usability 8 · creativity 6.5 · content 8 → overall 7.1。
Caps applied: 工作台没有装饰图片，保守保留 design 6.5 上限；不套用营销首屏的照片/视频要求。
Top three problems (most visible first), each with the screenshot it shows in and the fix:
1. desktop-fold.jpg：新增产品和架构后阶段超过单屏；保留横向画布及缩放，优先清晰阅读而不是强行压成六列。
2. tablet-fold.jpg：侧栏与画布同时占宽；已有横向滚动和配置抽屉，后续可增加用户控制的侧栏折叠。
3. mobile-fold.jpg：纵向流程较长；以阶段分组、固定导航、节点状态和抽屉保持定位，后续可增加按状态聚合。

已逐张查看 1440/768/390 截图。最终 lint 与三尺寸 inspect 均 **0 FAIL、0 WARN**；应用场景 allowance 延续画布设计，不豁免对比度或页面溢出。

最终手动 UI 项目：`c7f2d92f98ad34ee004d6613f293d339`，Run：`f1b44569-df7b-4c4a-ba16-bf470e894965`。新增产品节点经 UI 配置 ci-product、doc-compile 与文字材料，并连接为架构上游；实际产物包含对应 Skill 指令和材料。14 个节点中，13 个开发节点成功，1 个正式发布检查按预期报告缺少真实签名、设备和渠道回执。Web 手机布局与沙箱 MCP App 已分别看到同一结果；不把开发决定记录当原生设备验收。

## 2026-11-18 · 真实 Mobile 编码试验

已通过本机真实模型执行 A01/A02/A03 及失败修复节点，候选补丁经监督审查后使用第 14 个 MCP 工具 `ci_coding_apply` 应用。四类固定编码工具使用独立快照，输入为获授权的目标、材料和选定源码；不携带服务 token。真实模型返回完成不等于功能验收。当前使用 Desktop 随附 Codex CLI；DSH 探测返回余额不足，原 DSH/MCP 架构入口保留。

Mobile 首试的实际补丁、失败、修复与独立结果以 [整改记录](../../../../Muse-Client/docs/release/runs/2026-11-mobile-isolation/muse-ci/AI-REMEDIATION.zh-CN.md) 为准。后端说明见 [执行器边界](../../../../Muse-CI/docs/CODING-EXECUTOR.zh-CN.md)。原生 Mobile 后装、生产身份与签名/渠道交付没有因接入编码执行器自动完成。
