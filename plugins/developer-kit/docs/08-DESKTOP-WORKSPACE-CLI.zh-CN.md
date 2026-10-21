# Desktop Workspace / CLI 实现与验收记录

日期：2026-10-21。分支：两仓库 `feat/plugin-devkit-desktop`。本文优先于旧设计中“独立 DevKit 工作台/可选 CLI”的描述。

## 本次实现

实际路径：**选已有/新建 Workspace → 应用内终端搜索/安装插件 → CLI 选择多项依赖并原地初始化 → 现有编辑器/Agent 开发 → 应用内候选调试 → 打包 → 提交待审**。

| 层 | 代码 | 状态 |
| --- | --- | --- |
| Host | `mcp_workspace_tools.dart` / `mcp_terminal_service.dart` | 公开 Workspace/Registry 工具、随机 loopback 标准 MCP、每终端/账号/根目录短期凭据 |
| Host | `mcp_bin_registry.dart` / `plugin_cli.dart` | 通用 npm bin 发现、冲突排除、文件摘要校验、透明命令启动 |
| Host | `mcp_installed_app.dart` / `mcp_capability_gateway.dart` | 独立候选 View、标准工具/资源路由、逐消费者资源绑定和授权、关闭/撤销处理 |
| 终端插件 | `plugins/cli` | 在授权 Workspace 创建 shell，注入通用会话和命令路径，退出释放 |
| DevKit | `packages/devkit-cli` / `packages/devkit-core` | CLI 参数、1–8 项直接依赖、cwd 事务初始化、检查/候选/报告/打包/待审提交 |
| DevKit 页面 | `plugins/developer-kit/web` | Workspace 指导与能力搜索；复用现有编辑器和 Agent |
| 公共合同 | `contracts/devkit-v1` | 普通工具 Schema、目录/项目/锁文件 Schema 和协议边界说明 |

Host 未加入 DevKit、PPTX 或 PDF ID 的特权分支。DevKit/Core/SDK 不导入 Muse-Client；PPTX/PDF 业务在对应插件。

## 可重复验证

从生态仓库：

```sh
npm ci
npm run typecheck
npm run build:devkit
node plugins/developer-kit/scripts/pack.mjs
npm run test:devkit
```

从 Client 的 `app/openmuse_host`：

```sh
flutter analyze --no-pub
# 可选：独立编译通用 launcher 到临时目录，不改运行中的 App
dart build cli -t bin/openmuse.dart -o /tmp/openmuse-devkit-cli-build
OPENMUSE_TEST_CLI_LAUNCHER=/tmp/openmuse-devkit-cli-build/bundle/bin/openmuse \
  flutter test --no-pub \
  test/mcp_terminal_service_test.dart \
  test/mcp_capability_gateway_test.dart \
  test/workbench_shell_test.dart \
  test/devkit_workspace_cli_test.dart
```

`devkit_workspace_cli_test.dart` 需要先构建本地 DevKit 0.2.0、GenOffice PPTX 0.6.1、PDF Reader 0.1.1 的 MCPB。维护者构建这些测试夹具；第三方开发者只安装发行包。未提供 launcher 时测试仍可直接启动包中 CLI，提供后额外覆盖 Host shim/已编译 launcher。

### 已通过的证据

- TypeScript 类型检查、DevKit 构建/确定性打包。
- 生态测试 **6 通过**：项目/CAS/不可变包、依赖冲突、Workspace 冲突回滚及报告符号链接、精确 HTML 脚本解析、真实 PPTX/PDF Provider。
- Host 分析无问题；终端/网关/Workbench 测试 **24 通过、1 跳过**；真实 Provider 经 Host 网关测试另 **1 通过**。跳过项属于现有 workbench 的 fixture 门禁，不作功能通过依据。
- 终端插件 **4 通过**；插件市场 **4 通过**。
- 独立通用 launcher 构建成功。协议测试通过实际 shim 启动已打包 `muse`；Workspace、安装和临时路径包含空格。
- 实际 stdio Provider 读取 **23 页 Sample_ppt.pptx** 与 **2 页 PDF**，初始化双依赖项目、编辑源码、候选 UI 资源包含修改、记录报告、生成与候选摘要相同的 MCPB。
- 路径越界、重复初始化覆盖、被改动的安装包、缺凭据/浏览器 Origin/账号切换/请求中撤销均有拒绝验证。
- 生成的实际项目与锁文件通过公开 Schema 校验。

**headless 协议测试未打开原生 View，也没有操作真实文件选择器。测试由客户端调用候选自己的记录工具生成报告，不能作为人工 UI 已通过或服务端认证的证据。**

## 发行状态

2026-10-21 只读核对生产目录：

| 发行包 | 生产状态 | 包摘要 |
| --- | --- | --- |
| DevKit 0.1.1 | 已审核历史版本，旧页面流程 | `13ba93760ac9e42e0bc07fa84c016fe6373c287381b14aa732010eac24e41cb0` |
| DevKit 0.2.0 | **active，已完成工具包维护审核** | `d6abad26572628f67609c73cbd194b54c17b4d0da6b2967b88d03b8abe77cf6a` |
| GenOffice PPTX 0.6.1 | active，只读快照合同 1.0.1 | `b522cc46a1b758776939ca1617a488799e0929d50c86b5fac7ba5839b7c6f96d` |
| PDF Reader 0.1.1 | active，真实 PDF.js 文本合同 1.0.1 | `e5f56aaafae6728d7ab34f55eaccd46a3f6554cd003a90e0780679650d0b5f69` |

