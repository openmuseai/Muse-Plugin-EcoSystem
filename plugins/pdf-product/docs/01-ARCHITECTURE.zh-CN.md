# PDF 产品架构与边界

## 依据和结论

GenOffice PDF 是 Electron/React 产品。其 [`App.tsx`](../../genoffice-pptx/vendor/genoffice/apps/pdf/src/renderer/App.tsx) 同时持有 PDF.js 文档、页面列表、缩略图、编辑草稿、Ribbon 和保存状态；通过 `window.pdfApi` 调用主进程保存、OCR、签名、打印等服务。[`package.json`](../../genoffice-pptx/vendor/genoffice/apps/pdf/package.json) 依赖 `pdfjs-dist`、`pdf-lib`、React 和 Electron。它是交互/视觉参考，不是可以直接接入 Flutter 的独立壳组件。复刻产品信息架构、行为与视觉；不复制其文档状态或渲染路径。

当前 [`pdf-rebuild` 产品 ABI](../../../../ioffice/koffice/pdf/rebuild/pdf-rebuild/src/ksp/product/ProductEditBridge.h) 提供打开字节、页数/页尺寸、整页与区域渲染、文字/链接读取、文字修改、撤销/重做和导出；[`ProductBridge.h`](../../../../ioffice/koffice/pdf/rebuild/pdf-rebuild/src/ksp/product/ProductBridge.h) 有页面组合。Flutter [`PdfProductBackend`](../../../../ioffice/koffice/pdf/rebuild/pdf-flutter-app/lib/pdf_product_backend.dart) 维护会话与快照，[`ProductPdfDocument`](../../../../ioffice/koffice/pdf/rebuild/pdf-flutter-app/lib/product_pdf_document.dart) 将产品会话适配给 `pdfrx` 阅读视图。**目前生产 Flutter 直接调用 C ABI**；[`product-rust`](../../../../ioffice/koffice/pdf/rebuild/pdf-rebuild/product-rust/src/lib.rs) 是 Rust 所有权封装试点，尚非发布路径。Web 产品内核是 **PDFium/C++ 经 Emscripten 生成的 WASM**，不应误称 Rust WASM。macOS arm64、Android arm64 与 Web 的已有工程验证、限制见 [`pdf-flutter-app/README.md`](../../../../ioffice/koffice/pdf/rebuild/pdf-flutter-app/README.md)。

## Everything is plugin 的实际边界

| 责任 | 所属 | 原则 |
| --- | --- | --- |
| PDF 文档字节、对象/页面、编辑事务、撤销、导出 | `ioffice/pdf-rebuild` 的产品会话与 PDFium | 唯一权威；所有改变 PDF 的操作须由版本化产品 ABI 执行 |
| 页面绘制、选择、IME、触控、滚动、缩略图、注释/表单交互表面 | `ioffice/pdf-flutter-app` 中抽出的共用 Flutter 包 | 编译进各端 Host；状态仅是内核快照的视图，不形成第二文档模型 |
| 文件授权、单写者租约、窗口/标签页、保存原子提交、插件验签与离线缓存 | `Muse-Client` Host | 桌面可内嵌或独立原生窗口，皆复用同一 Flutter 表面与会话权限 |
| Ribbon 顺序与分组、多级菜单、快捷键、主题/图标、预设、开关和低频命令扩展 | 本 `pdf-product` 签名资源包 | 可从市场或离线安装；扩展不得进入滚动、逐字输入、命中测试、逐帧渲染路径 |

用户所见的 PDF 产品是一个可安装插件身份；可执行内核和 Flutter 表面是 Host 的版本化能力槽位。Desktop Flutter AOT 不能把下载的 Dart Widget 直接注入现有进程，所以“插件化安装 UI”指**已编译的表面组件消费可更新的签名产品描述**。新增原生组件或破坏性表面 API 时发布 Host 更新。Mobile 采用同一源码，内核随 Host 安装，离线签名资源在应用私有目录启用；Web 加载同一产品 WASM 并缓存核心资源，断网可打开本地授权文档。iOS 下载可执行代码须遵守平台分发约束，首版只安装声明与内容资源。

