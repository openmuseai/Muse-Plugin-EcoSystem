# OpenMuse Plugin Ecosystem

独立的第三方插件源码、开发指南和市场服务。插件与客户端只通过公开规范交互：运行时 [MCP](https://modelcontextprotocol.io/specification/2026-07-28)、Desktop 交付 [MCPB](https://github.com/modelcontextprotocol/mcpb/blob/main/MANIFEST.md)、发现与发布 [MCP Registry v0.1](https://github.com/modelcontextprotocol/registry/blob/main/docs/reference/api/openapi.yaml)、声明式移动界面 [A2UI](https://a2ui.org/specification/v0.9.1-a2ui/) 或 [MCP Apps](https://apps.extensions.modelcontextprotocol.io/)。插件包不引用客户端源码、私有 Manifest、内部命令或字段。

本仓库当前实现了独立的本地市场服务、审核状态、MCPB 上传、公开目录、GenOffice PPTX MCP 插件、AppFlowy Editor 跨端插件，以及 Desktop 的 stdio、Mobile 的 Streamable HTTP/A2UI 和审核包离线 Web/Wasm 交付。AppFlowy Editor `0.1.3` 在 Android 应用内安装后可不连接开发机直接打开、编辑和恢复文档。服务目前是**可联调原型**；生产部署需要 OIDC 身份与命名空间归属、恶意软件扫描、隔离运行、签名、审计、对象存储和高可用数据库。Web 尚未完成接入。

## 快速验证

```sh
cd plugins/genoffice-pptx
npm ci
npm test
npm run pack:desktop
cd ../..
MARKET_DEVELOPER_TOKEN=dev-local MARKET_REVIEWER_TOKEN=review-local \
  python3 server/market.py --listen 127.0.0.1:8765 --data .market-data
```

另一终端执行：

```sh
python3 plugins/genoffice-pptx/scripts/publish.py \
  plugins/genoffice-pptx/dist/genoffice-pptx-0.2.0.mcpb \
  --registry http://127.0.0.1:8765 --token dev-local \
  --remote http://127.0.0.1:8767/mcp
curl -X POST -H 'Authorization: Bearer review-local' \
  -H 'Content-Type: application/json' --data '{"note":"reviewed"}' \
  http://127.0.0.1:8765/internal/reviews/1/approve
curl http://127.0.0.1:8765/v0.1/servers
```

Desktop 客户端设置 `OPENMUSE_MCP_REGISTRY_URL=http://127.0.0.1:8765` 后，插件市场读取公开目录，一键安装并通过 MCP 调用。无此配置时，现有内置商店仍可独立使用。生产环境使用 HTTPS 地址。

Mobile 远端示例需另开终端在 `plugins/genoffice-pptx` 运行 `npm run serve:http`，并设置同一 `OPENMUSE_MCP_REGISTRY_URL`。Mobile 在线 MCP 页面读取 `server.json.remotes`，安装时连接远端 MCP、检查工具和 A2UI 资源，使用时由用户选择文件。Android 真机安装、页面点击与 PPTX 调用已通过；本机联调可用 `adb reverse tcp:8765 tcp:8765` 和 `adb reverse tcp:8767 tcp:8767`。生产环境须使用 HTTPS 和鉴权。移动端调用会把用户选择的文件发送给远端 MCP 服务，部署前必须明确隐私政策。

## 文档

- [Easel 社媒插件、安装引导与发布方案](plugins/easel/README.zh-CN.md)（独立 MCPB，Desktop macOS）
- [Plugin DevKit 插件产品、开发者指南、技术方案与开发计划](plugins/developer-kit/README.zh-CN.md)（设计阶段，包含 PPTX/PDF 多能力依赖与双资源协作）
- [Word 产品插件工程、跨端架构与开发计划](plugins/word/README.zh-CN.md)（资源与签名包骨架；内核和 Flutter 编辑表面保留在 `ioffice`）
- [产品与平台方案](docs/PRODUCT.zh-CN.md)
- [架构、服务和信任边界](docs/ARCHITECTURE.zh-CN.md)
- [MCP、A2UI、WebView 与 Wasm 技术选型](docs/PLUGIN-PROTOCOL-SELECTION.zh-CN.md)
- [AppFlowy Editor 跨端交付与验收](docs/EDITOR-PLUGIN-DELIVERY.zh-CN.md)
- [开发、打包、上传、审核指南](docs/DEVELOPER-GUIDE.zh-CN.md)
- [手机创作与 Mobile/Web 交付](docs/MOBILE-AGENT-STUDIO.zh-CN.md)
- [GenOffice PPTX 拆分与范围](docs/GENOFFICE-PPTX.zh-CN.md)
- [交付清单](docs/ROADMAP.zh-CN.md)
- [代理开发 Skill](skills/build-mcp-plugin/SKILL.md)

`compatibility/clients.json` 是**公开互操作测试矩阵**，开发者选择客户端版本时默认最新。它只选择测试目标，不注入插件包，也不成为运行时的私有兼容字段；最终可用性由客户端与插件在 MCP 协议协商、MCPB 标准兼容声明和标准 JSON Schema 能力发现中确定。

Design details: [docs/MARKET-SERVICE-ARCHITECTURE.zh-CN.md](docs/MARKET-SERVICE-ARCHITECTURE.zh-CN.md).
