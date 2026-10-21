# DevKit 产品功能：Workspace 优先

更新：2026-10-21。本文以开发者确认的 Workspace / CLI 流程为准，替代最初“在 DevKit 新建独立工作台”的交互设想。当前实现和待交付项见[验收记录](08-DESKTOP-WORKSPACE-CLI.zh-CN.md)。

## 用户旅程

1. 在 OpenMuse 选择已有 Workspace，或者新建目录并作为 Workspace 打开。
2. 安装 DevKit 插件，在该 Workspace 打开应用内终端。
3. 使用 `muse search` 搜索已安装插件和当前在线市场；使用 `muse install` 安装需要的已审核 Provider。
4. 使用 `muse init --name ... --capability ... --capability ...` 选择一个或多个能力，原地初始化项目。
5. 在该 Workspace 的现有文件树、编辑器和 Agent 中开发；终端运行 `muse check` 和 `muse dev`。
6. 在应用内候选 View 选择真实资料、授权所需操作并运行，收集报告。
7. `muse pack` 生成不可变包，`muse submit` 上传并进入市场待审。

开发者无需检出 Host 或 Provider 源码，也不需要从源码构建它们。DevKit 页面提供环境说明、能力搜索和命令指导；代码编辑、终端、Workspace 管理由现有插件承担。

## 页面与命令

| 入口 | 职责 |
| --- | --- |
| Workspace | 选择/创建开发目录，现有文件与新代码使用同一目录 |
| DevKit 页面 | 展示 Host/Workspace 信息，搜索 Provider，指导安装和 CLI 使用 |
| 应用内终端 | 当前 Workspace 中运行 DevKit 发布的 `muse` 命令 |
| 现有编辑器与 Agent | 编辑源码、审阅修改；复用用户选择的插件 |
| 开发候选 View | 独立消费者页面，逐份选择资源和授权，多能力同时运行 |
| 市场后台 | 审核、批准/拒绝、下架；开发者命令没有审核权限 |

## 初始化与依赖选择

- 搜索同时呈现本地已安装和在线已审核插件，注明版本、摘要和安装/上架状态。
- CLI 的每个 `--capability` 可用关键词或完整合同 URI。若命中多个合同，要求精确选择；未安装时提示先安装。禁止悄悄替换 Provider。
- 本期支持 1–8 项带 `readSnapshot` 操作的直接能力依赖；PPTX、PDF 是首个组合，不限制项目只选一项。
- 锁文件记录 Host 构建摘要、Provider 精确版本/包摘要和合同副本。重新调试时检查已安装 Provider 与锁定版本一致。
- 文件直接生成在终端当前目录。已有非冲突文件保留；同名模板文件冲突时回滚，提示选择空目录或 Workspace 子目录。不会生成隐藏的中心项目库。
- 一个 Workspace 可以有多个子项目；在相应子目录运行命令。项目目标目录必须在该终端授权的 Workspace 内。

## 开发、调试和发布

`muse check` 校验浏览器模块语法和 `run` 导出。固定构建器把项目浏览器代码、公开 SDK 与已发行 MCP runtime 组合成包，不运行项目构建 shell。

`muse dev` 请求通用 Host 开发通道。Host 明确提示候选包名称/摘要并取得运行确认，然后打开独立 View 和进程。候选不替换市场已安装插件；用户为候选单独选择 PPT/PDF 文件并授权。

当前模板提供真实资料读取与组合结果示例，不声称已接入模型推理、语音或未保存编辑会话。PPTX/PDF 快照合同由对应插件维护。后续 Agent 能力依赖也必须经过公开合同选择与授权。

报告关联代码、包摘要及 Provider 版本/摘要；代码变动后旧报告失效。开发客户端报告不等于服务端可信认证，审核仍需独立复测。

`muse submit` 上传后仅返回 pending 回执。待审插件不进入公开目录；批准才允许市场新安装。消费者运行无需安装 DevKit。

## 本期边界与后续计划

本期优先 macOS：标准 MCPB/Node 发行包与 MCP Apps View。Android/Web DevKit、远端隔离 Runner、独立 Dev Host 应用身份、完整依赖图、类型补全、生成业务 SDK、OIDC 开发者登录及审核自动认证仍在计划中。

Workspace 终端本身具有本机用户的 shell 权限。短期 MCP 凭据限制的是 Host API；独立 Node 进程也不是 OS 沙箱。页面不获得终端令牌或 Agent 全局令牌。