`0.1.18` 的生成文件导航遵守这条边界：签名 `chrome.json.dialogs.extractRange.desktopOpenResult` 选择新文档标签策略；产品会话完成抽页并取得实际落盘路径后，通过 `openGeneratedDocument(path)` 端口请求 Host 导航。Host 检查绝对 PDF 路径和文件存在性，再交给工作区标签控制器。原文档会话保留；端口缺失时独立表面仍可在自身视图打开结果。该端口不传 PDF 明文字节，页面内容和导出仍由唯一产品会话负责。

## 领域模型和命令

```text
Host ResourceRef / WriteLease
  └─ PdfSession(id, abiVersion, revision, permissions, dirty)
       ├─ PageRef(index, rotation, cropBox) → RenderTile / TextRun / Link
       ├─ Selection(文字范围与页面坐标)
       ├─ EditTransaction → Undo/Redo → Snapshot(bytes)
       └─ Annotation / Form / Signature / Redaction（能力成熟后开放）

ProductPackage(id, version, profile, minHost, minAbi, capabilities)
  └─ Tab → Group → Control → MenuNode → CommandId
```

Flutter 的 `ViewportState`（页码、缩放、布局模式、侧栏、选中工具）与 `PdfSession` 分离。页面坐标统一按内核 PDF 点与旋转/crop 变换；命中测试、文本四边形、批注位置和导出使用同一变换合同。所有修改命令携带 `sessionRef`、`baseRevision`、`requestId`，返回新修订、dirty、可撤销状态与受影响页；陈旧修订、只读、无权限、不可保真页面组合均须明确拒绝。保存由内核导出字节，Host 用授权目标、临时文件、fsync/原子替换（平台支持时）完成提交；插件不持有路径或 PDF 明文副本。

命令路由：`host`（打开/另存/打印/权限）、`view`（缩放/侧栏/导航）、`core`（编辑/批注/页面/表单）、`extension`（显式 AI/OCR/转换等）。产品包声明命令 ID、参数模式、必需能力、禁用原因、图标与菜单层级；Host 在安装时验证 ID/快捷键冲突，运行时以 **实际 ABI 能力 ∩ Host 能力 ∩ 已签名功能开关 ∩ 文档权限** 决定可用性。灰化命令要有原因；不能因按钮存在宣称功能已完成。扩展以授权快照调用，有版本、预算、可取消和离线策略，永远不接管内核编辑事务。

## 版本与安装合同（拟定）

拟定 `pdf.product/1`（签名资源）和 `pdf.command/1`（命令）合同；公开前必须由三仓共同冻结 JSON Schema 与兼容样本。产品包建议包含 `manifest.json`、`catalog.json`、`catalog.signature.json`、`product/chrome.json`、`product/ribbon.json`、`product/menus.json`、`product/shortcuts.json`、`product/features.json`、`product/assets/*`。使用与 Word 产品一致的逐文件摘要和 Ed25519 发布者验签、离线导入、原子安装/回滚。禁止包内可执行渲染内核或动态 Dart 代码。

版本分别记录 `pdfAbiMajor`、`pdfSurfaceMajor`、`pdfProductProfileMajor`、插件 SemVer、Host 最低版本和能力集合。一次文档会话锁定插件资源版本，升级在新会话生效；旧版本资源保留到正在使用的会话关闭。内核 ABI 破坏性变更提升 major；新增命令/能力提升 minor；仅 Ribbon 布局/文案/图标更改提升插件 patch 或 minor 并重签。对每次联合构建记录三仓 commit、源码脏状态、内核/Flutter/插件包 SHA-256 与 E2E 证据。

## 当前技术债与安全门禁

- 原生包仍留有调试回退用的独立 PDFium 阅读实例；Web 已移除第二份阅读器 WASM。收敛前应以产品会话为默认真相，逐步覆盖书签、旋转、字体回调和复杂文件后再删回退库。
- 页面组合会拒绝已知无法保留签名、表单、书签、标签、附件或所选页批注的文件。插件命令必须透出该能力限制，不允许静默丢失结构。
- 文字重排保真、加密 PDF、签名、复杂表单及撤销语义仍需语料门禁。涂黑必须证明底层内容不可提取，不能只画黑色矩形；证书签名必须独立校验证书与修改后有效性。相关菜单先保留设计位，未通过验证时禁用。
- [`pdf-reader`](../../pdf-reader/README.zh-CN.md) 保持独立只读 MCP Provider；它可服务其他显式任务，但不能成为 PDF 产品编辑画面的第二渲染内核。
