# 使用 DevKit 开发多能力插件

## 适用范围

这是一份面向计划中 DevKit 1.0 的开发者操作规范。产品尚未实现；示例命令、SDK 名和合同 ID 是拟定接口，不能作为当前可运行命令。实现后的指南需要由 CI 对可安装发行物执行验证，再移除本说明。

开发者只需了解所用能力的公开 API，使用 Host 和 Provider 发行包。SDK 本身按普通语言包安装，不要求把 Muse-Client 或 Provider 源码作为 Git 子模块。

## 安装工具并准备环境

在 OpenMuse 的插件市场安装“插件开发工具”，打开工作台中的 DevKit。环境检查页显示当前 Host、开发通道状态、项目目录权限、可用 Runner、磁盘、网络、运行时和目标设备。

Desktop 使用 DevKit 对应的本地 Runner；首次需要时下载受校验的工具链和 Dev Host。Android 可以编辑项目及预览，完整构建使用用户选择的云端或其他设备 Runner。手机发布插件不要求存在一台 Desktop，也不要求在手机启动 Node 或连接 `127.0.0.1`。

正式客户端中的 DevKit 只管理项目和发行包；未审核代码的执行放入隔离 Dev Host 或明确的开发通道。开发授权不进入发布包。

## 创建同时支持 PPT 和 PDF 的插件

1. 点击“创建项目”，选择“资源协作插件”。
2. 输入项目名 `document-explainer`，选择空目录或新建子目录。
3. 选择 macOS 和 Android 作为目标，Host 版本默认 latest。
4. 添加 PPT 讲解、PDF 讲解、双资料比较三个功能。
5. 在能力选择器分别添加 Slides API、PDF API 和 Agent API；Voice 可设为可选。
6. 检查每端的候选 Provider、版本、权限和依赖安装计划。
7. 初始化。DevKit 生成工程并下载已选择的 API 包和 Provider 发行物。

选择多个能力不会把它们合成一个插件 ID。最终产品使用自己的插件 ID；GenOffice、PDF Provider 和 Agent 仍独立安装、维护和更新。

### 初始化后的工程

```text
document-explainer/
├── package.json
├── devkit.project.json          # 公开开发工具配置
├── devkit.lock.json             # 已解析 Host、合同、SDK、Provider 和摘要
├── src/
│   ├── app.tsx
│   ├── features/ppt-explain.ts
│   ├── features/pdf-explain.ts
│   └── features/compare.ts
├── generated/                  # 从合同生成的客户端和类型
├── contracts/                  # 被锁定的公开合同副本
├── tests/fixtures/              # 人工授权使用的样例
├── tests/contract/
├── tests/host/
├── docs/PRIVACY.md
└── .devkit/                     # 本机缓存、会话；不进入 Git 或发布包
```

配置示例见 [双格式项目](../examples/devkit.project.example.json)；本目录提供对应 JSON Schema。配置是 DevKit 公开工具格式，不是 MCP/MCPB 官方 Manifest，不传入 Host 作为运行时私有命令。

### 三类依赖

| 类型 | 含义 | 发布时的处理 |
| --- | --- | --- |
| 语言依赖 | 通用 SDK、UI 库、API 类型包 | 构建并锁定，生成 SBOM |
| 能力依赖 | Slides/PDF/Agent/Voice Provider | 公开合同要求与兼容范围；用户端安装/绑定 |
| 开发依赖 | Mock、测试工具、Dev Host、构建工具链 | 只用于开发和测试，不随运行包提供系统权限 |

同一 Provider 的多项操作应绑定到同一兼容实例，例如从同一 GenOffice 会话读文字和取预览。锁文件冲突时显示不满足条件的最小依赖集合，不默默换版本或跨实例拼接状态。

## 编写业务代码

下例为拟定 SDK 伪代码，用于说明调用边界；API 名在合同阶段冻结后生成可编译示例。

```ts
// 两份资源由用户分别选择并授权，不读取整个 Workspace。
const { presentation: ppt, paper: pdf } = await runtime.resources.pickMany({
  roles: { presentation: { mediaType: "application/vnd.openxmlformats-officedocument.presentationml.presentation" },
           paper: { mediaType: "application/pdf" } },
});
const slides = await SlidesApi.bind(runtime, { resource: ppt, access: ["read"] });
const paper = await PdfApi.bind(runtime, { resource: pdf, access: ["read"] });

const deck = await slides.readSnapshot();
const pages = await paper.readSnapshot();
const result = await AgentApi.bind(runtime).then(agent => agent.generate({
  input: { deck, pages }, outputSchema: ComparisonSchema,
}));
```

