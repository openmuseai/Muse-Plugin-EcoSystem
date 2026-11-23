# Repository Review

通用的高亮仓库 Diff 与文件版本审阅 MCP / MCP Apps 插件。

**独立工程**：同级仓库 `Muse-Repository-Review`。本目录只维护生态分发入口及此前选型研究，不复制运行时源码。

构建候选包：`node scripts/build.mjs`。独立工程不在约定同级路径时，通过 `REPOSITORY_REVIEW_SOURCE` 指定；构建输出到本目录 `dist/`，校验包摘要并保留第三方许可证。MCPB 完整包含服务与UI，无 Host 私有源码依赖。

0.1.0 候选包含：工作区/暂存区/分支/提交/MR 来源，统一与并排高亮、全文、意见、已阅、本地审阅结论与回执，以及经 Host 明确授权的历史查看、保存、比较与恢复。Host 沿用 LocalVersionStore；Mobile 通过国内公网配对中转使用同一安装实例。

Muse-CI 的新项目为 `repository-review-plugin`，0.1.0 版本ID `ad060c4ff9dbd5baa78a971e0c5345ee`。产品、计划、公开合同、运行和验收证据在独立工程 `docs/releases/0.1.0/`。本目录 `docs/` 与 `spikes/` 是此前能力盘点/选型的历史材料。

当前状态为验收候选，不是公开市场已批准版本。实际设备验收按版本证据记录：0.2.0 已完成 PLP110 展开屏；其物理外屏与新接 PKM110 的最终结果需查看独立工程的验收报告。

0.2.0 新增原生 Open File Viewer 集成、紧凑 Git tree、Tree-sitter 高亮、上下文展开折叠与快照代码跳转。独立工程的版本文档与证据位于 docs/releases/0.2.0/；对应 Muse-CI 版本 71e2c0fc8e3bed84ad4097adb1f26774。
