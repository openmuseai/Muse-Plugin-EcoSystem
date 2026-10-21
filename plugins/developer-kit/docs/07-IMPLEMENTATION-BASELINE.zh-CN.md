# Desktop DevKit 开发基线

日期：2026-10-21。按要求先保存既有工作区，再切换分支。此记录不代表 DevKit 功能已经实现或端到端验收通过。

## 仓库与分支

| 仓库 | 原分支 | 保存后的基线 | 开发分支 |
| --- | --- | --- | --- |
| Muse-Client | `feat/standard-plugin-market` | `9ab9ecb` | `feat/plugin-devkit-desktop` |
| Muse-Plugin-Ecosystem | `feat/standard-plugin-market` | `7567617` | `feat/plugin-devkit-desktop` |

Client 的既有改动拆为 15 个提交，涵盖帐号授权失效、Mobile 插件运行时、示例包、Desktop 市场、Mobile 市场、注册与生命周期、工作台布局、PPTX 迁移探针、跨端测试、依赖锁、构建脚本、验收文档、README 和样例媒体。生态仓库拆为 3 个提交，涵盖 vendor 忽略、编辑器本地文件接入和 0.1.5 打包说明。作者与提交者均为 Alexixixi。

官网 `Muse-WebSite` 和旧客户端的独立改动保持原状，没有纳入此次提交或切换分支。既有 PPTX 原生 Flutter 测试探针按原样保存；它不代表现行 React/Konva 管线已经替换为 Flutter。

## 本次实际执行的验证

下表是提交前的测试基线，不沿用历史验收结论。Flutter 命令均使用 `--no-pub --reporter compact`。

| 目录 | 命令 / 范围 | 结果 |
| --- | --- | --- |
| `plugins/appflowy-editor` | `npm run build`、`npm run build:http`；临时启动端口 18789 的测试 HTTP 服务后 `npm test` | 构建成功；2 通过。服务随后停止。 |
| `packages/openmuse_mobile_plugin_runtime` | `flutter test` | 7 通过。 |
| `plugins/workspace-paired` | `flutter test` | 25 通过。 |
| `app/openmuse_host` | `flutter test test/workbench_shell_test.dart test/plugin_market_ui_e2e_test.dart` | 19 通过，2 跳过；没有执行真实 DSH 安装验收。 |
| `plugins/plugin-market` | `flutter test` | 2 通过，2 失败。 |
| `app/openmuse_mobile` | `flutter test test/mobile_app_test.dart test/mobile_market_media_test.dart test/mobile_workbench_page_test.dart test/workbuddy_shell_test.dart` | 35 通过，2 失败。 |
| `plugins/mobile-plugin-market` | `flutter test test/offline_mcp_install_test.dart test/online_catalog_surface_test.dart` | 2 通过。 |
| `tests/plugin-platform-e2e` | `flutter test` | 1 通过；使用真实领域服务和配对 HTTP 网关，DSH HTTP 为测试替身。 |

两仓库的 `git diff --check` 通过；待提交文本的凭据模式扫描未发现匹配。此次没有重新构建完整应用、操作用户设备或向生产市场发布。

## 已知失败项与后续门禁

1. Desktop 市场 `plugin_market_test.dart` 两项用例均在 `pumpAndSettle` 超时（原第 61、128 行）。界面布局测试通过，但不能据此认定整个市场测试套件通过；后续需检查测试 Host 返回值和市场加载状态，定位后修复。
2. Mobile `mobile_app_test.dart` 的两项 PPTX 用例仍断言 `GenOfficePptxViewer`。当前页面没有该组件，导致断言失败（原第 353、403 行）；需按实际发布的插件与渲染管线核对覆盖范围，不应为满足旧测试把 PPTX 业务重新放进 Host。
3. `native_pptx_registry_test.dart` 是保留的历史迁移探针，依赖在线 Registry 并固定断言 0.3.1。本次未把它作为当前 0.5.0 的安装验收；后续应使用明确版本的隔离目录或重写版本选择断言。
4. DevKit 尚无可运行发行包。后续验收必须实际覆盖安装 DevKit、同时选择 PPTX/PDF、独立项目初始化、应用内编码与调试、打包上传并进入待审状态；领域测试和测试替身不能代替完整应用验收。

实现继续遵循 [技术方案](03-ARCHITECTURE.zh-CN.md)、[公开合同与 SDK](04-CONTRACTS-AND-SDK.zh-CN.md) 和 [开发计划](05-DEVELOPMENT-PLAN.zh-CN.md)：Host 只处理通用协议和权限；开发编排、PPTX、PDF 业务分别留在各插件内。
