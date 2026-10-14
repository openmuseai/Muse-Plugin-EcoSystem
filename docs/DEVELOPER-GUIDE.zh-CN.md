# 开发者指南草案

状态：**目标工作流**，下列 `openmuse-plugin` 命令尚未实现。此指南用于确定 CLI、模板和服务端的验收合同。

## 选择插件形态

普通用户先使用 [手机 Agent 插件工坊](MOBILE-AGENT-STUDIO.zh-CN.md) 的“描述需求 → 预览 → 私有安装”路径；下表是需要写代码或自定义运行时的开发者路径。先选择能在目标设备运行的最小形态：

| 需求 | 模板 | 限制 |
| --- | --- | --- |
| Desktop 表单/卡片/简单工具 | `desktop-declarative` | 使用 Host 已预置组件，可热加载内容；不要求插件自己的进程。 |
| Desktop 自定义 HTML UI | `desktop-webview` | 受控 WebView 与作用域 bridge；不要求插件自己的进程。 |
| Desktop 本地计算、文件/Agent 能力 | `desktop-worker` | 新本机代码使用独立 worker 与 Host Broker；不能把 Flutter Dart AOT 当可下载包。 |
| Mobile 工作台卡片 | `mobile-a2ui` | 只使用当前 OpenMuse 受控组件目录；卡片无任意 JS/HTML。 |
| Mobile 插件详情 | `mobile-webview` | 包内静态内容，CSP 与受控 bridge；高权限动作经过 Host。 |
| Mobile 业务逻辑 | `mobile-quickjs` | 需要额外运行时/政策门禁；首期只给精选开发者。 |
| Web 远程能力 | `web-remote-surface` | 声明式 Surface，经 Cloud/Paired grant；浏览器不直接访问 Desktop 文件路径。 |
| DSH UI/工具 | DSH 自身 SDK | 按 DSH 的包和 profile 管理；OpenMuse 商店可登记兼容信息，但不会替代 DSH 安装合同。 |

同一个 `pluginId` 可以包含多个平台产物，各平台版本可独立推进；必须分别声明 target、运行时、ABI 和所需权限。某端没有实包时，详情页应显示“不支持该平台”，不能复用另一端的包。平台不同本身不产生第二个插件 ID。

## 从创建到发布

```text
openmuse-plugin init my-plugin --target desktop-worker
openmuse-plugin dev --host ./fixtures/host.json
openmuse-plugin validate
openmuse-plugin test --tck --target macos-aarch64
openmuse-plugin pack --channel beta
openmuse-plugin submit ./dist/my-plugin.omplugin --channel beta
openmuse-plugin status <submission-id>
```

建议的 CLI 语义：`init` 生成锁定 SDK 版本的模板；`dev` 启动 Mock Host 并记录 Broker 请求；`validate` 检查 Manifest、目标、权限、许可和资料完整性；`test` 运行与服务端相同的 TCK fixtures 并输出机器可读 JSON；`pack` 生成不可变包、SHA-256、SBOM 与构建来源；`submit` 经短时直传 URL 上传，服务器独立验算 digest；`status` 显示扫描、审核与发布结果。输出必须显示 Host API、A2UI Profile、QuickJS ABI、Web Bridge API 的具体版本，不用模糊的“兼容最新版本”。

## Manifest 与权限

当前 Manifest v2 的真源是 `Muse-Client/schemas/openmuse.plugin.v2.schema.json`。模板固定一个 Client tag/commit，并在 CI 以其 Rust/Dart parser 和 fixtures 验证。开发者为每个 target 声明 `supported/unsupported`，只有 `supported` target 才可附带 artifact。`requested_permissions` 是申请，不是授权；每个能力请求应提供用户可读用途、数据范围和失败处理。不要在配置里放 Secret、用户绝对路径或生产 token。

推荐能力文档分三层：

1. **宣告**：Manifest 列出权限、contribution、激活条件和外部域名。
2. **授予**：用户/管理员对具体插件版本与 Workspace/设备授予范围和时效。
3. **调用**：运行时经 Broker 发送 `requestId`、deadline、幂等键与资源引用；收到授权拒绝、超时、撤销或离线时安全降级。

若权限、外部域名或数据收集方式扩大，新版提交必须附差异说明；用户更新前重新确认。市场审核通过不会自动赋予设备权限。

## UI 约束与预览

Mobile 工作台的 A2UI 预览使用 Host 固定 Catalog；当前实现的白名单是 `Column/Row/Text/Divider/Card`，上限为 8 个 envelope、24 个组件和 16 KiB 编码消息。代码中使用的是 `version: v0.9`，不能直接上传 v0.9.1 消息并假设可解析。新的 profile 应有独立版本、组件清单和 TCK。详情 WebView 的脚本不能通过全局对象调用任意 Host 命令，只能调用已声明、当前插件作用域内的 bridge 方法。

Desktop UI 的 Native View/ WebView 只承载绘制和输入；文件、Workspace、Agent/DSH 等能力仍由 Host Broker 决策。Web 插件不与 OpenMuse Flutter Web 主应用共享特权 origin；远端 Surface 的 resourceRef/媒体 handle 有时效和授权范围。

## 发布质量清单

- 发布者对源码/媒体拥有授权；包中提供 SPDX 许可、第三方 notices 和 SBOM。
- 每个声明的 target 有真实构建、安装与功能测试；macOS/Windows、Android/iOS、主流浏览器分别出报告。
- 演示权限拒绝、超时、离线、版本不兼容和崩溃恢复；不能用假数据伪装在线统计或真实 DSH 能力。
- 执行包不携带私钥、明文 token、生产 Workspace 路径；网络目的地与数据处理声明和实际行为相符。
- 更新提供兼容说明与数据迁移/回滚策略。发布后的旧 artifact 不可替换；修复必须发新版本。

审核失败返回固定错误码、受影响文件/字段、TCK fixture ID 与可复现命令。开发者修复后提交新 candidate；审核员批准的 digest 必须与 CDN 上最终发布的 digest 一致。
