# Muse-CI：Desktop DSH 与 Mobile 联调

最新 0.3.0 已完成完整原生编辑器、国内云端委托协作、真实 MR 和重启恢复；参见[最新验收及边界](10-REAL-COLLABORATION-AND-MR-ACCEPTANCE.zh-CN.md)。下文保留首次接入时的工具数量、构建号及历史故障记录。

## 实现边界

- Host 新增通用远端 MCP App 会话、已安装 App 的 Agent 路由和右侧面板入口；没有新增 CI 项目、节点、流水线、Temporal 或发布业务代码。
- Desktop、Android、iOS 共用 `openmuse_mcp_app_runtime`。本次实际设备为 macOS 与已授权的 Android PKM110；iOS 未连接，不计入通过。
- 插件自己的 UI、14 项业务工具及后端继续在 Muse-CI 插件与执行后端中。
- 当前安装为显式开发者绑定，仅 debug Host 加载。生产市场审核、OAuth 登录刷新和正式 Mobile 安装策略仍需独立交付；没有放开生产固定包策略。

## 入口与连接

Desktop 工具栏可打开已安装的 Muse-CI，或在 DSH 中要求发现、打开插件。App 面板显示在当前 Agent 右侧，已有文档绑定保留，重复打开聚焦同一面板。

Mobile 首页出现插件入口，也可从插件卡片打开同一 MCP Apps 界面。手机 CI 后端本次通过 `adb reverse tcp:4180 tcp:4180` 访问本机服务；国内认证、设备目录、Desktop 配对及原生 DSH 使用 `cn.openmuseai.com`，没有替换为海外服务。USB 连接不是远程生产部署。

Agent 通用入口：`apps_list`、`apps_open`、`apps_tools_list`、`apps_call_tool`。CI 工具先发现 Schema，再调用；Host 不解析业务字段。每次业务写入仍受后端权限、commandId 幂等键与版本校验约束。

## 凭据与生命周期

开发安装声明固定 MCP URL、UI URI 和 UI SHA-256。Host 在原生安全存储中保存凭据，校验远端 UI 与已审阅的本地包一致；HTML、工具参数、URL 与产物不携带后端 token。首次导入后删除一次性私有凭据文件。

会话绑定当前账号。账号切换撤销旧连接与 View，异步结果再次检查作用域与会话代次。只转发已发现且对调用方可见的工具；已有文件资源的 active-document 限制保持独立。

## 已取得的真实证据

证据目录：`docs/evidence/desktop-mobile-e2e/`。

- Desktop 真实 DSH，模型 `deepseek-v4.1-flash`，已完成插件发现、14 个工具发现、右侧打开及查询。
- DSH 创建独立项目 `2af62cf846fe3f1a63b55a5dfb705acc`，没有修改 Mobile 1.0.2 整改项目。
- Run `054315ca-b540-4444-b9b9-10633c28de44`：`product-spec` 与 `ui-spec` 成功。
- Run `303d51f3-4b14-4a9b-887f-8a4488ed5b97`：`product-spec` 重跑成功，生成 attempt 2；真实工具及原生界面均已读取 `product-spec.md`。
- Android 真机已通过国内账号登录与 Keystore 保存、完整 Host 插件入口、原生 WebView 挂载、UI 经原生 MCP bridge 调用 `ci_capabilities` / `ci_projects_list` / `ci_project_get`、国内目录发现和同账号 Desktop 配对。
- 用户授权并完成系统权限验证后，已恢复 Mac 网络时间自动同步。原先约 13 小时的时差会使 Desktop 签发的授权到国内 Relay 时立即过期；纠正后原生 Mobile DSH 经国内 Relay 连接成功。没有修改国内服务器时间或降低授权校验。
- Mobile 真实 DSH 会话 `session-6669191e-6845-4d67-9681-a8e279e2fe6a` 保存计划，保留 title/type/budget，在 goal 追加独立验收标记，然后经 `apps_call_tool` 发出 `ci_run_command(action:start,nodeIds:[product-spec],auto:false)`。
- Run `da2e0b81-3d8f-45a1-a57c-96ae18fdb712` 成功，`product-spec` attempt 4 成功，项目版本 26。新的 `product-spec.md` SHA-256 为 `bff73c2c598b4f32faf82e4961b27282330908216c106295bd3653e9a8ae2bf1`。后端独立读取确认，不以模型回复作为写成功的唯一依据。
- Desktop 右侧 CI 已同步显示 Mobile 发起的 attempt 4。上架整改项目 `db29cc8e05c2609607efac6224b8ea30` 仍为版本 695；本轮没有代批发布决定。

