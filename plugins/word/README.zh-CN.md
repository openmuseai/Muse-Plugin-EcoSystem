# OpenMuse Word 产品插件

**状态：macOS 与 Android 原生只读预览已在 OpenMuse 端到端通过；编辑保存、iOS/Web、自动化 Android 联合钩子和市场正式上架尚未完成。** 插件 ID 为 `io.openmuse/word`。本目录只包含 Word 产品配置、资源、离线打包工具和显式调用的扩展服务；文档模型、排版、DOCX 导出、画布、光标、选区和输入法保留在 `ioffice`。

| 所属仓库 | 负责内容 |
| --- | --- |
| 本工程 | 功能区、命令布局、快捷键、功能门禁、模板、字体资源目录、低频扩展与签名包 |
| `ioffice/libs/word-core` | 唯一文档模型、编辑、排版、导出；Desktop/Mobile 原生构建与 Web WASM 构建 |
| `ioffice/samples/libs/word` | 共用 Flutter `word_editor` / `word_render` 编辑表面 |
| `Muse-Client` | 安装校验、受信任密钥、能力协商、资源授权、窗口与离线存储 |

## 文档

- [产品范围与体验](docs/01-PRODUCT.zh-CN.md)
- [技术架构与多端交付](docs/02-ARCHITECTURE.zh-CN.md)
- [公开合同与资源格式](docs/03-CONTRACT.zh-CN.md)
- [详细开发计划](docs/04-DEVELOPMENT-PLAN.zh-CN.md)
- [验收矩阵](docs/05-ACCEPTANCE.zh-CN.md)
- [持续迭代、版本与联合构建发布工作流](docs/06-CONTINUOUS-DELIVERY.zh-CN.md)
- [GenOffice Docs 壳层复刻计划与阶段验收](docs/07-GENOFFICE-CHROME-PLAN.zh-CN.md)
- [Ribbon 全部下拉菜单与响应式台账](docs/08-RIBBON-MENU-INVENTORY.zh-CN.md)
- [首版双端渲染验证记录](docs/09-FIRST-RENDER-VALIDATION.zh-CN.md)
- [0.1.8 GenOffice 壳层视觉对比与双端截图](docs/10-VISUAL-COMPARISON-0.1.8.zh-CN.md)
- [0.1.9 GenOffice 源图标与壳层视觉对比](docs/11-VISUAL-COMPARISON-0.1.9.zh-CN.md)
- [0.1.10 GenOffice 封面图库视觉对比](docs/12-VISUAL-COMPARISON-0.1.10.zh-CN.md)
- [0.1.11 GenOffice 艺术字图库视觉对比](docs/13-VISUAL-COMPARISON-0.1.11.zh-CN.md)
- [0.1.12 GenOffice 快速样式图库视觉对比](docs/14-VISUAL-COMPARISON-0.1.12.zh-CN.md)
- [0.1.13 真实 DOCX 样式与双端视觉对比](docs/15-VISUAL-COMPARISON-0.1.13.zh-CN.md)
- [0.1.14 真实文档字数与双端视觉对比](docs/16-VISUAL-COMPARISON-0.1.14.zh-CN.md)
- [0.1.15 字数统计弹窗与双端视觉对比](docs/17-VISUAL-COMPARISON-0.1.15.zh-CN.md)
- [0.1.16 页码定位面板与双端视觉对比](docs/18-VISUAL-COMPARISON-0.1.16.zh-CN.md)
- [0.1.17 阅读视图与双端视觉对比](docs/19-VISUAL-COMPARISON-0.1.17.zh-CN.md)
- [0.1.18 视图缩放组与双端视觉对比](docs/20-VISUAL-COMPARISON-0.1.18.zh-CN.md)
- [0.1.19 视图页签后半段、网格线与双端视觉对比](docs/21-VISUAL-COMPARISON-0.1.19.zh-CN.md)
- [0.1.20 多页视图与 macOS 视觉对比](docs/22-VISUAL-COMPARISON-0.1.20.zh-CN.md)
- [0.1.21 深色页面与 macOS 视觉对比](docs/23-VISUAL-COMPARISON-0.1.21.zh-CN.md)
- [0.1.22 水平标尺与响应式视觉对比](docs/24-VISUAL-COMPARISON-0.1.22.zh-CN.md)

