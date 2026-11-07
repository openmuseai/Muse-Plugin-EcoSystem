# 统一内容模型、对象协作与 Agent 命令

2026-11-04，拟议合同。下文类型/JSON 为设计示例，尚非现有 SDK 或 Cloud API。参见[总决议](README.zh-CN.md)及[对象平台与协作底座](OBJECTS-AND-COLLABORATION.zh-CN.md)。

## 1. 四种模型各司其职

| 模型 | 解决的问题 | 不能承担的责任 |
| --- | --- | --- |
| 公共语义模型 | 块/inline/对象、引用、属性、schema、可调用命令 | 不规定必须用 `.sy`、Y.Map 或某个 SQLite 表持久化 |
| 协作与持久模型 | 文本序列、结构变更、日志、版本、快照 | CRDT 收敛不自动解决领域不变量、权限和跨对象原子性 |
| 编辑投影 | Flutter node、Markdown 草稿、选区、输入法、视口 | 不作为第二个长期可写文档真源 |
| 渲染投影 | Office 页/网格图元、布局盒、文本语义层、预览图 | 不通过改绘制指令来修改文档内容 |

公共模型不是在 AppFlowy 与思源之间增加一个独立同步副本。它是唯一对外语义；首期可由 AppFlowy Document 的存储适配器实现。正文命令只经一个事务层写入对应 CRDT，UI/IR/索引都由该状态派生。不同领域对象各自也只有一个权威状态。

## 2. 平台对象图与智能文档块树

```text
ContentObjectGraph（平台级，非某篇文档的私有对象树）
  SmartDocument
    identity / schemaVersion / capabilityRequirements
    root BlockTree
      paragraph -> InlineSequence
      heading -> InlineSequence + level
      code -> source + language
      math -> latex/source + displayMode
      table -> rows/cells（每格可为受约束的块/inline）
      databaseView -> CollectionRef + Query/ViewConfig
      resourceEmbed -> ObjectRef + Selector + Binding + Presentation
      app -> AppDefinitionRef + StateRef + Bindings
  WordObject / WorkbookObject / Collection / PresentationObject
  PdfObject / ImageObject / VideoProject / MediaAsset
  AppDefinition / AppState
  relations / object directory / checkpoint manifests
```

树定义父文档的顺序、层级和阅读结构；平台图定义独立对象及其引用、关系和依赖。不把同一个被引用对象复制成多份权威数据。父文档结构 CRDT 和被引用对象独立加载、授权、同步和回收，避免打开一篇笔记就下载整本工作簿。这里的“子对象”只指嵌入关系，不代表所有权从属；工作簿、数据集或视频项目可以没有父文档，也可被多个文档/应用/Agent 同时使用。

建议公共寻址区分 resourceId（业务资源入口）、objectId（领域对象）、entityId/nodeId（块/行/记录/形状等实体）、anchor（文本相对位置、范围或页面坐标）。它们不是固定一对一层级；实体身份也不等于同步分片。另行定义事务单元、同步/存储分片、订阅范围与权限边界。本地内存指针、DOM path、数组下标、临时内核 ID 均不是永久身份。

可公开的 `ObjectRef` 用不透明 resource/object 标识；Cloud workspace、collabId 的实际映射由受权 provider 解析。第三方拿到引用不等于拿到读取权，也不需要知道服务器存储路径。

## 3. 元素类型与 schema 注册

每类元素须注册下列语义（平台合同设计，具体 API 名待冻结）：

```text
ElementDefinition
  type: namespacedId                # 如 muse/paragraph、vendor/chart
  payloadVersion / compatibilityRange
  payloadSchema / childConstraints / inlineConstraints
  supportedOperations / mergePolicy / invariants
  enumerateReferences / extractAccessibleText
  migration / importExport / fallbackRepresentation
  rendererCapabilities / editorCapabilities
  requiredPermissions / costLimits
```

