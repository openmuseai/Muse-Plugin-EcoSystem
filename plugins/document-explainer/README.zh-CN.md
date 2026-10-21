# Document Explainer

独立的 Desktop PPTX/PDF 讲解插件。浮层、提示词和顺序控制均在本目录；Host、GenOffice 不包含讲解代码。

- [产品和交互](docs/01-PRODUCT-AND-UI.zh-CN.md)
- [开发方案](docs/02-IMPLEMENTATION.zh-CN.md)
- [公开资源扩展协议](../../contracts/resource-extensions-v1/README.zh-CN.md)

## 用户使用

安装 GenOffice PPTX 0.7.0+、PDF Reader 0.2.0+ 和已启用的 DSH Agent。打开文件，右下角选择「从第一页」或「从当前页」，点「开始讲解」。DSH 显示逐页输入和模型输出；「暂停」取消当前页，继续时重试未完成页。内容由 DSH 中配置的模型生成；本插件不保存模型密钥。当前是文字讲解，不宣称语音播放或 Mobile 验收。

## 无源码依赖的开发

在 OpenMuse 选择/新建 Workspace，打开该目录终端，使用已安装 DevKit 0.3.1：

```sh
muse search pptx
muse search pdf
muse install io.openmuse/genoffice-pptx
muse install io.openmuse/pdf-reader
muse init --name my-document-explainer --capability pptx --capability pdf --template document-explainer
muse check
muse dev
```

保留这个终端，在 Workspace 编辑 main.js，再次 muse dev。打开 PPTX/PDF 后候选浮层出现；完成两种资料各一页真实模型讲解后，muse report 收集报告，muse pack 生成 MCPB，muse submit 提交待审。提交不会自动批准。关闭终端会撤销候选；不要把开发预览当正式安装。正式安装由市场审核通过后进行。

模板将标准 MCP Apps SDK、公开资源路由客户端和本插件参考适配器打入发行包。main.js 的 `run(api)` 可通过 `api.mountNarration()` 启动默认讲解 UI；高级开发可直接基于 MCP Apps App 实现自己的界面。脚手架没有要求读取 Host、GenOffice 或 PDF 源码，也不在运行时依赖 DevKit。它只固定开发/测试的 Provider 发行版本，其他运行环境仍须提供兼容实时接口。

## 从本仓库构建参考插件

```sh
npm ci
node plugins/document-explainer/build.mjs
node --import tsx --test plugins/document-explainer/test/narrator.test.ts
node plugins/document-explainer/test/pdf-view.mjs
node plugins/developer-kit/scripts/pack.mjs plugins/document-explainer/dist
python3 plugins/developer-kit/scripts/publish.py plugins/document-explainer/dist/document-explainer-0.1.0.mcpb
```

打包目录只放运行文件；测试证据放仓库 dist 或 docs/evidence，不要把 token、报告、截图和临时工程混进 MCPB。构建依赖许可证见对应发行包 notices。
