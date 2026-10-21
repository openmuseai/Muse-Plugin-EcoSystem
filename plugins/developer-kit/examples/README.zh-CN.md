# DevKit 设计示例

这些文件用于校核拟定开发格式，不是已发布配置或可运行插件。合同 URI、SDK、最低 Host Profile 和未来版本仍需 M0 冻结并发布；不能把它们上传到真实兼容目录。

| 文件 | 用途 |
| --- | --- |
| [devkit.project.example.json](devkit.project.example.json) | 一个项目组合 PPTX、PDF、Agent 和可选 Voice，包含双资料比较 |
| [devkit.project.schema.json](devkit.project.schema.json) | 该配置的本地 JSON Schema 草案，校核字段类型和结构 |
| [dependency-plan.example.json](dependency-plan.example.json) | 合同尚未发布时的 blocked 计划；不虚构已解析版本或包摘要 |
| [provider.contract.example.json](provider.contract.example.json) | Provider 业务合同的公开导出映射与输入输出示意 |

`devkit.project.json` 和 `contract.json` 属于公开生态工具 Profile，不是 MCP/MCPB 基础规范。项目 schema 的 `$id` 为拟定发布地址，目前应使用本地 schema 校验，不需要请求该域名。

结构校验不能检查 Provider 是否真实存在、授权是否成立或一个功能的 `allOf` 是否引用已声明能力；这些语义由解析器和真实运行测试验证。开发锁文件只在依赖真实解析、下载、验证后生成，因此不提供含假 SHA 的锁文件样例。
