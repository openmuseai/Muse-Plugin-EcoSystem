# Muse-CI 0.3：原生文档协作、DSH 与真实 MR 验收

2026-11-19，基于已安装的 Desktop「OpenMuse CI QA」与 Android PKM110 普通 QA 入口验证。国内认证、工作区、Document0/full-sync 与 WS2 使用 `cn.openmuseai.com`。插件界面不承载云端 token，Host 继续只提供通用 MCP 与资源路由；CI 业务留在插件/后端。

## 产品与交互交付

沿用 [生命周期规范](07-LIFECYCLE-AND-SMARTDOC.zh-CN.md)：版本包含需求子流程；Step 横向有序，节点在 Step 内按依赖运行，人工标过与执行成功分开。总文档、Step 材料、测试用例/报告、Attempt 产物按稳定文档 ID 归档，历史修订保留。

- 文档面板增加「完整 SmartDoc 编辑器」，通过标准 MCP Apps `ui/open-link` 和账号绑定的 `openmuse.resource-reference/v1` 打开原生资源。Host 校验账号；文档插件继续校验资源权限。
- 使用现有完整 SmartDocument 编辑器、原始 Yrs 文档与现有云服务，不另建协作文档格式或同步数据库。人和 CI Agent 的修改共同进入同一云文档。
- CI Agent 使用项目成员明确委托身份。CI 修订记录显示 Agent 与委托人；云端成员仍是该真实成员，不能把「1 人」展示称为两个独立云端账号。
- 原生子文档连接按父子顺序创建，保留云端实际父页面 ID。已有流程内引用在目标连接后升级为原生账号绑定链接，保留文字、富文本属性、块 ID 与历史；已存在的云页面不擅自移动。跨流程的未连接引用仍由 CI 文档面板解析。
- MR 支持实际创建草稿、提审、合并和状态核验。待完成检查保留操作并自动重试；失败检查阻止合并。重启恢复、并发租约、取消、源提交变化和权限撤回均有测试。平台回执归档为节点证据，人工标过不能替代平台合并。

## 真实用例与证据

