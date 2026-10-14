# GenOffice PPTX 插件拆分与接入

状态：实施记录与待完成设计，2026-10-15。固定上游 [genspark-ai/genoffice](https://github.com/genspark-ai/genoffice) 提交 `5eab98adc8d0ebf6ecea687e42400a791ef58d64`。

## 1. 源码分析

| 层 | 上游位置 | 依赖与作用 | 迁移结论 |
| --- | --- | --- | --- |
| PPTX 核心 | `packages/pptx-engine` | OOXML 解析、元素树、修改保存；依赖 `jszip`、`fast-xml-parser`、`zip-gate` 和 `agent-core/redact-range` | 已按固定提交拆入独立插件，并用真实 PPTX 样本跑解析与保存。 |
| 编辑操作 | `packages/pptx-ops` | 受校验的事务操作；还依赖 `docx-engine/math` | 下一步按实际编辑操作裁剪，避免为一个公式功能拖入全部 DOCX。 |
| 渲染树 | `packages/pptx-render` | 文本排版与渲染树，依赖字体度量、bidi、引擎 | 可以跨端复用数据层，必须单独验证字体和 Canvas 行为。 |
| 桌面 UI | `apps/slides/src/renderer` | React、Konva、工具栏、AI 交互 | 移入隔离 WebView 或独立窗口；UI 不得直接获得 OpenMuse 主进程权限。 |
| 桌面主进程 | `apps/slides/src/main` | Electron IPC、文件、打印/PDF、字体和媒体处理，调用 Node 核心 | 需要拆成 Host Broker 能力和受限 worker；不能直接装入 Flutter AOT。 |
| GenOffice CLI | `packages/cli` | `slides read/apply/audit/render/replace` | 可供 Agent Skill 和测试复用，但其广泛的其他 Office 依赖必须裁剪。 |

核心引擎可在 Node 22+ 运行，当前拆分后的 bundle 约 808 KiB。`pptx-engine/src/zip.ts` 使用 `node:crypto`，`media-insert.ts` 使用 `node:zlib`，`sections.ts` 使用 `node:crypto`；完整保存路径还使用 `node:fs` 和 `node:stream/promises`。因此 **QuickJS 不是 Node 引擎，也不能靠换解释器直接运行原核心**。WebView 路线需要替换这些 API、完成打包和内存/字体/媒体测试；A2UI 路线应由 Host 提供限定的 PPTX 操作，而不让插件 JS 直接读取任意文件。

`savePptx`/`savePptxToFile` 会重新封装 ZIP，所用样本的无改动保存并非字节完全相同。当前测试验证可重新打开、幻灯片数和元素数一致；公开宣称“原字节保真”前需建立更严格的文件级与 Office 应用互操作测试。

## 2. 产品范围与同一插件 ID

商店展示一个 `com.openmuse.pptx` 产品身份，Desktop 与 Mobile 各有独立 release、ABI 和交付物。首个完整目标是 Desktop 打开、编辑、预览、保存 `.pptx`；Mobile 默认先做受限预览，后续引入经过 Host 授权的编辑动作。移动端只读能力目前是 Muse-Client 已有的 `openmuse-office-viewers` Rust FFI：它解析文本级 PPTX 概览，不能宣称等价于 GenOffice 高保真渲染或编辑。

Mobile 目标桥：市场安装经 Ed25519 签名的 A2UI/QuickJS 控制包；Flutter Catalog 绘制界面；`office.pptx.open` 等动作经 Host Broker 按用户选定的资源 handle、插件权限和操作预算路由到内置 Rust 引擎。资源句柄不暴露原始路径/凭据给 JS。若需要高保真画布，另设隔离 WebView profile 与静态资源包，不能借此绕过 Broker。Android 和 iOS 分开验收；未完成实机及商店规则门禁的平台不标记 supported。

## 3. Desktop 完整接入设计

1. Store API 按 `{pluginId, desktop, version, channel, target}` 解析 immutable release，返回签名目录、摘要、权限差异与兼容判断。当前 `.omplugin` 本地目录仅为开发夹具。
2. Host 安装器增加可信目录验签、staging/journal/原子版本指针、文件边界与解包预算、失败回滚。当前 `plugin_package.dart` 能校验目录摘要和 artifact 摘要，却不具备公开上传物所需的签名/事务门禁。
3. Host 从 Manifest v2 的 `execution_connector=host-process` 创建受限 worker 适配器，保留 Node 22 运行时的明确 ABI；默认独立进程只是本机代码隔离选项。已有 Dart 对象仍走可热启停 Registry。worker 只能接受 Broker 授权的资源 handle 和命令，不能收任意文件路径。
4. `apps/slides` React/Konva UI 经受控 WebView 或独立窗口交付；把 Electron IPC 替换为版本化 `pptx.bridge/v1`，由 Host 在用户操作、权限与目标资源上下文中执行。需要打开、保存、字体、图片、PDF 与网络的逐项能力表和拒绝测试。
5. 商场 UI 统一展示 OpenMuse artifact 与 DSH 映射，安装/打开/禁用/更新状态各走相应 adapter，避免当前 DSH 专用文案和直接改 profile 的路径承担通用插件安装。

## 4. 当前真实验证与缺口

- `npm test`：上游 5 页 PPTX 样本可打开、保存、重新打开，幻灯片与元素计数一致。
- `npm run pack:desktop`：生成 Manifest v2 的本地 `.omplugin` 和目录；约 808 KiB worker。
- Muse-Client `openmuse_plugin install --catalog ...`：本地安装成功；从安装后的工作区运行 worker，返回 5 页、11 个元素的结构概要。
- Desktop 插件市场增加受 `OPENMUSE_PPTX_DEV_CATALOG` 开发目录开关控制的 PPTX 卡片；UI 的计划/安装链路通过 widget 测试。安装后 Host 可热注册一个内置适配器，由已安装的 Node worker 读取 Host 授权的本地 PPTX，并在 Flutter 编辑区显示页数与元素数。该卡片只允许本地开发目录，不是线上发行，也不是 GenOffice 高保真编辑器。
- Android 真机：既有 Rust PPTX FFI 成功读取同一份 GenOffice 样本；捆绑的 A2UI/QuickJS PPTX 包经 Mobile 市场安装并启动成功。Flutter widget 测试证明安装前工作区 PPTX 入口禁用、安装后可打开既有只读 viewer。Mobile 的原生解析引擎仍随 App 构建，下载的只是受限控制包。
- **未完成**：生产商场服务、远端签名目录、Desktop 通用外部 worker 装载/强隔离与完整 GenOffice 编辑 UI、Mobile 商店 UI 到 Cloud PPTX 的单次真机用户旅程、iOS 验证。因此当前不能报告两端完整端到端通过。

## 5. 前后端交付顺序

前端：先补 Desktop 通用市场卡片和详情的安装状态/权限差异，再接受控 PPTX UI；Mobile 在已签名目录源上安装受限控制包，并通过 Host 资源选择器打开既有 PPTX viewer。后端：先实现 `contracts/store-api.openapi.yaml` 的只读目录/精确 release 与签名快照，之后接开发者上传、隔离扫描、审核、发布与撤回。PostgreSQL 保存产品及分平台 release，S3 存按摘要不可变产物；当前本地 fixture 不能作为生产服务替代品。
