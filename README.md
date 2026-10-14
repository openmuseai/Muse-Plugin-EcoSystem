# OpenMuse Plugin Ecosystem（方案仓库）

状态：**设计草案，2026-10-15**。本仓库已经在本地初始化；服务、SDK、CLI 和远端发行仓库尚未实现或发布。

目标是承载非内置插件的官方示例与受维护源码、开发者文档、版本化合同、测试工具、发布服务和审核流程。社区开发者可以保留自己的源码仓库，向 OpenMuse 提交不可变的构建产物；Git 仓库不是线上安装源，也不是任意上传代码的执行环境。

- [产品与生态设计](docs/PRODUCT.zh-CN.md)
- [技术架构与接口设计](docs/ARCHITECTURE.zh-CN.md)
- [实施顺序与验收](docs/ROADMAP.zh-CN.md)
- [开发者入门指南草案](docs/DEVELOPER-GUIDE.zh-CN.md)
- [编码代理 Skill 设计](docs/AGENT-SKILL-CONTRACT.zh-CN.md)
- [Store API OpenAPI 草案](contracts/store-api.openapi.yaml)

## 与现有仓库的边界

| 仓库 | 责任 |
| --- | --- |
| `Muse-Client` | Host、三端运行时、安装与权限执行、Manifest v2 的当前真源、客户端集成测试。 |
| `Muse-Server` | 现有账号、Workspace/Cloud、设备中继；商店身份可复用 GoTrue，但插件版本和审核状态由本仓库的商店服务拥有。 |
| 本仓库 | 外部插件的开发、验证、提交、审核、签名目录、静态产物与开发者门户。 |
| 开发者仓库 | 各开发者的源码、构建与维护。商店只接收明确授权提交的产物和元数据。 |

## 建议的目标目录

```text
apps/developer-portal/       # 开发者控制台、公开文档和目录页
services/store-api/          # 目录查询、开发者发布、审核、统计
services/release-worker/     # 隔离扫描、TCK、签名发布
crates/plugin-tool/          # openmuse-plugin CLI、打包与本地验证
sdk/                         # Desktop、Mobile、Web SDK 和示例
contracts/                   # 版本化 API/发布/能力合同及 fixtures
templates/                   # 三端模板与最小可运行示例
skills/                      # 给编码代理使用的开发/验证 skill
plugins/official/            # 官方维护但非 built-in 的插件源码
docs/                        # 开发者指南、架构、审核与安全流程
```

当前仅创建方案文档。落地时先固定合同和运行时门禁，再添加上述实现目录；不要提前把现有 `Muse-Client` 代码复制为第二份合同真源。
