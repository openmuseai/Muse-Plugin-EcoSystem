# 公开能力合同与 SDK

## 合同层次和命名

公开、版本化、可由第三方实现的生态合同承载系统需要而基础 MCP 没有定义的业务语义。标准方法仍是 `initialize`、`tools/list`、`tools/call`、`resources/read` 等；业务工具名称、合同目录和开发配置不被包装成 MCP 保留字段。

| 合同层 | 内容 | 维护者 |
| --- | --- | --- |
| 标准协议 | MCP、MCP Apps、JSON Schema、MCPB、Registry | 对应上游规范 |
| Host 通用服务 Profile | 资源授权与会话、项目文件、受限任务、保存、开发通道 | Host/生态维护者，公开 Schema 与 TCK |
| Provider 合同 | Slides/PDF/Agent/Voice 的业务输入输出 | 对应插件维护者 |
| DevKit 工具格式 | 项目需求、锁文件、解析计划、报告 | DevKit 维护者，独立版本 |

合同 ID 使用维护者拥有的稳定 URI，版本独立于插件实现版本；输入输出使用标准 JSON Schema，不引入自定义验证方言。示例合同 URI 是设计占位符，不表示域名、服务或合同已发布。

## Provider 应发布的合同包

```text
provider-api/
├── contract.json       # Profile 版本、合同 ID、SemVer、导出操作及映射
├── schemas/            # tools/list 输入输出 Schema
├── client/             # 生成的轻量客户端和类型
├── docs/               # 语义、错误、权限、兼容性、迁移
├── mocks/              # 确定性的返回值与失败场景
├── fixtures/           # 有授权与许可的样本
└── tck/                # 可针对真实发行包执行的契约测试
```

包由 Provider 独立发布，包含内容摘要、许可和实现支持范围。市场索引它与发行包的关系，DevKit 缓存并生成 SDK。合同包中的导出映射是公开生态 Profile，不新增 Host 私有字段到 MCPB/Registry。

运行时可以把合同作为普通 MCP 资源公开；已锁定的合同和工具 Schema 在 Gateway 中核对。不能只凭工具名称或相同 JSON 字段猜测语义兼容，也不能运行时从任意 URL 自动下载并执行未审核 SDK。

## 最小业务接口

| Provider | 第一版公开能力 | 语义要求 |
| --- | --- | --- |
| GenOffice Slides API | readSnapshot、readNotes、getPreview、getState、goToSlide | 实时会话、revision、稳定页引用、正确画布预览 |
| PDF API | readSnapshot、getPageText、getPreview、getState、goToPage | 可选择文本与扫描件状态、页数/旋转/尺寸、受限预览 |
| Agent API | generate、任务状态与取消 | 输入输出 Schema、费用/数据出站、错误和取消回执 |
| Voice API | synthesize/speak、pause、resume、stop、状态 | 语言支持、音频资源、播放状态、音频焦点与生命周期 |

GenOffice 0.5.0 已有工具不被直接改名或覆盖。通过新发行版本增加公开合同及兼容适配，保留已发布行为。只读、导航、写入和保存分开授权；API SDK 不包含引擎源码。

PDF 无文字层时应返回明确状态；OCR 是独立可选能力，不能把空文本当成功讲解。加密或不支持的文档明确报错。讲解插件不复制 PDF 渲染引擎来弥补合同缺失。

第一阶段业务合同先由已有 Provider 维护；出现第二个真实实现后可抽取中立语义 Profile，并用适配器验证。Host 不因为增加 PDF 或其他格式而加入业务 switch。

## 多能力依赖模型

### 最小公开通用服务

下表为待冻结的公开服务语义。具体工具名和完整 Schema 由 DK-002 发布；它们通过普通 MCP tools/resources 承载，不使用未公开 Host command，也不要求插件识别原生通道名称。