节点公共信封包含 `id/type/payloadVersion`、结构关系和有类型 payload。核心结构字段由内核维护，插件不能用 `props` 私自定义第二套 parent。自定义属性按命名空间管理，并为可协作字段定义粒度、验证和操作；不能默认所有属性都用任意 JSON 全量替换。

兼容策略：识别 type 且支持版本时编辑；识别较新版本但存在安全降级投影时只读展示；完全未知时显示占位、保留原载荷/引用并允许显式导出。旧客户端不能“规范化”删除未知字段。迁移在检查点上执行、记录迁移版本，并防止旧客户端继续以旧 schema 写入。

元素扩展不能只提供 renderer。没有服务端可验证的操作合同和存储处理方式，最多作为只读或整体 CAS 更新对象；不能直接获得任意细粒度协作。

## 4. inline、代码、公式及三种“表格”

InlineSequence 用字符序列与有类型 marks/atoms 表达文字、强调、链接、提及、块引用、行内公式等。文字与可编辑公式源同步，渲染 HTML/TeX 结果是缓存；跨端 offset 编码需固定，Office CP、Dart UTF-16、Unicode scalar 不能直接混用。

代码块可保存 source/language、可选运行配置，运行输出独立为带来源与版本的结果。执行是受权任务，不是打开/渲染代码块就自动启动。公式以来源文本和语义为准，排版差异由 renderer 兼容测试约束。

| 类型 | 权威内容 | 编辑/协作特点 |
| --- | --- | --- |
| 文档普通表格 | 文档模型的 row/cell ID、受约束内容 | 富文本、合并/拆分、行列结构；与正文同对象事务可实现原子操作 |
| 数据库视图 | 独立 collection 的字段、记录及关系；视图引用它 | 筛选/分组/排序属于视图；行是稳定实体，不以屏幕位置定位；计算字段派生 |
| 电子表格区域 | Office Workbook 内的 sheet、cell/range、公式、样式 | 由 spreadsheet 内核计算；结构操作与地址变化需领域协作设计 |

数据库同一数据可同时以表、看板、日历展示；个人排序/筛选和共享视图配置应分开保存，避免 A 切筛选影响 B 正在编辑的界面。新建数据库可先复用 AppFlowy database 适配，但不可将其等同于思源 AV，后续绑定块/公式/关系需专项映射。

## 5. Office 嵌入合同

```json
{
  "id": "embed-01",
  "type": "muse/resource-embed",
  "payloadVersion": 1,
  "payload": {
    "target": {"resourceId": "resource-word-01"},
    "selector": {"kind": "word.semantic-range", "rangeId": "range-42"},
    "binding": {"mode": "live"},
    "presentation": {"mode": "page-fragment", "maxHeight": 640},
    "requestedInteraction": "read-only"
  }
}
```

这只是目标选择器的示例，不声称 `word-core` 已提供稳定 rangeId。实现需增加并持久化语义锚点；若当前只能定位页序，就只开放固定版本页面能力。`requestedInteraction` 不是权限来源，最终由 provider 与会话 ACL 裁决。

### 5.1 三种绑定

* **固定快照**：绑定具体内容版本/哈希与 selector；适合引用、归档、报告、可重现历史。
* **实时引用**：绑定对象与语义 selector；展示最新受权版本，可显示源版本和刷新状态。
* **独立副本**：显式创建新领域对象并重写引用；不是把目标 ID 更名，来源关系与权限重新确定。

`live` 视图允许更新内容但不意味着离线一定拥有目标；无权限显示受限占位，无缓存显示未下载。历史检查点必须将 live 引用解析为具体版本向量或记录未解析状态。

### 5.2 “插入一页”的三种语义

