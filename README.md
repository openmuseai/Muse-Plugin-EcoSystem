# OpenMuse Plugin Ecosystem

状态：**方案与首个 PPTX 纵向样例，2026-10-15**。本仓库已在本地初始化；公共商店服务、签名发布、SDK 和开发者门户尚未实现或发布。GenOffice PPTX 的 Desktop 核心 worker 已拆出并通过本地安装目录验证；它尚不等于三端可上架产品。

目标是承载非内置插件的官方示例与受维护源码、开发者文档、版本化合同、测试工具、发布服务和审核流程。社区开发者可以保留自己的源码仓库，向 OpenMuse 提交不可变的构建产物；Git 仓库不是线上安装源，也不是任意上传代码的执行环境。

- [产品与生态设计](docs/PRODUCT.zh-CN.md)
- [技术架构与接口设计](docs/ARCHITECTURE.zh-CN.md)
- [实施顺序与验收](docs/ROADMAP.zh-CN.md)
- [开发者入门指南草案](docs/DEVELOPER-GUIDE.zh-CN.md)
- [编码代理 Skill 设计](docs/AGENT-SKILL-CONTRACT.zh-CN.md)
- [仅用手机与 Agent 创建插件](docs/MOBILE-AGENT-STUDIO.zh-CN.md)
- [Store API OpenAPI 草案](contracts/store-api.openapi.yaml)
- [GenOffice PPTX 源码分析、拆分与三端接入](docs/GENOFFICE-PPTX.zh-CN.md)
- [GenOffice PPTX 独立插件样例](plugins/genoffice-pptx/README.md)

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
plugins/genoffice-pptx/      # 首个外部插件：GenOffice PPTX 核心、构建与本地包
docs/                        # 开发者指南、架构、审核与安全流程
```

当前 `plugins/genoffice-pptx` 固定上游源码快照并构建 Node worker。本仓库仍以 `Muse-Client` 的 Manifest v2 为真源，未复制合同定义。`dist/` 是本地、未签名的安装夹具，只供开发测试。
