# 开发者编码代理 Skill 设计

状态：Skill 产品/技术合同。实际 `SKILL.md` 应在 CLI/TCK 可运行、模板稳定后创建，不能让代理以文字指令替代签名与测试。

## Skill 组合

面向普通用户的第一入口应是 OpenMuse Mobile 内置的 `mini-plugin-maker` Agent Skill：它把需求限制在 `MiniPluginSpec`、`forms@1` 等已上线能力中，驱动草稿、预览与私有发布工具。用户不需要安装开发 Skill 或 CLI；完整流程见 [手机 Agent 插件工坊](MOBILE-AGENT-STUDIO.zh-CN.md)。下面的 Skill 供专业开发者使用。

| Skill | 输入 | 行为 | 输出 |
| --- | --- | --- | --- |
| `openmuse-plugin-start` | 产品需求、目标平台 | 询问真正缺失的权限/目标信息，选择模板，生成最小 Manifest、代码与本地示例 | 可运行工程与声明的支持矩阵。 |
| `openmuse-plugin-ui` | A2UI/WebView/Web Surface 需求 | 读取固定 profile，使用允许组件/bridge，生成预览和无障碍检查 | UI 产物与 profile 版本。 |
| `openmuse-plugin-validate` | 工程或发行包 | 调用 `validate`、`test --tck`，解释失败并修正代码 | TCK 报告、未通过项、修复记录。 |
| `openmuse-plugin-publish` | 已通过 TCK 的包、发布说明 | 核对权限 diff、许可、来源和 digest，准备提交资料；由开发者身份完成上传 | submission ID 与审核状态。 |

Skill 的固定规则：只从指定的 SDK/Manifest tag 读取合同；先识别 Desktop、Mobile 和 Web 的不同执行边界；不声明没有真实 artifact 的平台；不给插件直连 Host 内部文件、DSH profile 或生产 Secret；用户未授予的能力必须保留可解释失败路径。自动生成的发布说明必须列出新增权限、外部域和数据迁移。Skill 不能持有商店签名私钥，不能绕过 TCK 或代替人工审核。

## 验证方式

每个 Skill 与模板工程同版本发布；CI 用“低权限 Mobile 卡片”“Desktop 文件只读”“Web 远程 Surface”“错误 target”“越权 bridge”五类任务回放。至少检查生成代码能构建、Manifest 与真实 artifact 一致、TCK 运行、错误建议不会要求关闭安全门禁。只有稳定后，才把 Skill 放入 `skills/<name>/SKILL.md` 供开发者安装。
