# Muse CI 设计与验证记录

日期：2026 年 11 月 18 日。以下为初版六视图的历史验证记录；新增节点画布的当前结果见 [流程编辑器记录](04-WORKFLOW-EDITOR.zh-CN.md)。交付性质：产品定义、跨端交互原型与本地状态模型；不是已经接入 Host 的发行版本。

## Skill 与视觉方向

按用户要求使用工程内 [tasteskill v2](../../../../Muse-Client/.agents/skills/design-taste-frontend/SKILL.md)，参照已有插件应用组件的适配方式。该 skill 主要面向营销网页，本轮仅采用应用组件的排版、色彩、状态、焦点、反馈及 look-and-fix 流程，不照搬营销图片配额、Hero 或滚动叙事。

方向为“交付记录台”：把当前工程的目标、待决定事项、检查证据和十二阶段关口组成一份可操作的交付记录。实色冷灰背景、白色内容表面、深绿色单一操作强调色，系统字体，无远程字体/图片/CDN。图标是统一的代码内线性 SVG；没有图片生成或外部素材版权依赖。

本轮没有抽签或 redraw seed：沿用既有插件应用组件方向，采用 skill 的单组件/已有设计适配。主交互是从目标生成本地计划，运行后处理阻塞决定并继续；所有执行和报告都显式标记为示例。

## 交互与状态

- 总览、计划、运行、证据、发布、设置六个视图；Desktop/平板稳定侧栏，手机底部导航与更多菜单。
- 创建草案、目标/预算验证、计划版本、输入变更后清除旧决定。
- 运行版本固定，暂停、恢复、取消及阻塞状态互斥；断开示例连接后禁止需要连接的运行控制。
- 手机首屏待决定入口；对话框使用原生 dialog，支持 Escape 和焦点返回。
- 证据分类、报告详情和本地 JSON 下载；发布页始终保留真实制品与验收缺项。
- 本地存储使用独立键；拒绝部分损坏结构，重置仅影响本原型。用户输入转义为文本。

## 第一轮截图复核

ROUND 1
Seen in one second: 目标、任务与待决定事项构成一个交付工作区。
Idea (one sentence): 把真实工程的发布关口和证据作为产品的主线。
Live thing: 本地计划、运行及阻塞决定的可操作闭环。
Layout words by section: shell=稳定导航 / overview=当前交付与任务 / aside=待决定与活动 / mobile=纵向阅读和底栏。
Scores: design 7.3 · usability 7.0 · creativity 7.0 · content 7.8 → overall 7.3（应用设计自评，不作为营销页面奖项评分）。
Caps applied: 未将营销页面的图片/视频/八处滚动动效规则用于真实工作台；原始工具结果仍保留。
Top three problems (most visible first), each with the screenshot it shows in and the fix:
1. tablet-fold：项目切换器副标题换成三行，移除窄侧栏中的次要说明。
2. mobile-fold：待决定区处于长列表下方，在首屏增加汇总入口。
3. mobile-fold：部分描述字体较小，正文说明调为至少 13px，主要点击区域补到 44px。

## 第二轮截图复核

ROUND 2
Seen in one second: 用户知道当前要交付什么、下一步去哪里，以及是否有决定待处理。
Idea (one sentence): 同一条交付记录在桌面展开，在手机收敛成可行动的任务。
Live thing: 新建、固定计划版本、运行、决策阻塞、继续和证据查看。
Layout words by section: shell=双端导航 / overview=内容主列 / decision=桌面右栏、手机入口 / release=可检查的阶段列表。
Scores: design 7.7 · usability 7.8 · creativity 7.2 · content 8.0 → overall 7.7（应用设计自评）。
Caps applied: 与第一轮相同的应用适配边界。
Top three problems (most visible first), each with the screenshot it shows in and the fix:
1. mobile-fold：正文可读性和入口已修复；真实长日志仍应在后端分页后继续验收。
2. desktop-fold：当前只有单个固定示例项目；多项目选择和空态需要真实服务数据。
3. 所有视口：连接、运行和审批仍是本地交互；不据此给出真实跨端安装或执行通过结论。

## Taste 检查范围

[静态 lint](evidence/taste-lint.log)：0 FAIL、0 WARN。

原始第一轮渲染记录在 evidence/taste-round1。最终 [inspect 日志](evidence/taste-inspect.log) 为 0 FAIL、0 WARN，使用四项显式应用场景 allowance：

| Rule | 原因 |
| --- | --- |
| icon-cards | 识别对象是实际任务/导航行，不是营销图标功能卡片 |
| few-pictures | 这是应用工作台；添加图片会替换有用状态，没有产品理由 |
| still-page | 工作台采用按需交互反馈，不加入八处滚动动效来满足营销度量 |
| no-footage | 没有需播放的视频内容，不添加装饰视频 |

没有豁免溢出、对比度、标题裁切、失效图片或页面级 data-ui 滥用。data-ui 仅标记局部真实界面组件，未套在 body 或整体页面上。该检查不是 WCAG 合规认证。

## 验证证据

- `npm test`：6 项有意义的状态测试，覆盖固定计划、重复运行、断连、决定阻塞、取消、旧决定失效及损坏存储。
- `npm run build`：生成独立 dist/index.html，无在线依赖；该文件不是市场安装包。
- `node scripts/verify-ui.mjs`：使用生态仓库已有 playwright-core 和本机 Chrome；18 个视图/视口组合均无横向溢出，浏览器无脚本错误。
- 浏览器验证包含新建计划、暂停恢复、决策闭环、刷新恢复、取消确认/关闭、证据筛选下载、提审阻断、断连门控、手机决定入口及 file:// 直接预览。
- [浏览器验证 JSON](evidence/ui/verification.json)、[日志](evidence/browser-verification.log)、[状态测试日志](evidence/model-tests.log)。

## 预览截图

- [Desktop 总览](evidence/taste-inspect/desktop-fold.jpg)
- [平板总览](evidence/taste-inspect/tablet-fold.jpg)
- [Mobile 总览](evidence/taste-inspect/mobile-fold.jpg)
- 六个视图各尺寸截图位于 evidence/ui，文件名为宽度加视图名。

## 正式接入前待办

实现并验证 Host 可安装远端 App 的通用合同，将本地 adapter 替换为标准 MCP tools，接入真实授权、项目数据、执行和证据。随后在实际 OpenMuse macOS/Android/iOS 内验证安装、登录、工具、生命周期和可信用户决定。当前不修改 Host，也未构造虚假的 Registry、服务器地址或安装回执。
