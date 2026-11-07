# 智能文档 v1.2：功能对齐、视觉稿与架构反推

> 产品/交互冻结基线：**SD-BL-1.2-20261105**。以 [冻结记录与快照](../../13-FROZEN-BASELINE.zh-CN.md) 为准；技术实施见 [14](../../14-ENGINEERING-DESIGN.zh-CN.md)/[15](../../15-EXECUTION-PLAN.zh-CN.md)。

2026-11-05。目标是对齐 WPS 智能文档的**功能组织、内容编辑及协作任务流**，作为 Desktop/Web 新评审基线。原型是独立可点击设计稿；没有部署运行产品、连接真实 Cloud 或修改参考文档。证据及无法观察的部分见 [11](11-WPS-DESKTOP-REFERENCE.zh-CN.md)。

## 1. 页面结构和设计取舍

第一视觉中心是可写的连续内容流。全局资源树由 Muse Host 承担，不在内容插件内再造；目录只代表当前文档结构。编辑页依次有资源标题/成员/分享、文档菜单、常用格式工具、正文与可选侧栏、底部保存状态。评论默认展开以便评审协作；生产中记忆用户的开关偏好。

Agent 是上下文操作和可切换侧栏，评论/历史/Agent 同时只展开一个右侧面板。打开面板不创建新文档、不改变数据源、不扩大 Agent 授权。页内数据集和 Office 资源有来源入口，不以普通文档表格替代专业工作簿。

Desktop 原生窗口保留 Host 工作区标签；Web 由资源路由装配同一编辑 surface。具体平台外框可以不同，领域命令、选区语义、内容和协作状态一致。Mobile 最终仍按 [05](05-UX-SPEC.zh-CN.md) 的专用触控方案实现。

## 2. 功能映射与本次覆盖

`DOC` 为公开手册支持的方向，`MUSE` 为我们的取舍；均不代表指定企业页面已观察。源链接集中于 [11](11-WPS-DESKTOP-REFERENCE.zh-CN.md)。优先级沿用 SD-01–SD-17；以下 FA 编号只细化任务，不扩大 0.1 发布承诺。

| ID / 需求 | 功能与交互要求 | 依据 | 可点击稿覆盖 | 产品实现边界 |
| --- | --- | --- | --- | --- |
| FA-01 / SD-01,15 | 标题、资源位置、成员、分享 | DOC + MUSE | 示例成员/权限设置 | 真实角色由平台 ACL 裁决 |
| FA-02 / SD-02 | 常用格式、段落样式、列表/任务、对齐 | DOC | 选区加粗/斜体/下划线/高亮、样式、任务与对齐 | 字号、颜色、缩进、列表编号和复杂选区补入生产 surface |
| FA-03 / SD-02 | 选区工具与顶部工具使用同一命令 | DOC + MUSE | 实际鼠标选择片段后格式/评论 | 跨块/跨单元格选择、IME 和 undo 归属在 G0 验证 |
| FA-04 / SD-02 | 段落柄、下方插入、排序、移除、稳定链接 | DOC + MUSE | 复制/上移/下移/移除、示例链接 | 原型以按钮代表移动；拖拽、跨父节点和链接路由须实现 |
| FA-05 / SD-02,12 | 顶部、`/`、段落入口复用一个插入目录 | DOC + MUSE | 搜索、文字/列表/表格/代码/引用/高亮/公式源等 | 原型仅基本词匹配；正式版含键盘候选、别名、能力过滤 |
| FA-06 / SD-02 | 基础表格属于正文 | DOC + MUSE | 3×3 可编辑单元格、撤销/重做 | 行列操作为首版基础能力；合并/拆分等复杂表格按 P1 |
| FA-07 / SD-06,07,10 | 数据集、工作簿、PDF 各有独立对象 | DOC + MUSE | 数据源共用、移除引用后重新插入、PDF 来源示例 | 不含真实 PDF/Workbook 渲染；遵守 SD-07 真 provider 门槛 |
| FA-08 / SD-03 | 在线成员、远端位置、来源信息 | DOC + MUSE | 本地固定成员/远端编辑位置示例 | 真多连接 awareness、TTL、位置映射另验 |
| FA-09 / SD-05 | 选区/段落评论、回复、提及、解决/重开 | DOC | 引用摘录、回复、解决/历史/重开；@插入示例 | 原型不发通知；锚点重定位、通知去重与 ACL 另验 |
| FA-10 / SD-15 | 可编辑/可评论/可阅读有明确差异 | MUSE | 评审身份切换并阻止相应操作 | 评审开关不能进入生产权限入口 |
| FA-11 / SD-13 | 历史版本、协作记录、历史评论分开 | DOC + MUSE | 命名快照、只读预览、恢复、定位操作、已解决评论 | 原型原位预览；正式版可比较窗口，跨端返回语义一致 |
| FA-12 / SD-04 | 本机保存、待同步、云确认独立 | MUSE | 在线/离线/不可用，正文仍可写而记录不提交 | 所有回执和持久化均模拟，不能据此宣告恢复可靠 |
| FA-13 / SD-09 | Agent 针对明确目标、旧建议不得覆盖新内容 | MUSE | 建议、检测文档 revision 变化、重读、提交 | 正式版按目标实体及读集前置条件校验，避免全局 revision 误冲突 |
| FA-14 / SD-17 | 窄屏、浅深色、无溢出、面板关闭 | MUSE | 宽屏主界面与窄屏上下排列 | 窄屏是评审降级，不代表最终手机键盘/抽屉实现 |

