# 第三方插件开发与发布

## 1. 选择兼容目标

查阅 [`compatibility/clients.json`](../compatibility/clients.json)。`publish.py --client` 选择 Desktop 或 Mobile（默认 Desktop），`--client-version` 默认为该客户端的 `latest`；也可以指定矩阵已有的精确 SemVer。矩阵只选择公开协议互操作测试目标，不在包中写客户端内部字段。插件真正运行时由 MCP 协议发现、标准 JSON Schema 和 MCPB `compatibility` 判断能力。

## 2. 独立开发

用 Node、Python、Rust 或其他语言写 MCP Server。工具参数与输出使用 JSON Schema；处理文件时可用 `contentEncoding: base64`、`contentMediaType`，由 Host 发起用户选文件。插件不得索取 Workspace 内部路径、客户端私有 token 或 Host 私有命令。需要 UI 时用 A2UI over MCP 或 MCP Apps。Desktop 本地分发打包成 MCPB；Mobile 可提供远端 MCP Streamable HTTP，或按公开静态站点 profile 把 Web/Wasm 资源随已审核 MCPB 分发。用官方 MCP SDK 和独立 MCP 客户端做互操作测试。

PPTX 示例：

```sh
cd plugins/genoffice-pptx
npm ci
npm test
npm run pack:desktop
```

`npm test` 使用官方 TypeScript MCP 客户端调用真实 GenOffice PPTX 样本，验证工具发现与结构化结果。`pack:desktop` 输出 `dist/genoffice-pptx-0.2.0.mcpb` 和 `dist/mcpb.sha256`。包中只含标准 `manifest.json` 与自包含 Node server，不含客户端私有 Manifest。

## 3. 上传并提交审核

启动独立服务，设置不同的开发者与审核员 Bearer 令牌（本机样例见仓库 README）。发布命令上传包到按摘要命名的 URL，再向 MCP Registry 标准 `/v0.1/publish` 提交 `server.json`：

```sh
python3 plugins/genoffice-pptx/scripts/publish.py \
  plugins/genoffice-pptx/dist/genoffice-pptx-0.2.0.mcpb \
  --registry http://127.0.0.1:8765 --token dev-local \
  --client-version latest --remote http://127.0.0.1:8767/mcp
```

返回 `submissionId` 和 `pending`。批准前 `GET /v0.1/servers` 不包含该插件、包下载返回 404。开发者可查询 `GET /v0.1/submissions/{id}`（开发者令牌）。审核员走独立后台 API，批准后客户端刷新在线市场即可看到条目。生产流程需要自动扫描、命名空间校验和带审计的审核台；本地批准命令仅供联调。

## 4. 验收

```sh
python3 -m unittest discover -s server -v
cd plugins/genoffice-pptx && npm test
```

Desktop Host 设置 `OPENMUSE_MCP_REGISTRY_URL` 指向已批准目录后，打开插件市场，一键安装。标准 MCPB 安装路径由 Host 管理。用户选中兼容的 PPTX 文件时，Host 通过 MCP tool 调用，不依赖插件私有字段；PPTX 示例目前提供结构预览和 Engine roundtrip 测试，不是完整图形编辑器。

Mobile 读取同一目录条目中的标准 `remotes`。远端 MCP 服务需自行部署，使用 HTTPS 和用户授权；本地示例可先运行 `npm run serve:http`。Mobile 安装会连接端点，校验 `tools/list` 和 A2UI 资源，然后保存安装记录。选择文件后通过工具参数发送文件内容；远端处理会上传所选文件，开发者应清楚说明数据处理与保留策略。A2UI 的完整动态绘制仍属于后续工作。

## 发布质量要求

版本不可覆盖；每次变更提升 SemVer。提交源码链接、许可证、隐私说明、构建来源、依赖清单、截图和平台 TCK 结果。避免把凭据或绝对本机路径放进包。生产审核会检查下载代码的运行权限、网络目标、资源预算和操作系统政策。用户使用远端插件时，说明数据是否上传及保留时间。

### 大文件的公开输入 Schema

对多 MiB 的二进制内容，使用有长度上限的字符串及标准 `contentEncoding: base64`、`contentMediaType` 注解。避免重复分组正则：部分客户端正则引擎会在合法的大文件上栈溢出。编码注解本身不负责验证，Provider 必须在解码前限制编码长度，并在解码后验证 canonical base64（例如回编码比较）、字节数和格式预算。请同时测试真实 Host 的能力网关与独立 MCP 客户端，不能只测试直接调用 Server。
