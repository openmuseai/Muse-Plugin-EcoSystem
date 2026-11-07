# 智能文档第一阶段工程冻结输入

基线：**SD-F1-20261105**；2026-11-05。关联不可变[产品/交互 SD-BL-1.2](../sd-v1.2-20261105/BASELINE.zh-CN.md)。

本归档冻结完整目标方案、总执行计划，以及第一阶段实施范围、版本和退出条件。第一阶段以 [16](16-PHASE1-IMPLEMENTATION.zh-CN.md) 的明确切片为交付范围；[14](14-ENGINEERING-DESIGN.zh-CN.md) 中公开合同、通用 runtime、Agent/Office 等后续设计不因归档而变成已实现接口。阶段文件格式不是平台永久公共合同。冻结不改变完整产品目标，不将 macOS 验证替代全量 G0 或三端首版验收。

* [详细目标方案](14-ENGINEERING-DESIGN.zh-CN.md)
* [总执行计划](15-EXECUTION-PLAN.zh-CN.md)
* [第一阶段具体方案与开发批次](16-PHASE1-IMPLEMENTATION.zh-CN.md)
* [实际实现/验收及后续门槛](../../17-PHASE1-ACCEPTANCE.zh-CN.md)

`manifest.json` 固定本目录所有正文/来源证据的大小与 SHA-256；`source-evidence.json` 记录工作稿来源摘要及相对链接改写。工程方案有变更时新增版本/变更记录，不覆盖本归档。可运行代码和本轮测试证据由阶段验收报告关联，它们不会改写产品冻结时的 `unrun` 历史台账。

校验：从 v1 运行 `python3 scripts/verify_engineering_baseline.py`。
