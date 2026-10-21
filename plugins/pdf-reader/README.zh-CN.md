# PDF Capability Provider 0.1.1

独立标准 MCPB 插件，使用 Mozilla PDF.js 6.4.299（Apache-2.0）读取已授权 PDF 的文字层。首版仅验证 macOS Apple Silicon / Node ≥22.13；内置对应平台的 `@napi-rs/canvas` 原生依赖。它是供其他插件组合使用的能力 Provider，首版没有独立可视化阅读器。

公开合同资源：`capability://pdf-reader/contracts`，MIME `application/vnd.openmuse.capabilities+json`。合同 ID 为 `https://plugins.openmuseai.com/contracts/pdfjs/pdf-read/v1`。普通 MCP 工具 `pdf_read_snapshot` 接收 JSON Schema base64 `application/pdf` 内容；返回文件 revision、页数、逐页文字、尺寸和旋转。调用不上传文件，不访问调用者路径，不执行文档内 JavaScript。

无文字层返回 `no-text-layer`，不伪造 OCR；密码保护、损坏、超过预算（32 MiB / 500 页）的文件明确失败。OCR、页面预览与导航不在本版承诺内。

从生态仓库根目录执行：

```sh
npm ci
npm run build:pdf
npm run test:devkit
node plugins/developer-kit/scripts/pack.mjs plugins/pdf-reader/dist
python3 plugins/developer-kit/scripts/publish.py plugins/pdf-reader/dist/pdf-reader-0.1.1.mcpb
```

最后一步只创建待审核提交。市场安装后，DevKit 通过公开合同发现此 Provider，Host 仅授权资源并路由普通 MCP 工具。测试样本 `fixtures/quarterly-brief.pdf` 为本仓库生成的两页文字 PDF。

0.1.1 将合同版本更新为 1.0.1：公开二进制 Schema 使用长度上限和标准编码/MIME 注解，避免重复分组正则在大文件上耗尽客户端栈；Provider 通过 canonical base64 回编码比较拒绝非法输入，文件/页数/输出预算仍然生效。Host 无 PDF 特判。

## 0.2.0 Desktop 实时视图

新增 pdf_open MCP Apps UI 入口，离线捆绑官方 PDF.js 画布和 worker（以官方 fake worker 方式在同一隔离 View 中运行，不需要 Node/localhost 服务渲染）。原先 pdf_read_snapshot 的语义和合同保持不变。

View 通过普通 MCP Apps tools/list/tools/call 贡献：

- pdf_get_state({}) → name, revision, pageCount, pageIndex。
- pdf_read_page({pageIndex}) → name, revision, index, text, status。
- pdf_go_to_page({pageIndex}) → pageIndex, revision；重绘完成后返回。

页码从 0 开始。没有文字层返回 no-text-layer；不自动 OCR，不虚构讲解文字。Host 不包含 PDF 页码或渲染业务逻辑。测试脚本在 plugins/document-explainer/test/pdf-view.mjs，包含两页实际 PDF 渲染、文字读取和导航；这不等于 Android 或所有 PDF 字体/图形特性均验收。
