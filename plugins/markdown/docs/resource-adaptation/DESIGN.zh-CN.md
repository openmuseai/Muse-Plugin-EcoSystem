# SiYuan 资源插件适配方案

> 编辑器交互已按后续反馈修正；当前实现与人工流程见 [原生编辑器适配](EDITOR-PARITY.zh-CN.md) 和 [最新验收](EDITOR-PARITY-ACCEPTANCE.zh-CN.md)。本文件保留原资源化阶段记录。

2026-11-02。目标：插件提供资源格式及其能力，OpenMuse 组合工作区与导航。适用 Desktop、Android、iOS；本地内核保持在插件内，无远端服务依赖。

## 现状与参考

改造前，适配器只贡献 `siyuan.workspace` 面板及 Mobile Workbench 详情。它没有 editor、resource handler、creator 或 context 贡献；`buildEditor` 直接拒绝资源。Flutter WebView 加载原版 Desktop/Mobile 应用，因此第二套工作区、文件树、标签、工具栏、账户品牌、加载动画一起进入 Host。此前验收证明了独立应用可运行，不能证明它融入资源框架。

GenOffice PPTX 当前以 `.pptx` 的标准 MIME/扩展名参与 editor 路由：Desktop 测试验证 `inspect_pptx` 对应的 `io.openmuse/genoffice-pptx.file`，服务端工厂返回 MCP App 的 UI resource，移动端另有原生 Flutter 预览 renderer。可复用的边界是「资源与能力归插件，文件入口/标签/位置归 Host」，不能据此宣称现有 PPTX 已有全部新建或写回能力。SiYuan 使用新资源中心已提供的可选 handler/creator/session 接口实现创建和版本化保存；`.sy` 依赖块 ID、附件和属性视图，不能套用单文件文本保存。

Mobile 依据 `Muse-Client/docs/design/mobile-resource-center/IMPLEMENTED-CONTRACT.zh-CN.md`：Home 的最近/本机/PC、动态 `+`、打开方式、引用、版本和受限编辑会话沿用共享实现；Workbench 不再承载第二套笔记应用。后续 Word/Excel 使用相同 handler/creator/session，不在 Host 加格式分支。

## 功能与逻辑分区

| 分区 | 原实现 | 适配归属 |
| --- | --- | --- |
| 资源与持久化 | notebook、`.sy` AST、块 ID、assets、storage/av、历史、索引 | 插件；资源中心持有不透明资源身份和精确版本字节 |
| 编辑 | Protyle、Lute、事务、撤销、输入法、代码/数学/图表、附件上传 | 插件编辑 surface，直接使用原组件 |
| 数据库 | 属性、关系、表/看板/日历/画廊、过滤排序 | 插件内部领域；数据库视图 tab 是内容视图，保留，不作为应用文档 tab |
| 知识关联 | 块引用、嵌入、反链、搜索、标签、大纲 | 插件文档/集合上下文；跨资源跳转经公开路由，不能私建 Host 工作区 |
| 文档生命周期 | 新建、打开、编辑、保存、重命名、最近 | SDK creator/handler/session 与资源 Provider；插件不直接写 Host 文件或最近表 |
| 工作区外壳 | Workspace 菜单、文档 tab、左右 Dock、状态栏 | OpenMuse；资源编辑入口不启动该外壳 |
| 应用服务 | SiYuan 账户、VIP、集市、更新、同步/远端服务 | 不进入客户端资源编辑流程；原有数据保留，署名/许可证保留于插件信息及打包文件 |

## 模块清单与承载方式

| 原模块/目录 | 逻辑边界 | UI/能力承载 |
| --- | --- | --- |
| `kernel/filesys`、`model`、`treenode`、`sql` | 原生 AST、块身份、事务、索引 | 仅插件内核；Host 不直接读写 AST/SQLite |
| `app/src/protyle`、Lute | 编辑、撤销、Markdown 输入、代码、数学、图表、媒体 | 独立编辑 surface；原生上下文菜单/格式工具属于内容操作 |
| `kernel/av`、`protyle/render/av` | 数据库行列、关系、布局、视图、过滤排序 | 内容中的数据库视图；不删数据库自身的视图切换 |
| notebook、`fileTree`、`layout`、`mobile/tabs` | 应用笔记目录和窗口导航 | OpenMuse 资源目录与标签；包内关联文档用内容菜单定位 |
| `search`、`outline`、`graph`、`backlink`、tag/bookmark | 知识检索与关联 | 插件资源上下文能力；同包块跳转在当前 surface；包外引用明确要求打开来源，不能误跳另一编辑会话 |
| `asset`、upload、OCR、PDF annotation、live photo | 附件领域 | 插件上传/引用/打包，平台文件选择适配；OCR 引擎继续独立打包 |
| `history`、`sync`、`riff/card`、templates | 内容历史、同步协议、闪卡与模板领域 | 内核保持插件所有；Host 资源版本与 SiYuan 工作副本历史区分，不把云同步接成 Host 服务 |
| `config`、appearance、hotkeys、menus | 编辑偏好与应用偏好 | surface 跟随 Host 语言与浅深色；仅编辑偏好进入资源操作，Host 负责全局设置与导航快捷键 |
| `ai`、agent、plugin/bazaar | 原应用的 AI/扩展体系 | 由公开工具/上下文能力逐项适配；当前资源编辑入口禁用原应用前端插件装载，避免第三方扩展重新创建工作台外壳 |
| account/VIP、update、workspace chooser、boot loading | 原应用发行壳 | 不挂载；版权及许可在插件信息保留，普通加载/错误使用 Flutter 控件 |

