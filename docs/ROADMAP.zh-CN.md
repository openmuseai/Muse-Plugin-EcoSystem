# 实施路线图与决策门槛

状态：评审草案（2026-10-15）。工期是按一个平台小组并行推进的粗估，依赖现有 Host 安装与 Mobile/Web 门禁；不是完成承诺。

## 阶段与验收

| 阶段 | 预计 | 交付 | 退出门槛 |
| --- | --- | --- | --- |
| E0 合同与体验原型 | 2–3 周 | 三端插件类型与权限矩阵、跨端同 ID/分平台版本模型、Manifest 扩展 RFC、手机 Agent 工坊与安装/提交流程原型、TCK fixtures | 同一 fixture 在 Rust/Dart/Web 判定一致；明确 iOS/Android 发行范围与受限 profile。 |
| E1 开发者内环 | 3–5 周 | CLI、模板、Mock Host、文档、Desktop/Mobile/Web 最小样例和本地 TCK；`MiniPluginSpec` 与 `forms@1` Profile 纵向切片 | 外部开发者无需修改 Host 就能创建、验证、打包；普通用户在手机上描述一个表单助手并完成真实预览/试填。 |
| E2 安全分发基础 | 4–6 周 | 上传隔离、扫描 Worker、人工审核、签名目录、CDN、密钥轮换/撤回、开发者门户；手机草稿/私有发布 API | 篡改、旧快照、过期、错误 target、权限 diff、坏包、错误签名均 fail closed；审核与签名分权；用户可从手机安装自己的版本。 |
| E3 Desktop 公开 beta | 4–6 周 | Host 单一安装服务、事务 journal、声明式/WebView/worker 分型装载、市场 UI 接入 | macOS/Windows 实包安装、更新、崩溃恢复、禁用和回滚通过；分别证明可热启停与可热替换代码的边界；DSH 依赖不做半安装。 |
| E4 Mobile 受控 beta | 4–6 周 | A2UI/WebView profile、QuickJS 能力 Broker、签名目录迁移、Android/iOS 设备矩阵 | 真实商店渠道政策与实机门禁通过；UI/动作越权、弱网和失败恢复可复现。未过门禁的平台不上架。 |
| E5 Web 与生态开放 | 4–8 周 | 隔离 Web 扩展点、浏览器 TCK、公开提交、举报/撤回、开发者指标 | 插件 JS 不能读取宿主特权会话；Cloud/Paired grant 撤销及时生效；公开审核流程可运营。 |

E1/E2 可部分并行，E3/E4/E5 的客户端门禁需分别验收。若 2 名客户端、2 名后端/平台、1 名安全/测试和共享设计/运营投入，首个可对外的 Desktop + 开发者门户 beta 粗估 3–5 个月；Mobile/Web 生态开放另按政策审核、浏览器隔离 PoC 和实际 TCK 结果重估。不要把阶段工期简单相加或把现有演示运行时算作 E4 已完成。

## 必须先决定的四件事

1. **源码托管范围**：建议本仓库只托管官方维护的非内置插件、模板与合同；社区开发者保留自己的源码仓库，向服务提交不可变 artifact。这样避免把“能上传插件”误解成必须给所有人写 Git 权限。
2. **首发渠道**：建议 Desktop macOS/Windows 公开 beta，Android 先精选，iOS 完成 4.7 审查后再开放外部代码 profile；Web 先声明式 Surface。
3. **外部代码权限级别**：首期按低权限与高权限两级审核；高权限（执行、Secret、文件写入、跨设备）不能仅靠自动审核发布。
4. **商业化**：首期免费；支付、分成、退款、税务、App Store/Play 数字商品规则另立项，不预埋收费假流程。

## 下一轮具体工作单

1. 在 `Muse-Client` 固定 Manifest v2/SDK 当前提交，补出三端 compatibility 和权限的跨语言 TCK；定义同 ID 分平台版本与 `MiniPluginSpec/forms@1`，确定新仓库同步方式。
2. 从当前 Desktop `plugin_package.dart`、Mobile `SignedHttpMobileMarketSource` 和 Web remote surface 各取一个真实纵向样例，记录差距，不绕过签名和权限。
3. 并行做手机 Agent 工坊的“描述 → 预览 → 试填 → 私有安装”纵向切片，以及 `openmuse-plugin init/validate/test/pack` 和三端模板；分别让普通用户与非 Host 开发者验证。
4. 实现最小 Store API、隔离上传、审核与签名目录；用一个官方非内置插件完成从源码提交到三端目录展示的闭环。
5. 补 Desktop Host 事务与权限 Broker，再放开安装；Mobile/Web 分平台通过政策、沙箱和设备矩阵后逐步开放。

## 发布前必测故障

同名抢占、同版本内容改写、恶意压缩包、越权 WebView 消息、A2UI 组件/消息超限、QuickJS 死循环/内存耗尽、错误 ABI、签名密钥轮换、目录回滚、依赖循环、DSH profile 冲突、安装中断、健康检查失败、灰度暂停、撤回后的离线启动、Cloud/Paired grant 撤销、iOS/Android 商店渠道差异。每项要有自动化反例与用户可理解的修复状态。
