# PDF Capability Provider 0.1.0

独立标准 MCPB 插件，使用 Mozilla PDF.js 6.4.299（Apache-2.0）读取已授权 PDF 的文字层。首版仅验证 macOS Apple Silicon / Node ≥22.13；内置对应平台的 `@napi-rs/canvas` 原生依赖。它是供其他插件组合使用的能力 Provider，首版没有独立可视化阅读器。

公开合同资源：`capability://pdf-reader/contracts`，MIME `application/vnd.openmuse.capabilities+json`。合同 ID 为 `https://plugins.openmuseai.com/contracts/pdfjs/pdf-read/v1`。普通 MCP 工具 `pdf_read_snapshot` 接收 JSON Schema base64 `application/pdf` 内容；返回文件 revision、页数、逐页文字、尺寸和旋转。调用不上传文件，不访问调用者路径，不执行文档内 JavaScript。

无文字层返回 `no-text-layer`，不伪造 OCR；密码保护、损坏、超过预算（32 MiB / 500 页）的文件明确失败。OCR、页面预览与导航不在本版承诺内。

从生态仓库根目录执行：

```sh
npm ci
npm run build:pdf
npm run test:devkit
node plugins/developer-kit/scripts/pack.mjs plugins/pdf-reader/dist
python3 plugins/developer-kit/scripts/publish.py plugins/pdf-reader/dist/pdf-reader-0.1.0.mcpb
```

最后一步只创建待审核提交。市场安装后，DevKit 通过公开合同发现此 Provider，Host 仅授权资源并路由普通 MCP 工具。测试样本 `fixtures/quarterly-brief.pdf` 为本仓库生成的两页文字 PDF。
