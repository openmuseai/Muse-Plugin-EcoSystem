# 冻结产品与设计：SD-BL-1.2-20261105

状态：按用户 2026-11-05 明确指令归档。此目录为不可变产品/交互快照；不在这里修订范围或重跑并覆盖证据。

- [产品稿：SD-01–SD-17](04-PRODUCT-PRD.zh-CN.md)
- [交互稿：功能区、编辑区、协作与 Mobile 语义](05-UX-SPEC.zh-CN.md)
- [视觉/功能映射：FA-01–14、WF-01–12](12-FUNCTIONAL-ALIGNMENT.zh-CN.md)
- [直接打开可点击设计](wps-functional-review/index.html)
- [主编辑页截图](wps-functional-review/screens/desktop-editor.png)
- [公开参考与待核对项](11-WPS-DESKTOP-REFERENCE.zh-CN.md)
- [验收规格](07-ACCEPTANCE.zh-CN.md)及[机器可读追踪](implementation-traceability.json)

规范优先于原型简化；真实产品测试仍为 unrun。19 项原型检查是本地模拟；指定企业页精确布局和最终 Mobile 高保真仍待细化。

工作入口：[冻结记录](../../13-FROZEN-BASELINE.zh-CN.md) → [详细技术方案](../../14-ENGINEERING-DESIGN.zh-CN.md) → [执行计划](../../15-EXECUTION-PLAN.zh-CN.md)。快照中的外链技术文档属于演进中的配套说明，不是已冻结 wire/API。

`manifest.json` 记录本目录文件 SHA-256、字节数和来源；Markdown 链接仅做归档路径调整，设计源字节不变。该清单未做外部签名，不代替 Git 归档。校验请从 v1 运行 `python3 scripts/verify_baseline.py`。

如需重新检查冻结预览，用 `node wps-functional-review/review-check.cjs wps-functional-review/index.html /absolute/path/new-evidence`；新证据必须写到此目录之外。
