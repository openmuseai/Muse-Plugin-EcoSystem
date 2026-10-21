# OpenMuse Plugin DevKit

OpenMuse Plugin DevKit 是可安装、可停用、可升级和可卸载的开发者插件。开发者先在 OpenMuse 选择或新建 Workspace，再在该 Workspace 的终端搜索/安装能力依赖，通过 CLI 初始化项目，使用现有编辑器或 Agent 开发、应用内调试并提交市场审核。

当前已包含 Desktop DevKit 插件、共享项目核心、Apps SDK、`muse` CLI，以及真实 PPTX/PDF Provider 适配。0.2.0 的 Workspace/CLI 流程已通过本地协议测试并发布到生产市场，原生 UI 全流程验收仍在进行；当前公开版本与证据见[Desktop 实现记录](docs/08-DESKTOP-WORKSPACE-CLI.zh-CN.md)。

## 阅读顺序

| 文档 | 主要读者 | 内容 |
| --- | --- | --- |
| [产品功能](docs/01-PRODUCT.zh-CN.md) | 产品、设计、开发者 | 插件入口、信息架构、多能力选择、初始化、编码、调试、发布 |
| [开发者指南](docs/02-DEVELOPER-GUIDE.zh-CN.md) | 新插件开发者、开发 Agent | 不读 Host 和依赖插件源码的完整开发旅程 |
| [技术方案](docs/03-ARCHITECTURE.zh-CN.md) | Host、生态、服务端工程师 | 运行边界、技术选型、会话、Gateway、多端与市场服务 |
| [公开合同与 SDK](docs/04-CONTRACTS-AND-SDK.zh-CN.md) | SDK、能力提供插件作者 | 合同分层、发现、依赖解析、权限、版本、错误和 SDK |
| [开发计划](docs/05-DEVELOPMENT-PLAN.zh-CN.md) | 工程负责人、开发团队 | 阶段门禁、任务、依赖、交付顺序和风险 |
| [验收矩阵](docs/06-ACCEPTANCE.zh-CN.md) | 测试、审核、发布负责人 | 双格式组合、独立环境开发、设备与发布闭环 |
| [开发基线](docs/07-IMPLEMENTATION-BASELINE.zh-CN.md) | 工程、测试 | 分支、既有改动提交与开发前测试结果 |
| [任务表](docs/development-plan.csv) | 项目管理、自动化工具 | 与开发计划相同的任务 ID、前置条件和验收项 |
| [设计示例](examples/) | SDK、工具开发者 | 开发配置、JSON Schema 与多能力需求样例 |

## 已确定的设计决策

1. DevKit 自身遵循插件生命周期；安装 DevKit 不等于给所有项目开放设备和 Workspace 权限。
2. 一个项目可以组合 PPTX、PDF、Agent、语音等多个能力，也可以同时绑定多份经用户授权的资源。
3. 开发者依赖公开合同、API 包和 Provider 发行包；Host 只处理通用发现、授权、路由和生命周期。
4. DevKit 作为插件发行 CLI 与共享项目核心；Workspace 和 CLI 是主要开发入口。页面提供环境与能力搜索，现有编辑器和 Agent 在同一 Workspace 操作代码。
5. 开发配置和锁文件是公开工具格式；插件与 Host 运行时继续使用标准 MCP/MCP Apps，不把开发配置塞进客户端私有 Manifest。
6. Desktop 首先完成真实 PPTX + PDF 双能力闭环；Android 的跨插件调用、真机调试及手机创作按阶段交付，支持状态由实测决定。
7. 开发包、审核包与上架包明确区分。提交审核不会自动上架，开发者和 Agent 不获得审核员凭据。

## 参考与范围

更新：2026-10-21。已发布 GenOffice PPTX 0.6.0 与 PDF Reader 0.1.0 的只读快照合同；完整能力矩阵和独立 Dev Host 发行仍需补齐。

完整 M0–M4 门禁仍保留在计划中；只读快照、headless 测试和开发者 pending 回执不能代替 Live 编辑、多端真机或原生界面的最终验收。