本次真实 AI 执行器是 DSH 中的 `deepseek-v4.1-flash`，负责发现 Schema、查询和执行 CI 操作。验收项目的产品/UI 节点使用 `doc-compile` 编译明确版本的工程材料，不把确定性编译描述为 AI 编写代码。整改流水线的代码改造、版权结论和正式渠道发布也不因本轮接入测试而自动完成。

## 验收结果与画面

2026-11-19（上海时间）Android 真机测试通过，12 个联调里程碑均有记录。测试覆盖原生页面操作、逐次 AI 发送确认、国内账号和配对、MCP Apps WebView bridge、实际模型工具调用、计划写入和新尝试产物。

- [真机通过记录](evidence/desktop-mobile-e2e/mobile-acceptance-results.json)
- [会话、版本与尝试回执](evidence/desktop-mobile-e2e/mobile-ci-host-e2e.json)
- [跨端后端回执](evidence/desktop-mobile-e2e/cross-device-backend-receipts.json)
- [测试摘要](evidence/desktop-mobile-e2e/mobile-test-summary.txt)

![Desktop DSH 及右侧 CI，同步显示 attempt 4](evidence/desktop-mobile-e2e/desktop-dsh-ci.png)

![手机原生 DSH 完成 CI 重跑](evidence/desktop-mobile-e2e/mobile-native-dsh.png)

![手机 AI 接收方及本次发送范围确认](evidence/desktop-mobile-e2e/mobile-ai-consent.png)

## 使用和交付状态

- Desktop 当前打开的开发构建位于 `Muse-Client/app/openmuse_host/build/macos/Build/Products/Debug/OpenMuse.app`，CI 在 DSH 右侧。系统原有 `/Applications/OpenMuse.app` 未替换。
- Android QA 包为 `com.openmuseai.mobile.acceptance`。测试后恢复普通 `lib/main.dart` 入口的 **1.0.2+111810**，保留国内账号安全存储和插件绑定；主应用包未修改。普通入口仍执行真实首次协议检查，不由测试伪造同意记录。用户回复确认后，普通入口已进入首页，首次协议页不再阻挡。随后用户报告“插件连接失败”；实际检查发现 USB `reverse` 映射已丢失，而 Mac 后端正常。恢复映射后，新增完整普通入口冷启动回归已通过：调用真实 `main()`，恢复已有国内地区/协议记录和 Keystore 会话，不使用登录 fixture，再实际点击插件入口、加载 WebView 并经原生 bridge 查询后端。普通入口 APK 留存于 `Muse-Client/target/qa/OpenMuseQA-muse-ci-cn-1.0.2+111810.apk`，SHA-256 为 `2125effd376ff717ad361943c9ce5d1f57d7ab7a0f1306b85d53bedc83ae93f2`。
- 打开首页的 Muse-CI 进入流程界面；右上连接入口切换后端项目。在 DSH 中可要求“发现 Muse-CI 工具并查询指定项目”，以项目 ID 限定操作范围。
- 当前 CI 后端仍是本机 4180，经 USB reverse 接入手机；脱离这台 Mac 的独立远程访问、生产 OAuth 与市场安装尚未交付。国内账号、设备目录与 Relay 已真实验证，不能将它等同于 CI 后端已部署到国内公网。
- iOS 共享实现已接入，但未连接 iOS 真机，本次没有 iOS 实机通过结论。

## 普通入口连接失败的复查与修复

2026-11-19 补充验证：本机 CI 后端可用，手机的 USB reverse 表为空。开发配置使用手机回环地址，因此 USB 重连或 adb 重启后丢失这条映射会导致“插件连接失败”。后端鉴权、已审阅 UI 摘要与账号绑定均通过独立复查；没有重新导入 token 或放宽账号校验。