| 领域 | 合理 selector | 变化时处理 |
| --- | --- | --- |
| Word | pinned version + pageIndex + layoutFingerprint，或 live 语义范围 | 分页依赖字体、纸张和内核版本；同一页序在新版可变；失效不能悄悄指向别的内容 |
| PDF | pinned version + page identity/index + crop/rotation | PDF 增删页后做显式锚点重定位；注释坐标从 page space 转 view space |
| Excel | sheet stable ID + named range/稳定区域身份；或 pinned print-page | 行列插入后用领域规则跟随区域；A1 字符串或屏幕行号不是完整永久锚点 |
| PPT（未来） | slide stable ID + shape/range | 页序可变，稳定对象身份优先；不把 slide 内容存为普通 Markdown |

Office 布局输出须附 `contentRevision/layoutRevision/rendererVersion/fontManifest/viewport`。父文档根据返回的 intrinsic size、baseline/坐标系统进行布局；Word 目前图元单位是 twip，父 surface 的逻辑像素需要统一变换、裁剪及 hit-test 逆变换。不能把 page screenshot 当作可编辑语义层。

### 5.3 嵌入编辑分三级

1. 同屏只读：预览、文本提取、来源跳转；无需声称子对象能协作。
2. 激活领域编辑：父文档委托焦点给 Office surface，执行能力明确的命令；保存/撤销仍由子对象负责。
3. 子对象多人协作：该内核需要可重放、可合并或服务端序列化的领域操作及恢复协议。父文档 CRDT 只同步嵌入位置和配置，不自动覆盖子对象协作。

## 6. 按对象的协作与事务

协作底座面向所有领域横向共享，并位于领域内核的依赖下层；领域操作、冲突语义与业务不变量纵向实现。下表是分阶段交付策略，不表示 Word/Excel 永久采用快照，也不表示它们必须被嵌入智能文档才可协作。未来独立 Office/数据集编辑器与嵌入视图连接同一对象会话。粒度、分片与各领域协作合同详见[专项决议](OBJECTS-AND-COLLABORATION.zh-CN.md)。

建议首期矩阵：

| 状态 | 首期策略 | 后续演进 |
| --- | --- | --- |
| 正文/块结构 | AppFlowy/Yrs 支持的细粒度 CRDT + 领域不变量验证 | 验证复杂树移动、扩展 payload 的协作编码 |
| 简单属性/应用声明配置 | 类型化 map/明确字段策略，少量复杂配置用 CAS | 按冲突需求增加操作，不能静默整对象覆盖 |
| 数据库 records/view | 使用已有模型支持的操作/协作；关系约束另外验证 | 思源 AV 功能专项，计算/关系修复可追踪 |
| Word/Excel | 版本化领域快照 + 可用的单写者会话或只读嵌入 | 设计稳定操作 ID、锚点变换、重放/合并后再开放多人编辑 |
| PDF | 正文版本资源与注释层分开 | 注释可独立协作；改页内容另走 PDF 内核，不能认为注释协作覆盖正文编辑 |
| 附件/导出二进制 | 内容寻址、对象权限、manifest | 大内容按块/懒加载；不在正文 CRDT 放二进制 |