公式原型显示可编辑 LaTeX 源，不宣称已经提供数学排版。基础文本编辑原型在重新输入段落时清理原有格式标记，仅用于操作评审；正式版需维持 runs/marks、撤销和组合输入的正确语义。原型不实现完整 Markdown 输入规则、富剪贴板、文件上传、真实视频和表格行列工具；这些仍按原 PRD 验收，不用空按钮冒充完成。

## 3. Frame 与关键评审路径

| Frame | 状态 / 可执行动作 | 预期变化 |
| --- | --- | --- |
| WF-01 编辑主界面 | 文档菜单、格式工具、目录、正文、评论 | 内容居中，正文可写，侧栏可关 |
| WF-02 文字选区 | 拖选正文 → 加粗/高亮/评论 | 仅格式化选中字串，评论带原文摘录 |
| WF-03 插入 | 在段落按 `/` 或点击插入，搜索 table/todo/代码 | 在当前块之后插入；取消不改正文 |
| WF-04 段落操作 | 柄 → 上下移动/复制/移除 | 块结构改变；移除外部视图不删真源 |
| WF-05 协作者 | 点头像或查看位置 | 定位远端内容，不抢本地光标 |
| WF-06 评论讨论 | 回复 → 解决 → 已解决 → 重新打开 | 线程身份和原文引用保留 |
| WF-07 分享 | 查看成员、改变示例成员角色 | 不发邀请；生产接平台受权提交 |
| WF-08 协作记录 | 文件 → 历史记录 → 协作记录 | 按事件定位当前内容，删除目标说明失效 |
| WF-09 历史版本 | 预览 → 恢复 → 确认对象范围 | 只读预览；恢复建新版本，保留旧正文，不回滚外部记录 |
| WF-10 连接变化 | 评审设置 → 离线/不可用 | 本机正文可编辑，评论/记录提交禁用 |
| WF-11 Agent | 生成 → 人类改段落 → 应用 → 重读再应用 | 旧建议拒绝，保留人类修改 |
| WF-12 窄屏与主题 | 浅/深色、360px 宽 | 工具换行、目录收起、面板下置，无页面横向溢出 |

建议评审次序：WF-01→02→03→06→07→09→10；再走外部数据共用、移除引用和 Agent 目标冲突。首先评审日常写作和团队协作，再核对指定页的工具排序/精确几何。

## 4. 视觉规格