| 服务 | 输入语义 | 结果语义 | 执行边界 |
| --- | --- | --- | --- |
| 选择资源 | 命名角色、数量、MIME 过滤、请求操作 | 用户授权的不透明资源引用 | Host 原生授权；多选不隐式授权整个目录 |
| 绑定能力 | 合同 ID/版本范围、操作集、资源引用、可选 Provider 约束 | 受限工具导出映射、绑定状态、支持特性 | Host/Gateway 验证调用者与已安装 Provider |
| 释放绑定 | 当前调用者拥有的绑定引用 | 撤销结果 | 不接受他人的凭据或绑定 |
| 项目操作 | 授权工程引用、相对路径、预期摘要、补丁 | 新资源版本或明确冲突 | Workspace/项目 Provider；不允许任意系统文件 |
| 执行任务 | 工程引用、已许可的任务定义和工具链 | 任务资源、状态与取消入口 | Runner；shell 和挂载策略留在 Runner 内 |
| 插件安装计划 | Registry 来源、插件/版本和依赖要求 | 候选安装图、权限/兼容结果 | 市场插件与 Host 安装管理，用户确认后执行 |

DevKit 在选定 Host 缺少这些服务时停留在环境检查，提示具体更新/安装项，不能调用内部 Dart 接口绕过。基本合同、能力目录和工具映射可缓存为普通资源；能力缺失不能以假 `serverTools` 协商结果掩盖。

### 发布依赖元数据

`devkit.project.json` 记录开发期意图，`devkit.lock.json` 记录精确验证组合；两者都不作为 Host 私有运行时 Manifest。打包器从中生成最小 `devkit/dependencies.json` 公开生态 Profile，包含合同范围、所需操作、功能/目标和可选 Provider 约束，随不可变包一起审核并由市场索引。

该 Profile 不包含工程路径、Runner 会话、开发者登录、运行租约或共享锁文件中的本机信息；不向 MCPB/Registry 基础 Schema 塞未知顶层字段。只支持基础 MCPB 的其他 Host 可以使用其基本工具功能；组合能力必须在支持该公开 Profile 并通过测试的 Host 上启用，不能宣称所有 MCP 客户端都能自动安装依赖。

开发元数据、运行依赖 Profile、合同描述和 TCK 报告都在 M0 发布完整 Schema；当前示例只提供开发配置的结构草案，不能把其 Schema 校验通过当成所有运行格式已冻结。

### 功能和约束

项目配置分别声明目标、能力和功能。能力需求包含合同范围、操作集、可选 Provider 约束；功能以 `allOf` 关联所需能力。可选功能的不可用不阻塞核心功能，但发布页面与设备功能矩阵必须反映实际状态。

`allOf` 是本生态开发配置中的字段，不冒充 JSON Schema 关键字的求值语义。同一合同的多个候选 Provider 是替代实现，不等于两个业务能力可互相替代。SDK 不设“一个插件只能依赖一个 Provider”的数量限制；执行预算、循环检测和 Host 资源预算限制实际图规模。

### 解析过程

1. 将自然语言/选择器结果转为显式的功能与合同需求。
2. 固定目标 Host 的精确构建、协议 Profile 和设备平台。
3. 按目标功能找已上架且能新安装的 Provider，核对合同、操作、运行方式和测试状态。
4. 展开传递依赖，检测循环与互斥约束，对同 Provider 多项操作求共同版本交集。
5. 生成确定性的候选计划；多候选遵循显式绑定、用户偏好及兼容排序，不能按插件名猜能力。
6. 对每端、每功能给出 ready/blocked/degraded，并说明缺失项与最小冲突集合。
7. 用户确认安装/新增权限后固定精确 Provider、SDK、合同、工具链和工件摘要。
8. 安装和真实工具发现再次校验；目录记录本身不能证明设备运行成功。

默认同一项目/目标内同 Provider 使用一个活动版本，版本冲突明确阻塞。多版本并行不是首版承诺。开发 Mock 不能成为正式发布依赖；已下架版本可显示本机旧安装状态，但干净环境新安装验证不可绕过下架。

### 锁文件和环境覆盖

共享锁文件固定开发与测试的精确组合和内容摘要。机器路径、账号、授权租约、token、设备序列号及运行时用户偏好放入本机状态目录，不能进入共享锁文件。

实际用户运行时先采用其已安装且通过相同合同验证的 Provider，再遵循显式选择；发布依赖定义兼容范围，测试证据固定精确组合。更换 Provider 或升级必须重新验证绑定，不能静默换实现继续旧会话。合同结构兼容检查是辅助，最终还需语义 TCK。

