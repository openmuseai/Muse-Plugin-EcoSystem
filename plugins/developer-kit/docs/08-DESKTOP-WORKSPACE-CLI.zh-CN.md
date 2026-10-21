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

`devkit_workspace_cli_test.dart` 需要先构建本地 DevKit 0.2.0、GenOffice PPTX 0.6.0、PDF Reader 0.1.0 的 MCPB。维护者构建这些测试夹具；第三方开发者只安装发行包。未提供 launcher 时测试仍可直接启动包中 CLI，提供后额外覆盖 Host shim/已编译 launcher。

### 已通过的证据

- TypeScript 类型检查、DevKit 构建/确定性打包。
- 生态测试 **6 通过**：项目/CAS/不可变包、依赖冲突、Workspace 冲突回滚及报告符号链接、精确 HTML 脚本解析、真实 PPTX/PDF Provider。
- Host 分析无问题；针对性 Host 测试 **24 通过、1 跳过**。跳过项属于现有 workbench 的 fixture 门禁，不作功能通过依据。
- 终端插件 **3 通过**；插件市场 **4 通过**。
- 独立通用 launcher 构建成功。协议测试通过实际 shim 启动已打包 `muse`；Workspace、安装和临时路径包含空格。
- 实际 stdio Provider 读取 **23 页 Sample_ppt.pptx** 与 **2 页 PDF**，初始化双依赖项目、编辑源码、候选 UI 资源包含修改、记录报告、生成与候选摘要相同的 MCPB。
- 路径越界、重复初始化覆盖、被改动的安装包、缺凭据/浏览器 Origin/账号切换/请求中撤销均有拒绝验证。
- 生成的实际项目与锁文件通过公开 Schema 校验。

**headless 协议测试未打开原生 View，也没有操作真实文件选择器。测试由客户端调用候选自己的记录工具生成报告，不能作为人工 UI 已通过或服务端认证的证据。**

## 发行状态

2026-10-21 只读核对生产目录：

| 发行包 | 生产状态 | 包摘要 |
| --- | --- | --- |
| DevKit 0.1.1 | active，旧页面流程 | `13ba93760ac9e42e0bc07fa84c016fe6373c287381b14aa732010eac24e41cb0` |
| DevKit 0.2.0 | **本地候选，未发布** | `d6abad26572628f67609c73cbd194b54c17b4d0da6b2967b88d03b8abe77cf6a` |
| GenOffice PPTX 0.6.0 | active，只读快照公共合同 | `d250a7d1422107317570ebf67acb2c6a21485b8241ed4237fe6e10b5423b6672` |
| PDF Reader 0.1.0 | active，真实 PDF.js 文本能力 | `24ac8b419edb0b7564f66bd75a6ab91310f3670bf03e54d366b7c2df762f3f7e` |

0.1.0 因包内脚本损坏已下架，不能作为验收版本。0.2.0 需要包含本次通用 CLI/Workspace 能力的新 Host；不能将用户当前运行的旧完整构建误认作已包含此代码。

## 待完成的原生 UI 验收

用户当前保留 OpenMuse 窗口操作权，本次没有接管、重启或覆盖其运行应用。以下项仍待执行：

1. 新 Host 完整 macOS 包构建、摘要记录及安装启动。
2. 部署更新公开 Profile/Schema，发布/审核匹配的 DevKit 0.2.0，从真实生产市场安装。
3. 选择用户已有 Workspace 或新建验收目录，新开终端；真实 `muse search/install/init`。
4. 通过现有编辑器或 Agent 修改项目，`muse dev` 打开原生应用内候选 View。
5. 用户分别授权 PPTX/PDF 文件和 Provider；实际点击运行并保存界面证据。
6. 返回终端 `muse report/pack/submit`，保存真实 **pending submission ID**，后台只读核对；不自动批准消费者。
7. 确认待审不在公开目录。消费者的审核批准、新安装、停用/卸载另按生命周期门禁测试。

**当前没有上述 Workspace 消费者的真实待审提交回执，不宣称 Desktop 完整闭环完成。**

## 完整产品的剩余范围

本期直接依赖只读快照不等同于完整计划：未保存编辑会话/导航/预览/写入、Agent/Voice 公共 API、传递依赖图、独立 Dev Host 应用身份与 OS 沙箱、OIDC/namespace 自助开发者、Android/Web DevKit 和远端 Runner 均有后续任务。SDK/CLI 当前随 MCPB 捆绑，不是已公开 npm 产品。
