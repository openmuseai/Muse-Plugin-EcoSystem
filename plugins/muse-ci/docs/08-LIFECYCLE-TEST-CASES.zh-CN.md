# Muse-CI 生命周期改造测试用例

测试输入为本轮后端与插件源码；业务回归使用独立 PostgreSQL schema / Temporal queue 和独立 UI 验收项目，不能用正式上架任务的状态模拟通过。以下“通过”以测试报告及对应断言为准。

| ID | 前置 / 操作 | 预期 | 验证入口 |
| --- | --- | --- | --- |
| LC-01 | 新建版本和独立需求 | 分别为五 Step，节点配置与总文档独立，所有依赖在同 Step 内 | lifecycle.test / UI |
| LC-02 | 同 commandId 并发创建版本和子需求 | 只产生一个身份、一条父子关系和总文档入口 | lifecycle-e2e |
| LC-03 | 从主画布进入子需求并返回 | 不平铺子需求节点，标题、上下文与 URL 一致 | 浏览器 |
| LC-04 | 保存跨 Step 节点边 | 拒绝；画布仅绘制同 Step 边，Step 箭头有序 | lifecycle.test / 浏览器 |
| LC-05 | 前序 Step 未完成或文档未发布 | 后续节点不就绪、后端拒绝启动，显示具体缺项 | lifecycle.test / UI |
| LC-06 | 无依赖同 Step 节点与 A→B | 无依赖可并行；B 等待 A，显示上游在前 | graph.test |
| LC-07 | 人工标过并撤回 | 状态独立、操作者原因留痕，不生成成功 Attempt；下游失效 | lifecycle.test / 浏览器 |
| LC-08 | 标过但缺用例/测试报告/MR回执 | 不得作为实际测试或合并交付，版本回归不能绕过 | lifecycle.test / lifecycle-e2e |
| LC-09 | 人与 Agent 同一版本并发写文档 | 一方冲突，重读后再贡献；原内容保留 | lifecycle.test / lifecycle-e2e |
| LC-10 | 按旧 document revision 写入 | 拒绝过期修改，不覆盖当前文档 | lifecycle.test / lifecycle-e2e |
| LC-11 | 撤回 Agent 协作权限后编辑 | 拒绝新贡献，保留已有协作历史 | lifecycle.test / lifecycle-e2e |
| LC-12 | 导出已编辑 SmartDoc | 真实原生 profile/objectId/docState，可由同一引擎重新打开 | lifecycle.test / lifecycle-e2e |
| LC-13 | 发布材料并运行节点 | Temporal 固定已发布 native bytes，归档不可变 SmartDoc 产物 | lifecycle-e2e / 浏览器 |
| LC-14 | 编辑已用于运行的文档 | 新修订为草稿，旧输入/产物保留，受影响结果过期 | lifecycle.test |
| LC-15 | 创建子文档和引用已有文档 | 父文档中有原生链接，访问仍检查项目权限 | lifecycle.test / 浏览器 |
| LC-16 | 子需求创建过程中总文档达到限额 | PostgreSQL 同一事务回滚，不留下孤儿需求 | lifecycle-e2e 故障注入 |
| LC-17 | 配置未受信仓库或带凭据的 GitLab origin | 网络请求前拒绝，不泄漏后端 token | repository.test |
| LC-18 | 实际 MR 回执分支/URL/SHA 不匹配 | 拒绝；仅接受绑定仓库、源/目标分支与真实合并 SHA | repository.test |
| LC-19 | 文档草稿中输入未保存时收到远端刷新 | 保留输入，提示修订变化，发布不能丢弃未保存内容 | 浏览器与冲突用例 |
| LC-20 | 原上架任务整理为版本和六子需求 | 原项目仍 v695、50 节点、原 Run/Attempt/产物不改写 | migrate-mobile-lifecycle |
| LC-21 | Desktop/Web 及窄屏查看主/子画布 | 主流程不混排，手机为 Step 分组列表，文档及归档可用 | 浏览器截图 / Host 验证 |

MR 模拟 API 响应只验证 adapter 合同，不构成真实仓库已经提审或合并的证据。真实渠道上架和完整云端实时协同没有在本用例集伪造通过。