## SDK 包与接口

| 拟定包 | 责任 | 不包含 |
| --- | --- | --- |
| `@openmuse/plugin-sdk` | Apps/MCP 协商、资源引用、能力绑定、通用错误与日志 | Host 私有命令与 Flutter SDK |
| Provider API 包 | 类型、调用映射、输入输出校验、业务文档 | GenOffice/PDF 引擎或 DSH 内部协议 |
| `@openmuse/provider-sdk` | 从 Schema 定义/生成工具、合同、Mock、TCK | 自动获得 Host 权限 |
| `@openmuse/devkit-core` | 项目规划、依赖解析、生成、构建/测试/发布编排 | UI 组件和 Host 内部状态 |
| `@openmuse/devkit-cli` | 可选命令入口，拟定可执行名 muse | 独立的第二套发布逻辑 |

SDK 面向标准协议，可用其他官方 SDK 调用相同公开合同。首版 TypeScript，后续按需求生成 Dart/Python 等客户端；不同时手工维护多语言的业务语义。

### DevKit 对 Agent 的工具面

拟定普通 MCP 工具：`devkit_plan_project`、`devkit_resolve_dependencies`、`devkit_initialize_project`、`devkit_apply_patch`、`devkit_start_run`、`devkit_test`、`devkit_pack`、`devkit_submit`。这些名称属于 DevKit 公开业务合同，由 DevKit 插件执行，不是新 Host 协议或 MCP 保留方法。

工具结果有 outputSchema/structuredContent。耗时任务返回普通任务资源并提供状态/停止操作；标准 MCP Tasks 扩展仅在真正实现并协商后启用。工具接收项目范围引用，不接收任意系统 shell、宿主内部 Workspace ID 或可替换的账号 token。

项目变更带预期版本/摘要，补丁过期应拒绝并要求重新读取。`submit` 只上传并创建待审提交，不含 approve/reviewer 操作。

## 权限、隔离和故障

一次绑定至少受调用者身份、资源会话、Provider 实例、允许操作和有效期限制。普通资源引用不能作为 bearer token。Host 在最末转发前再次校验，防止先列工具后撤权的竞态。

| 场景 | SDK 级语义码示例 | 行为 |
| --- | --- | --- |
| 缺少必需 Provider | PROVIDER_UNAVAILABLE | 展示安装/替换计划，禁止静默使用 Mock |
| 合同或版本冲突 | CONTRACT_INCOMPATIBLE | 返回冲突需求和当前支持范围 |
| 缺少资源权限 | PERMISSION_REQUIRED | 交给 Host 请求范围授权，不自行弹假授权框 |
| 资源关闭或绑定失效 | RESOURCE_SESSION_CLOSED | 停止后台读取/播放，等待重新选择 |
| 内容版本冲突 | REVISION_CONFLICT | 重新读快照，不覆盖用户修改 |
| 超预算或取消 | BUDGET_EXCEEDED / CANCELLED | 释放任务，确认 Provider 实际终止状态 |

这些码是拟定 SDK/生态业务语义，在线路上使用标准 JSON-RPC 错误或 MCP `isError` 与公开错误 Schema 映射，不给保留错误码重新赋值。Host 与 Provider 分别执行其授权和业务校验，annotations 不作为安全凭证。

## 兼容、撤回和文档维护

协议版本、Host Profile、SDK、业务合同、Provider 实现和模板分别编号。latest 只在显式创建/升级时解析。Schema 必填字段变更、枚举收窄、返回语义变化都进入破坏性检查；不能只依据插件版本递增判兼容。

API 包、文档、Skill、Mock 和 TCK 固定同一合同摘要。发布 TCK 覆盖授权拒绝、并发修改、关闭、升级、错误和多端功能；提供者通过单项 TCK 不等于所有消费者组合已经验证。

Contract/依赖 Profile 必须先公开完整 Schema、示例、版本策略及独立测试，再让 SDK 和 Host 依赖它。开发配置示例使用本地 Schema 校验；示例中的未来 Provider/合同不得出现在真实兼容目录。