按对象拆分可以利用 Cloud 多 collab 对象；这里不假定需要 Yjs 原生 subdocument。官方明确 subdocument 同步由 provider 负责，因此仅嵌套一个 Y.Doc 并不保证 Cloud 具备其加载和授权能力。[Yjs Subdocuments](https://docs.yjs.dev/api/subdocuments)。

**声明的事务单元内原子、跨单元任务编排**：对象与事务边界不能强制等同，一个大型领域对象也可能跨多个分片。例如 Agent“汇总工作簿并插入报告”，先读指定工作簿版本，生成正文变更，提交时记录来源版本；需要同时改正文与工作簿时用 operationId、阶段状态、幂等与恢复记录。若业务要求全有或全无，就必须在 Cloud 增加可验证的协调/提交协议，不能以单份 CRDT 的事务替代跨单元原子提交。失败补偿也需检查版本，禁止回滚覆盖他人的后续修改。

检查点 manifest 至少记录：父对象 epoch/revision、子对象固定版本、附件摘要、schema/插件定义版本、来源关系与完整性状态。若各对象来自不同时间的读取，应明确这是版本集合；只有经过依赖屏障/一致性协议才能称为因果一致的全局快照。

## 7. Agent 是正式编辑主体

Agent 与人类/UI/第三方插件使用同一领域命令语义，传输方式可不同：本地高频输入直接调用核心，Agent 经受权的服务/工具入口，不能模拟光标作为唯一数据 API。

建议公共能力分四类：

```text
inspect: describe_schema, get_outline, read_nodes, read_object_range
query:   search, backlinks, query_collection, inspect_dependencies
mutate:  insert_blocks, edit_text, set_properties, bind_embed, execute_domain_command
observe: subscribe_changes, get_operation_status, list_checkpoints
```

MCP 可以发布这些查询与工具，普通工具 schema 不暴露私有存储。无客户端在线的服务端 Agent 也应在受限对象范围内调用同一服务语义；当前仅活动资源的本机 broker 不能直接充当这种服务。

示例命令信封：

```json
{
  "requestId": "req-01",
  "idempotencyKey": "job-42:insert-summary",
  "actor": {"kind": "agent", "id": "agent-7"},
  "target": {"resourceId": "doc-01", "nodeId": "block-12"},
  "preconditions": {"epoch": "e3", "nodeRevision": "n8"},
  "command": "document.insert_after",
  "arguments": {"blocks": [{"type": "muse/paragraph", "text": "分析结果"}]},
  "provenance": {"jobId": "job-42", "sourceVersions": ["workbook-01:v19"]}
}
```

actor 字段是审计描述，服务端从已认证会话绑定真实身份，不能由调用者声明身份来授权。命令结果返回 committed/conflict/rejected/pending、变更对象、修订、警告与恢复信息；网络接收回执不代表业务完成。

并发处理区分两类：人类字符输入用 CRDT 相对锚点合并；Agent 对“刚才读到的内容”的语义修改带节点/范围 hash、epoch 或版本前置条件。不要每次以整篇文档 revision 变化拒绝所有并发，也不能在目标语义已变时盲目自动重试。批量生成先形成有限大小的结构化变更集，支持预览/建议模式；已有授权允许自动提交时无需每步确认，权限由会话策略决定。

持久化 `actor/job/sourceVersions/requestId` 与最终 operation 关联；token 流或模型内部推理不是文档持久日志。Agent 的中间生成内容可作为私有草稿，明确提交的内容才进入共享历史。文档中的文本、代码和应用配置是输入数据，不因为被 Agent 读取就获得执行/联网/写文件能力。

## 8. 文档内应用

应用块由四部分组成：版本化 AppDefinition（界面/逻辑声明）、StateRef（持久数据）、Bindings（对象查询/命令映射）、ExecutionPolicy（权限与限额）。实例数据不能只存在 WebView 内存或 localStorage，否则其他端和 Agent 无法可靠读取、恢复或协作。

共享配置和业务数据进入受控领域对象；用户临时输入、展开状态、光标、网络连接与运行时句柄保持本地。确定性纯计算可从状态重建；外部服务调用通过带 requestId 的任务执行并记录状态/结果，渲染和重放历史不得重复发起付款、发消息等副作用。

例如审批应用由表单块读取 collection，按钮发出 `approval.submit` 命令，内核/服务校验权限与状态转换，产生事件；界面仅订阅并展示。Agent 可用同一查询/命令理解这个应用，无需截屏点击。

应用发布包含依赖和 schema 版本，导出文档时明确携带哪些定义/资源及哪些外部依赖仍需连接。运行时缺失则显示静态摘要/只读状态；插件卸载不能删除文档数据。未知应用仍可保留来源与状态，但不自动执行不认识的逻辑。