| 编号 | 操作与预期 | 结果与证据 |
| --- | --- | --- |
| AUTH-01 | 本地授权账号在原生国内 GoTrue 登录、工作区读取 | 通过；[认证记录](evidence/live-e2e/cn-login-verification-2026-11-19.json) |
| AUTH-02 | QA 凭据安全存储、消费一次性插件导入，冷重启自动恢复 | Desktop 实际界面通过；无需再次登录/重新导入 token |
| DSH-01 | 真实 DSH 模型发现已安装插件，仅在指定验收流程查询、标过、撤回、单节点运行、读取产物/事件 | 通过；[后端独立核验](evidence/live-e2e/desktop-dsh-ci-2026-11-19.json)、[会话与右侧画布](evidence/live-e2e/desktop-dsh-ci-live.jpg) |
| SD-01 | Desktop 完整编辑器读取手机/Agent 内容，编辑进入云端，Agent 回读后实时回复 | 通过；[Agent 回执](evidence/live-e2e/desktop-agent-cloud-2026-11-19.json)、[原生编辑器](evidence/live-e2e/desktop-native-smartdoc-live.jpg) |
| SD-02 | 手机普通 Host 入口 → 已安装 CI → 原生 SmartDoc → 读取 Desktop 修订 → 富文本写入云端 → Agent 回读/实时回复 | 真机通过 18 项；[套件](evidence/live-e2e/mobile-smartdoc-cross-device-111845-suite.json)、[内容/实时帧回执](evidence/live-e2e/mobile-smartdoc-cross-device-111845.json) |
| SD-03 | 子文档归档、Agent 云端贡献、父文档原生引用与 Desktop 实际点击跳转 | 通过；[原生归档索引](evidence/live-e2e/smartdoc-live-archive/INDEX.json)、[Desktop 子文档](evidence/live-e2e/desktop-native-child-live.jpg) |
| MR-01 | 真实 GitHub MR 草稿 → 提审 → 等待平台检查 → 合并 → 回读 merge SHA | 通过；[MR #1](https://github.com/openmuseai/openmuse/pull/1)、[平台回执](evidence/live-e2e/mr-live-acceptance-2026-11-19.json) |
| ENGINE-01 | 独立数据库 Schema/任务队列：重启、暂停、恢复、重跑、材料固定、审批过期、产物摘要 | 后端端到端 25 项通过；[报告](evidence/live-e2e/report.json) |

DSH-01 的实际 Run：`5a523216-135c-49df-aa5c-5f8ee4e0d318`。只运行 `feature-prd`，产物为原生 `.sydoc`；没有操作整改主项目、后续节点或发布渠道。该节点编译明确发布的原生文档快照；真实模型负责工具编排，不能将快照编译称为 AI 写代码。

MR-01 在专用验收源/目标分支完成：`codex/ci-acceptance-52d61ac2-head` → `codex/ci-acceptance-52d61ac2-base`。merge SHA 为 `75307d554274156ea07cb7dee2c75c87492cf355`。实际平台检查发现 macOS 14 runner 已停用后，在该独立分支将两处 runner 更新为 macOS 15，保留原检查脚本，全部检查通过后再合并。此 MR 验证了完整平台操作链，**没有把当前工作区所有产品代码或正式版本合并进主分支**。

## 登录与签名问题的结论

本地 `.account` 不是严格 JSON，邮箱与密码之间有注释。原先按相邻行取值会把注释当密码。现改为仅在账号数组中解析，跳过字符串外注释，保留密码转义；不会误取后面的 GitHub token。另将网关/HTML 错误与明确的密码拒绝分开。未修改账号密码。

独立 QA 的 bundle ID 是 `com.openmuseai.office.ciqa`，原有正式 profile 只覆盖 `com.openmuseai.office`，导致 Keychain `-34018`。Xcode 登录后，为已注册的本机取得团队 Development profile，沿用现有团队和 Xcode 选中的开发证书，QA 签名的 Keychain 权限限定到 QA 自身身份。没有替换正式 App 的证书、bundle ID 或正式发行 profile。

原生网络恢复仅在已安装国内服务域名系统 DNS 失败时使用可信 DNS 查询，HTTPS 保留原 hostname/SNI 与默认凭证校验。WS 使用独立受限连接生命周期；原生编辑器不再等待一次握手才能显示。测试默认不运行预热诊断 socket。

## 验证与原生材料

后端 56 项单元/回归测试与 TypeScript 类型检查通过；插件 22 项测试与 MCPB 打包通过。Host 的账号绑定链接、远端 App、原生实时连接、DNS/TLS 与实际包安装 conformance 已验证。手机的同步断言等待当前 mutation epoch 被接受，并由 Agent 从云端回读，不能用一次较早 HTTP 请求的完成替代当前写入确认。

[原生材料索引](evidence/live-e2e/smartdoc-live-archive/INDEX.json) 记录父/子文档 ID、账号绑定定位和相对 `.sydoc` 文件路径。这些是只读时间点导出；在线文档与云端版本仍是协作入口。私有 `.data` 配置、安全存储及 `.account` 不进入证据目录、插件包或提交。

## 当前交付边界

- 当前是实际安装的独立 QA App 与已审阅的开发者插件绑定，包含普通启动与冷重启验证；不是仅浏览器预览，也不是已上架/公证的生产安装。
- CI 后端仍在本机 `4180`，手机通过指定设备 USB reverse 连接。生产国内 HTTPS 部署、OAuth 多用户后端鉴权、正式插件市场安装与脱离 Mac 独立使用尚未交付；没有放宽正式 Mobile 固定包策略。
- OpenMuse 服务使用国内端点；实际 DSH 复用同一账号原有 `deepseek-v4.1-flash` 配置，网关为 `opencode.ai`。本次只发送专用公开验收数据。若要求 AI 推理也完全走国内端点，还需单独配置可用的国内模型凭据。
- iOS 未连接真机，本次不计入实机通过。正式 App 1.0.2 的版权/隐私整改与四渠道上架仍须各自的签名产物、版权结论和平台回执。
- GitHub token 曾由用户粘贴到聊天；验收使用本机私有凭据文件，建议后续轮换。没有将其写入 Git、HTML、归档或链接。
- Host/插件改动按粒度提交，其他并行工作保持在工作区。`Muse-CI` 后端目录当前没有 Git 元数据，代码已落盘；不能把后端源码宣称为已提交或已合并。
