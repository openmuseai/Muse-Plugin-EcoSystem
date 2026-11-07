# 视觉交互评审与架构反推

> 历史方案：当前 Desktop/Web 基线已更新为 [v1.2 功能对齐视觉稿](12-FUNCTIONAL-ALIGNMENT.zh-CN.md)。本文件和旧原型仅保留布局探索与行为试验；指定参考页精确布局仍待核对，详见 [11](11-WPS-DESKTOP-REFERENCE.zh-CN.md)。

2026-11-05，v1.1。视觉稿为可点击产品提案，采用类似 Figma 原型的画面/状态/跳转组织；不是 .fig 文件，也不是已实现客户端。

## 1. 交付与来源

交互原型提供三种布局：**工作区协作、专注创作、移动端**。当时的工作区布局作为历史评审基线，专注模式是同一对象的布局变化，移动端验证触控/上下文展开。

设计依据为现有 [Host 工作区实现](../../../../../../Muse-Client/app/openmuse_host/lib/src/host/workbench_shell.dart)、[Host 主题 token](../../../../../../Muse-Client/packages/openmuse_host_shell/lib/src/theme.dart)、[Home 资源中心合同](../../../../../../Muse-Client/docs/design/mobile-resource-center/IMPLEMENTED-CONTRACT.zh-CN.md)和[既有工作区图](../../../../../../Muse-Client/docs/meterails/assets/dsh-in-codex/fig1-openmuse-workspace.png)。Host 的侧栏/编辑标签/既有 Agent 区域归属保留；评审尺寸下作适度压缩，具体生产尺寸随现有布局组件实现。

源码保存在本目录 `visual-review/prototype.fragment.html`，浏览器检查为 `visual-review/review-check.cjs`；生成预览只用于本地检查，不发布网站。截图和 QA 报告见 `visual-review/screens`。示例数据与 PDF 示意页明确标注，不读取真实用户内容。

静态对照：[工作区](visual-review/screens/desktop-workspace.png)、[专注模式](visual-review/screens/focus-creation.png)、[移动端](visual-review/screens/mobile-resource.png)、[Agent 冲突](visual-review/screens/agent-target-conflict.png)、[协作不可用](visual-review/screens/collaboration-unavailable-local-edit.png)。交互原型可覆盖截图无法表达的来源共用与提交状态变化。

## 2. Frame / 状态 / 跳转

| Frame | 画面与操作 | 下一个状态 |
| --- | --- | --- |
| F01 工作区资源 | 侧栏选资源、正文、任务视图、材料、Agent | 打开来源进入 F04；生成建议进入 F06 |
| F02 专注创作 | 收起全局导航，保留资源身份与 Agent 开关 | 展开同一上下文，不创建另一个会话真源 |
| F03 Mobile 资源 | 返回式资源页、正文和底部内容操作 | 展开 Agent/评论后返回同一资源 |
| F04 独立数据集 | 单独标签查看/改变任务状态 | 回 F01 看见相同记录状态 |
| F05 插入材料 | 选择示例资源、页和固定版本 | 插入引用块，保持来源独立 |
| F06 Agent 建议 | 显示建议、来源及未提交状态 | 应用到明确目标；丢弃；目标变化进入 F07 |
| F07 目标冲突 | 人类先编辑正文，再应用旧建议 | 不覆盖原文；重新读取/生成或丢弃 |
| F08 分享/角色预览 | 评审编辑者/评论者/只读行为 | 评论者不能改正文但可以评论 |
| F09 保存/连接状态 | 演示离线、服务不可用与恢复 | 正文继续本机编辑；记录提交按在线能力限制 |
| F10 历史 | 预览正文版本、退出或恢复新版本 | 不自动回滚独立数据集 |
| F11 插件与能力 | 内容编辑、Cloud 连接、PDF provider 分开显示 | 停用连接不卸载内容内核 |

F08 的“评审角色预览”和 F09 的“演示”操作是原型控制，生产界面不能允许用户通过自选角色获得权限。生产产品的实际能力仍由受权服务裁决。

## 3. 视觉与交互规范

采用 Host 轻量侧栏、低噪声分隔、主色强调与系统字体；支持浅/深色。默认正文是阅读流，数据/材料采用有来源的嵌入容器，不把所有块都做成仪表盘卡片。

所有关键操作有文本/可访问名称，触控目标和窄屏换行明确；状态不只用颜色表达。对话框可关闭，输入不是截图；表格/看板与来源标签可点击。浏览器初版原型不模拟完整分页/媒体播放/任意代码应用。

## 4. 从视觉行为反推架构

| 视觉行为 | 最小合同 | 包 / 插件归属 | 生产验证 |
| --- | --- | --- | --- |
| F01/F04 状态共用 | objectRef、实体 ID、观察/领域命令 | 内容 plugin + 资源合同 | 真服务多入口与 Agent 共用同对象 |
| F02/F03 布局切换 | SurfaceHandle、焦点/视口、受限会话 | Host + 内容 surface | 退出/后台/窄屏不丢草稿、不双写 |
| F05 材料引用 | selector、版本、binding、可访问文本 | 对应内容 provider | 真 Office/source/ACL/坐标/缓存 |
| F06/F07 提交/冲突 | 目标/来源版本、幂等 patch、回执 | 领域 binding + Agent 服务 | 服务端原子重验、并发不覆盖 |
| F08 只读/评论 | access scope、命令能力 | Host 身份 + 服务端 ACL | 原始更新入口同样拒绝越权 |
| F09 连接与保存 | persistence、sync、durability receipt | runtime + Cloud provider | 磁盘/配额/崩溃/重连真实故障注入 |
| F10 恢复 | checkpoint/epoch/依赖 manifest | 领域 binding + 协作合同 | 旧队列隔离、保留待处理草稿 |
| F11 停用连接 | provider 生命周期与依赖描述 | 能力 registry + 协作 provider | 内容算法仍可用；算法缺失正确只读 |

## 5. 评审顺序

先走 U1：改变任务状态 → 独立来源 → 回文档；再走 U2：生成建议 → 修改概览 → 应用触发冲突 → 重新读取；最后走 U3：停用协作连接 → 写正文 → 恢复连接。然后检查评论/只读、历史、窄屏与插件依赖。

评审意见使用 Frame ID + 操作/期望/实际，区分产品范围、交互表达、视觉细节与技术缺口。流程未通过时先修用户行为和最小合同，不先扩大基础设施建设。

## 6. 运行检查与限制

原型浏览器检查覆盖同源数据视图、Agent 前置条件冲突、角色边界、连接失效、本机可编辑表达、历史只读、专注/移动布局与窄屏溢出。实际执行结果及浏览器版本以 `visual-review/screens/QA.json` 为准。

原型没有真实账号邀请、剪贴板写入、Cloud、CRDT、文件保存或原生 Office 渲染。这些仍按既有 AC-01–AC-17 和新增 package/领域兼容测试验收。浏览器原型测试通过不等于产品通过。