0.1.0 因包内脚本损坏已下架，不能作为验收版本。0.2.0 已由开发者接口提交，再由独立维护审核批准；submission ID 为 `131ab0fb-7001-4099-ae08-9d821e956723`。生产公开包与本地候选摘要一致，公开 Profile/Schema 与仓库逐字节一致。开发者 CLI 未获得审核员凭据。

## 已完成的 Desktop 原生闭环

最终 Host 源码 `d2aad9a`，完整 ZIP SHA-256：`fd60eb306f6c47e855532df58aaf7395dc63de454ac26dbb5438babb288af89d`。运行中 Host 摘要 `e10576041b17aea363537a0f14a7601b280ca706fec7ec88866f5df2b48ad714` 与项目锁文件一致。完整构建含 DSH、Node、CLI、Helix；最终签名、entitlement 和 ZIP 主执行文件一致性已核对。其后的 Client 提交 `e1e3baa` 仅增强测试。

| 步骤 | 实际操作与结果 | 证据文件 |
| --- | --- | --- |
| 安装 DevKit | 生产市场原生页面安装 0.2.0；打开插件页面显示真实 Workspace 与 Host 摘要 | `01-market-installed.png`、`02-devkit-workspace.png` |
| 能力搜索 | 应用内 `muse search pptx/pdf` 显示已安装、在线目录和公开合同 URI | `03-pptx-capability-search.png`、`04-pdf-capability-search.png` |
| 更新 Provider | 应用终端 `muse install` 从生产 HTTPS 市场安装 0.6.1 / 0.1.1，包摘要相符 | `09-pptx-061-installed.png`、`10-pdf-011-installed.png` |
| Workspace 初始化 | 用户已有 explainer Workspace，新建项目目录后 CLI 同时选择 PPTX/PDF，生成精确版本/合同/摘要锁 | `11-validated-project-initialized.png`、`devkit.lock.json` |
| 应用内开发 | 在 Workspace 终端运行独立源码修改脚本，保存 main.js 标题，`muse check` 通过；现有 Helix 查看最终源码 | `12-validated-code-check.png`、`19-workspace-source-and-pending-receipt.png` |
| 原生候选调试 | `muse dev` 打开应用内候选；原生文件选择器分别选择指定 PPTX 与 PDF，并逐 Provider 授权 | `13-pptx-061-authorization.png`、`14-pdf-011-authorization.png` |
| 实际执行 | 点击运行；原版 GenOffice 引擎返回 **23 页**，PDF.js 返回 **2 页**，修改后的业务标题生效 | `15-native-run-pptx-passed.png`、`16-native-run-pdf-passed.png` |
| 报告与打包 | `muse report` 接受运行报告；`muse pack` 摘要等于已测候选 | `17-report-and-immutable-package.png`、`test-report.json` |
| 提交待审 | `muse submit` 隐藏输入开发者凭据，实际上传生产市场；服务端只读确认 pending | `18-production-submission-pending.png`、`submission.json`、`market-verification.json` |

证据目录：[2026-10-21-desktop](evidence/2026-10-21-desktop/)。`01`–`08` 含早期安装/故障定位过程；最终成功调试使用 `09`–`19`、最终锁文件和 release.json。源码修改通过**应用终端脚本**完成；没有把原生编辑器快捷键保存或 Agent 自动编码宣称为已验收。

验收项目：`plugins/explainer/desktop-acceptance-validated`。消费者 `io.openmuse/desktop-document-explainer@0.1.0`：

- submission ID：`cc85fd4a-4dd3-450f-902a-b3f4cc7c10d0`，服务端状态 **pending**。
- 候选、报告、打包、上传 SHA-256：`f2e2f4e0d8dd01d014f7d0e69f623484a2c0d1d791fb3d6a8826a0b8835f6e82`。
- 审核前不出现在公开目录，直接公开下载返回 **404**。未批准消费者；新安装/下架不属于此次“提交审核”出口。
- 包中不含本机路径、开发者凭据或测试文档内容。测试报告是开发客户端报告，不是服务端可信认证。

### 本轮发现并修复的问题

1. **终端入口生命周期**：空 Agent 视图隐藏了编辑器区域，且底部终端绕过插件激活，导致没有短期会话/PATH。Host 现在先通过通用 Registry 激活贡献终端的插件，再打开可见终端；插件缺少上下文时明确失败。
2. **最终 macOS 包丢权限**：刷新 ad-hoc 外层签名时未带 entitlement，文件选择器在显示前拒绝。打包现在使用对应构建配置的 entitlement 重签，最终包必须通过独立校验脚本。
3. **大文件 Schema 正则栈溢出**：旧 Provider 的重复分组 base64 正则在约 5.5 MiB PPTX 上触发 Dart 正则栈溢出。PPTX 0.6.1 / PDF 0.1.1 的合同 1.0.1 采用标准编码/MIME 注解与长度预算，Provider 做严格 canonical base64 验证。Host 不跳过 Schema，也无格式特判。
4. **测试覆盖缺口**：原协议测试直接调用 Provider，漏掉 Host 输入输出校验。现在实际资源经过 choose → bind → call 网关，支持 `OPENMUSE_TEST_PPTX` 指向指定文件；原错误可复现，补丁通过。

失败的早期生成项目保留在仓库本地忽略目录 `dist/devkit-acceptance-attempts-20261021`，未删除文件。最终示例与证据独立保留。

## 完整产品的剩余范围

本期直接依赖只读快照不等同于完整计划：未保存编辑会话/导航/预览/写入、Agent/Voice 公共 API、传递依赖图、独立 Dev Host 应用身份与 OS 沙箱、OIDC/namespace 自助开发者、Android/Web DevKit 和远端 Runner 均有后续任务。SDK/CLI 当前随 MCPB 捆绑，不是已公开 npm 产品。