`slideId`、页码、备注、选区等业务类型来自 Provider API 包，Host 不解释。生成的客户端负责工具映射、输入输出校验和 Provider 错误转换，不直接读取另一个插件的 DOM、安装目录或 Electron IPC。

PPT/PDF 单资料功能分别绑定一份资源。双资料比较的两个资源都有独立会话及版本，不能用“最后活动资源”替代其中一个。使用 Agent 时清楚展示数据是否发送到远端模型。

## 在应用内开发

文件树中新建文件，编辑器提供补全、诊断、保存状态和错误定位。点击“Agent”可让用户选择的 Agent 按需求生成补丁。查看修改差异，再运行测试；业务代码和依赖版本修改分别记录。

对已有工程使用“导入”，只读扫描通过后再允许安装依赖和启动任务。构建在 Runner 中执行，DevKit UI 无任意 shell 权限。应用退出或插件停用时可取消任务；已提交到远端的任务需显示其实际状态，不能仅隐藏页面。

## 调试顺序

| 模式 | 操作 | 你能证明什么 |
| --- | --- | --- |
| Mock | 选择固定 PPT/PDF 状态和错误夹具 | 自己的业务逻辑与 UI |
| 真实 Provider | 下载已审核发行包，在 Dev Host 打开样例 | API 合同和跨插件调用 |
| 真机 | 安装候选包及依赖，在目标设备点击使用 | 该设备、该摘要、该能力组合可运行 |

Mock、真实运行和真机分别有报告，不互相覆盖。真实调试的资料由用户授权，本地文档不会为构建自动上传到云端。需要云端测试夹具时单独选择并说明上传目的。

查看调用链时，先看资源与 Provider 绑定，再看权限、Schema、版本冲突和耗时。热更新只更换当前开发插件；PPT/PDF 会话继续保留。文档关闭、Provider 更新或授权失效时重新绑定；不要直接改正在编辑的磁盘文件。

## 设备测试与发布

1. 在设备页选择完整 Dev Host，固定版本、构建摘要、系统与 WebView 信息。
2. 安装候选插件及其依赖，测试 PPT、PDF、双资料比较和可选语音。
3. 验证切换标签、未保存修改、授权撤销、Provider 禁用、断网与恢复。
4. 在发布页填写版本、隐私、许可证、源码/构建来源，确认目标功能与依赖。
5. 运行校验和 TCK，生成不可变包、摘要、SBOM 与证据清单。
6. 登录选定市场上传并提交审核。页面显示 submission ID 和 pending。
7. 审核通过且目录可见后，在正常客户端安装验证；不把 Dev Host 成功等同于正式客户端验收。

运行已发布产品无需 DevKit；卸载 DevKit 不影响该产品的正常使用。市场下架阻止新安装，已安装副本按 Host 政策管理，不删除用户生成的文件。

## 可选 CLI 与 CI

以下命令为拟定接口；实现后由 DevKit 页面调用相同核心，CI 也使用同一格式：

```sh
muse doctor
muse create document-explainer --template resource-companion --host latest
muse capability add slides pdf agent
muse resolve --frozen=false
muse dev --mode mock
muse dev --mode providers --target macos
muse test --contracts
muse test --device android
muse pack --frozen
muse publish --registry https://plugins.openmuseai.com
```

开发者凭据保存在凭据存储中，CI 由其密钥系统注入，不能写入配置、日志、截图或锁文件。发布命令不包含自动审核。

## 能力提供者与开发 Skill

Provider 作者发布合同、Schema、API 客户端、Mock、夹具和契约测试。API 合同与实现版本分别管理；破坏性变更先发布新主版本和迁移说明，再验证下游组合。

SDK 随版本提供开发 Skill 和 API Context Pack：公开合同、最小示例、目标端限制、错误处理、测试命令、发布边界。Agent 读取它们即可开发；UI 与 Agent 共用项目工具，不能各自维护一套私有发布脚本。
