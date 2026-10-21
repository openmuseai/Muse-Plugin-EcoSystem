# Desktop 开发者指南

本指南对应 DevKit 0.2.0 Workspace/CLI 实现。公开市场当前版本和完整 UI 验收状态见[实现记录](08-DESKTOP-WORKSPACE-CLI.zh-CN.md)。使用前需要支持公开 Workspace 工具和 npm bin 启动的 Host 构建；旧版 Host 不能只靠更新 DevKit 获得这些能力。

## 1. 选择开发 Workspace

在 OpenMuse 选择已有 Workspace，或创建目录并作为 Workspace 打开。安装 DevKit 后，在目标 Workspace **新开应用内终端**；已有终端不会自动得到新的命令路径和短期会话。

```sh
pwd
muse --help
muse search pptx
muse search pdf
```

搜索包含已安装和当前市场已审核插件；已安装 Provider 同时列出公开合同 URI、操作和精确摘要，可直接用 URI 选择依赖。若 Provider 尚未安装：

```sh
muse install io.openmuse/genoffice-pptx
muse install io.openmuse/pdf-reader
```

Host 会显示真实包摘要并请求安装确认。下架版本不允许通过在线搜索新装。离线搜索仍可显示本地已安装项；在线状态不可用会明确标注。

## 2. 在当前目录初始化

若 Workspace 已有 README/main.js 等模板同名文件，先创建一个子目录并进入；其他已有文件会保留。不要在 Host 或 Provider 的源码目录初始化。

```sh
mkdir document-explainer
cd document-explainer
muse init --name document-explainer --capability pptx --capability pdf
```

如果目标 Workspace 本身为空，直接执行 `muse init`，无需额外子目录。

`--capability` 可重复，支持关键词或完整合同 URI。例如精确选择：

```sh
muse init --name document-explainer \
  --capability https://plugins.openmuseai.com/contracts/genoffice/slides-read/v1 \
  --capability https://plugins.openmuseai.com/contracts/pdfjs/pdf-read/v1
```

不要重复执行这两个初始化示例。候选有歧义或尚未安装时，命令停止并提示搜索/安装。

生成文件：

```text
main.js                 # 浏览器业务模块，export async function run(api)
devkit.project.json     # 名称、版本、功能需求
devkit.lock.json       # Host 构建、直接 Provider 版本/摘要、合同（无账号令牌）
README.md
.gitignore              # 增补本地状态/包/报告的忽略规则
```

这里的配置是公开 DevKit 工具格式，不是 MCP 保留方法或 MCPB 私有字段。实际 Schema 位于 `contracts/devkit-v1/`；`examples/` 中更复杂的最初设计示例尚未实现，不能直接替代当前配置。

## 3. 在同一 Workspace 中开发

通过现有文件树打开 `main.js`，使用已有编辑器或 Agent 修改。DevKit 不再提供第二个编辑器。模板使用：

```js
export async function run(api) {
  const documents = await api.readAll();
  return documents.map(({ capability, snapshot }) => ({
    capability,
    pages: snapshot.pageCount,
    text: snapshot.pages.slice(0, 3).map(page => page.text),
  }));
}
```

`api.readAll()` 调用用户已经绑定的 Provider。具体页结构来自锁定的 PPTX/PDF 公开合同，Host 不解析这些字段。当前示例只读取资料，未自动调用远端模型；请不要把它称为已经实现的 AI 讲解。

## 4. 应用内真实调试

```sh
muse check
muse dev
```

确认运行候选包，随后在应用内 View：分别选择 PPTX 与 PDF，确认各自 Provider/工具授权，再点击“运行 / 比较全部资料”。同一候选可同时保留两份绑定，切换焦点不会替换资料。

返回终端：

```sh
muse report
muse pack
```

`muse report` 从此终端创建的候选资源读取报告；未运行、调用失败或修改过代码时不能冒充通过。`.devkit/run.json` 只保留不透明 runRef；关闭终端后凭据及其开发运行授权失效。默认会话有效期 4 小时。

`dist/<id>-<version>.mcpb` 为不可变产物。同版本已存在不同字节时拒绝覆盖。发布新版本先在 `devkit.project.json` 修改 SemVer，重新调试并打包；能力依赖更新本期须重新解析，暂未提供 `muse add/resolve` 命令。

## 5. 提交审核

```sh
muse submit
```

交互式终端隐藏输入开发者令牌；CI 可从其密钥系统注入当前进程的 `MARKET_DEVELOPER_TOKEN`。不在命令参数、源码、锁文件或日志放令牌。市场地址使用 Host 选择的 `MCP_REGISTRY_URL`，默认生产市场 HTTPS。

当前生产开发者身份为受控静态凭据与 namespace，不是公开自助 OIDC 平台。非 `io.openmuse` 命名空间需要市场分配身份；通过进程 `MCP_PUBLISHER_NAMESPACE` 选择对应命名空间，不能靠设置字符串越权。

返回 submission ID、pending、包摘要和版本；本地保存 `submission.json`。提交不自动批准；等待审核后在正常客户端市场安装验收。DevKit/消费者均不获得审核员凭据。

## 故障定位

| 提示 | 处理 |
| --- | --- |
| `muse: command not found` | 安装新 DevKit，使用兼容 Host，在 Workspace 新开终端 |
| 缺少短期 MCP 会话 | 从应用内 Workspace 终端运行；不复制其他账号/终端的令牌 |
| 超出授权 Workspace | 在正确根目录新开终端，或回到其子目录 |
| EEXIST | 模板文件冲突；保留已有文件，在空目录重试 |
| 多个候选 | 使用完整合同 URI 精确选择 |
| Provider unavailable/changed | 核对锁文件与已安装版本；更新依赖后重新测试 |
| 报告 stale/incomplete | 重新 `muse dev`，选择全部真实资料，运行并 `muse report` |
| 同版本字节不同 | 提升项目版本，重新测试和打包 |

Android/Web 真机开发、Live 编辑会话、远程构建和自动审核认证尚未完成；不要以 Desktop CLI 测试替代这些验收。