- 新增 `ci_normal_entry_live_test.dart`，从实际 `main()` 而非内部 boot 函数启动；6 个检查通过，并再次通过 `--restore-normal` 验证恢复为 1.0.2+111810 的日常 QA；[恢复回执](evidence/desktop-mobile-e2e/mobile-normal-restoration.json)。复用已保存的协议和国内账号，未重新登录或伪造协议记录。
- `mobile-host-e2e.mjs --normal-entry --restore-normal` 会运行上述回归，并在 finally 中清理测试凭据/独立调试端口、恢复普通入口 QA（构建号递增）、重建 USB bridge 和重新启动。直接 `adb install -r`，仍无卸载回退。
- 新增 `Muse-CI/scripts/mobile-host-bridge.mjs` 开发连接监控，只绑定启动时选定的授权手机，只维护 `4180 → 4180` 这一条映射。USB 重连后补回，不开放公网、不写入账号/后端 token、不影响其他转发。
- 实际移除该映射后，监控在 **2972 ms** 内自动恢复；[故障恢复记录](evidence/desktop-mobile-e2e/mobile-bridge-recovery.json)。
- [普通入口通过记录](evidence/desktop-mobile-e2e/mobile-normal-entry-results.json)、[6 项检查与 UI 工具回执](evidence/desktop-mobile-e2e/mobile-normal-entry-e2e.json)、[摘要](evidence/desktop-mobile-e2e/mobile-normal-entry-summary.txt)。

![普通 main 启动并打开真实 CI 页面](evidence/desktop-mobile-e2e/mobile-normal-ci.png)

开发连接监控当前已启动。重新开始本地联调时，在后端运行的前提下执行：

```sh
cd /Users/mac/src/openmuse-io/Muse-CI
node scripts/mobile-host-bridge.mjs
# 另一个终端：普通启动回归，并自动恢复日常 QA
node scripts/mobile-host-e2e.mjs --normal-entry --restore-normal
```

这仍是 USB 本地开发连接。拔掉 USB 期间不能访问该后端；要脱离 Mac 独立使用，需要交付带 HTTPS/鉴权的国内远端 CI 后端，不能靠这条开发转发实现。

## 验证工具

`Muse-CI/scripts/mobile-host-e2e.mjs` 使用不低于已安装版本的构建号构建 APK，安装前检查版本，直接 `adb install -r`，没有自动卸载回退。测试读取 App 私有的一次性账号文件，结束后清理；账号不编译到 APK。

OPPO 调试日志不可用时，Android debug Application 将带原有鉴权 nonce 的 VM service URI 写到 App 私有文件，USB 测试经授权 `run-as` 读取。正式源码集合不含此 Application，不关闭调试服务鉴权。

测试错误：第一次直接使用 `flutter test` 时，默认构建号 9 低于 QA 的 111801，Flutter 自动卸载 QA，造成 QA 本地数据清除。主应用包未被操作。后续恢复开发绑定，并改用以上禁止自动卸载的入口。

已通过连接层测试 5 项、Desktop 路由和面板测试 4 项、Mobile 组合与隐私回归 17 项。最终签名包、生产插件安装和 iOS 真机不属于本次已通过的证据。


首次登录可能弹出“绑定 Desktop”引导；验收通过真实点击其遮罩关闭后再进入插件，随后核对指定设备并建立连接。此前等待首页按钮可点击而超时，是没有处理该引导，未通过调用按钮回调绕过页面。

```sh
cd /Users/mac/src/openmuse-io/Muse-CI
node scripts/mobile-host-e2e.mjs --restore-normal
```

`CI_NATIVE_CAPTURE=1` 开启人工截图检查点（每个最多 45 秒）；无截图模式仍运行全部业务断言。`--skip-build --skip-install` 仅用于已安装的同版本测试 APK，不应对普通 QA 包使用。测试入口结束后应恢复普通入口 APK，不能把测试结束后的最后一帧当作可用 App。

本轮 Host 代码已按通用 runtime、Desktop 集成、Mobile 集成、真机断言分别提交：`71239193`、`5eca85a0`、`739ffbed`、`780c988a`。普通入口冷启动回归另提交为 `bf059535`。未推送或发布。