## 工程结构

```text
product/                可安装的 Word 产品配置、模板与字体目录
src/server.ts           Desktop MCP 资源发现与低频扩展工具
src/word_count.mjs      可移植的显式字数统计逻辑
scripts/               验证、构建、Ed25519 签名打包与验签
test/                  合同与签名完整性测试
stack/                 跨仓库版本和端到端用例政策
docs/                  产品、架构、合同、计划、验收
```

## 本地开发

在仓库根目录先安装既有 Node 依赖，然后：

```sh
cd plugins/word
npm run validate
npm test
npm run build
```

三仓并列检出后，在本仓根目录一键规划、构建或执行严格联合验收：

```sh
npm run word:plan -- --platform desktop
npm run word:build -- --platform desktop --scope render
npm run word:e2e -- --platform desktop --scope render
```

构建/验收报告写入 `.word-stack-runs/`。`--scope render` 是首版 Desktop 打开与渲染门禁，实际启动 OpenMuse 原生窗口；默认的完整编辑门禁仍会在当前金文件及保存能力处失败。[工作流文档](docs/06-CONTINUOUS-DELIVERY.zh-CN.md)定义了两级门禁。

macOS 人工预览：完成上述 `word:e2e` 后，在并列的 `Muse-Client` 仓库运行 `./scripts/launch_word_preview_macos.sh`。脚本从最近一次通过的报告读取隔离安装、公钥和样本文档，启动 Debug OpenMuse，自动打开 Word 页面；右侧 DSH 面板也应加载。E2E 同时检查 DSH 服务启动、WebView HTTP 200 和页面加载。完整 Release 应用由 `Muse-Client/scripts/package_macos.sh` 生成，Word 原生库需提供 arm64 与 x86_64 两个切片。

Android 首版由 Host 随包提供 `word-core` 的 arm64 原生库和共用 Flutter 编辑表面；已签名产品包、身份和公钥作为离线启动资源随包放入 Host。手机的文件夹按钮打开 DOCX，拼图按钮只安装 `.mcpb` 产品资源。2026-10-22 在 Android 16 真机用 Release QA 包打开 `sample3.docx`，页面和状态栏均显示 1 页。标准包名 APK 与 macOS 通用包位于 `Muse-Client/dist/`；当前 Android APK 使用本地 QA 签名，正式分发需要生产签名。具体证据与未完成项见[首版双端验证记录](docs/09-FIRST-RENDER-VALIDATION.zh-CN.md)。

`build` 只在忽略的 `dist/` 生成开发产物。发行包要求由发布环境提供 Ed25519 私钥；仓库不包含生产私钥：

```sh
npm run pack -- --private-key /secure/word-product-ed25519.pem --key-id word-publisher-2026
npm run verify -- dist/word-0.1.2.mcpb /secure/word-product-ed25519.pub.pem word-publisher-2026
```

`pack` 生成标准 MCPB 的 `manifest.json` 和签名资源目录。包摘要供 Registry 下载完整性校验；`catalog.signature.json` 对资源目录及其每个文件摘要签名。首版 Host 使用显式配置的可信公钥校验 Word 产品资源，在安装后注册 `.docx` 原生预览编辑器。正式发行仍需可信公钥配置和密钥轮换机制；当前只读预览**不等于**已支持 DOCX 保存。无私钥时只做开发构建和测试，不生成可发布包。

当前字体目录没有字体二进制；系统回退名称不是离线字体保证。加入字体时必须带可再分发许可、文件摘要并通过同一签名目录。两个 JSON 模板是内容资源，实例化由 `word-core` 接口完成；插件不直接修改 DOCX。