本轮不宣称全套原应用侧栏工具已经逐个完成 UI 贡献化。正式验收范围是资源生命周期、独立块编辑、包内跳转、原生包中数据库/附件/引用保存；全局图谱、闪卡管理、历史面板、模板管理、AI 工具面板须按上表作为资源上下文能力继续交付，不以隐藏原应用按钮充当已适配。

## UI 分区

Desktop：OpenMuse 文件/资源树及文档标签 - 资源 surface - Protyle 内容。插件可提供内容相关的格式、插入、数据库、查找操作；不渲染应用 Workspace、第二套文件 tab、品牌头、全局 Dock。Mobile：Home - 新建/打开 - Host 资源页标题与返回 - 响应式编辑内容；键盘编辑工具属于内容操作。加载由普通 Flutter 进度状态表达，无原应用品牌启动页。错误可重试，退出脏文档沿用资源页确认。

## 资源格式与能力

- `.sydoc`，`application/vnd.openmuse.siyuan.document+zip`：使用 SiYuan 原生 `.sy.zip` 归档内容，不转成 Markdown。包含 `.sy`、附件、属性视图及同包关联文档；插件验证归档预算、路径、文档结构后调用原生导入。主文档由插件持久属性标记识别。可新建、打开、编辑、保存、重命名和复制引用。
- `.sy.zip`：原生文档集合导入/打开；多文档保持同包关系，资源身份属于集合而非其中临时内核 ID。`.sy`：可打开独立 AST；没有随附文件的附件/外部关联不能凭空恢复。
- `.md`：继续由既有 Markdown/Notes handler 处理；导入/导出是显式转换，不把所有 Markdown 默认抢占为 SiYuan。
- 包内主文档与关联文档 ID 由原导入器一起重映射，避免多个资源或固定历史版本相互覆盖。外部块引用保持外部引用，不宣称资源包自动携带整个用户知识库。

## 保存、版本和隔离

每个资源编辑会话使用插件私有工作笔记本。内核事务只修改工作副本；保存先等待编辑器事务确认、flush，再导出该会话所有文档/附件/AV，交给 `ResourceEditorSession.commit` 做 CAS。保存失败/冲突保留工作副本及脏状态，不改原资源，不回退版本。只读/对话快照禁止编辑。资源身份稳定，临时内核 ID 和物理路径不进入引用；Host 不解析 SiYuan JSON/API。

现有 userdata 不移动、不覆盖、不自动转换。整本迁移以显式原生集合归档为边界；把有跨文档引用的已有知识库逐篇无提示拆开会改变语义，禁止这样迁移。完整旧应用代码仍在 vendor，正式资源入口使用独立构建的 Protyle bootstrap。

## 开发计划与验收

1. D1：记录模块、资源格式、UI 归属和边界；实现独立编辑入口，构建不启动原应用 App 类。
2. D2：插件原生归档 API/校验、隔离会话、creator/handler/context；新建与重开使用真实 Go 内核。
3. D3：Desktop 资源路由接入工作区标签，Mobile 直接复用 Home/资源页；插件详情只说明能力，不启动第二套应用。
4. D4：归档安全、资源类型/能力、保存/冲突/只读、两个资源隔离测试；回归资源中心和 PPTX 路由。
5. D5：真实 Desktop/Android/iOS UI：Home/资源入口 - 插件新建 - 编辑 - 保存 - 关闭 - 最近重开；检查无第二套应用外壳/品牌加载；数据库/附件原生包另做 roundtrip；构建人工审核客户端。

实际执行结果和未覆盖项写入本目录 ACCEPTANCE，不将设计能力或组件测试冒充设备 UI 验收。