| 区域 | 本次可评审规格 |
| --- | --- |
| 页头 | 紧凑标题、来源路径、在线人、评论、分享 |
| 功能区 | 菜单与常用工具分两行；按撤销、段落、文字、列表、插入、评论分组 |
| 正文 | 系统中文字体；正文 14px/1.6；文档标题 28px，节标题 20px；中心最大 840px，随侧栏自适应 |
| 内容容器 | 连续阅读流；表格保留行列关系；资源引用显示来源；高亮块轻底色 |
| 目录/侧栏 | 目录 138px、侧栏 266px，宽度随评审窗口调整；窄屏采用重排 |
| 配色 | Muse accent #4c63d9；浅/深色配对；权限/同步状态有文字 |
| 交互反馈 | 活动选区/段落、禁用原因、来源和版本明确；hover 不承担唯一入口；对话框可关闭并约束键盘焦点 |

以上是我们的设计 token，不是对 WPS 页面测量的结果。代码原型和截图是可检查的视觉交付，不是 .fig 文件。

## 5. 由交互反推的架构合同

| 用户行为 | 必需合同与责任 | 分层 / 任务 |
| --- | --- | --- |
| 顶部、选区和段落柄做相同格式操作 | EditorCommandRegistry、SelectionSnapshot、capability/enabledReason；统一投递领域命令 | 内容 surface + 领域 package；T05/T08 |
| 打开菜单后仍操作原来的选区 | surfaceId/entityId/anchor/range/focusToken；IME 期间不提交结构变更；关闭后恢复合法焦点 | surface 适配；T08/T09/T22 |
| 子工作簿内撤销不删掉整个引用块 | activeSurface、enter/exit 及 undoOwner；事件在 surface 边界路由 | Host + ioffice adapter；T09/T14 |
| 插件新增元素后各入口一致 | 同一 ElementDescriptor 贡献菜单、slash 别名、可读能力及渲染器；availability 由平台/安装/ACL 求交 | registry + 版本化 profile；T18 |
| 远端用户移动光标不改变正文 | ephemeral awareness、TTL、会话身份、领域位置映射；不作为持久正文写入 | 协作合同/runtime + domain binding；T06/T08 |
| 评论跟随文字、删除后仍能追溯 | AnnotationThread 独立持久实体；anchor adapter 留在领域；孤儿锚点与线程解决状态分开 | annotation 服务 + binding；T05/T10 |
| 分享可评论但不能改正文 | 服务器区分内容 mutation 与 comment command；原始 CRDT 入口也执行授权/结构验证 | ACL + provider + server；T06/T10 |
| 回看版本与查看谁做了什么 | checkpoint、semantic activity、annotation history 分流；不能从 awareness 推断审计 | 核心历史 + 事件投影；T10/T13 |
| 恢复正文时外部记录保持 | checkpoint 依赖 manifest 指明 fixed/live；restore 明确对象集合和 epoch/旧队列处置 | 领域恢复 + runtime；T13 |
| 可用性随角色和连接变化 | capability snapshot、撤销事件、local durability/sync receipt 分开；服务端提交时仍重验 | Host session + runtime + domain；T06/T07/T10 |

任务号与 [实施计划](../../06-IMPLEMENTATION-PLAN.zh-CN.md) 一致，不表示这些包已实现。更细的 package 边界见 [09](../../09-COLLABORATION-PACKAGES.zh-CN.md)。UI 对齐不要求将 Word/Workbook 模型变为文档块，服务端继续基于 Muse-Server/AppFlowy-Cloud。

## 6. 交付文件、检查与边界

本目录 `wps-functional-review/prototype.fragment.html` 是可点击视觉源；`review-check.cjs` 是本地操作检查；`screens/QA.json` 记录实际执行结果及浏览器版本。截图：[主编辑页](wps-functional-review/screens/desktop-editor.png)、[评论协作](wps-functional-review/screens/collaboration-comments.png)、[分享](wps-functional-review/screens/share-permissions.png)、[历史预览](wps-functional-review/screens/history-preview.png)、[离线](wps-functional-review/screens/offline-editing.png)、[深色](wps-functional-review/screens/desktop-dark.png)。

检查针对本地原型的 DOM 与状态行为，不测试 WPS 页面，不证明真实多人收敛、账号授权、磁盘耐久、Office 渲染、原生输入法和设备性能。实际产品仍走 AC-01–AC-17；精确参考页视觉对比仍是 TARGET-PENDING。
