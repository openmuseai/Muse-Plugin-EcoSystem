# Word 产品持续迭代与联合验证

## 目标和当前边界

Word 产品由三个源码仓库形成一条交付链：`ioffice` 的 `word-core`、FRB 运输层及 Flutter `word_render`/`word_editor`；`Muse-Client` 的 Host 与安装器；本仓的签名 Word 产品资源及低频扩展。插件包不携带文档模型、排版代码或编辑画布。Desktop 使用原生 Rust，Mobile 内核随 Host，Web 使用 Rust WASM；Flutter 编辑表面编译进各端 Host。

本仓已经提供联合构建入口、版本策略和报告格式。首版 Desktop `--scope render` 已接入 Host：从签名 MCPB 读取产品资源，注册原生 DOCX 编辑器，并启动 OpenMuse macOS 应用打开、渲染样本文档。Android Host 也已接入随包的 Rust 内核、Flutter 编辑表面和签名产品资源，并在真机完成手动只读渲染验证。完整编辑 `--scope edit` 仍受 DOCX 保存与内核保真测试阻塞；Android 自动化联合钩子、iOS 和 Web 钩子尚未完成。

## 版本与兼容性

[`../stack/compatibility.json`](../stack/compatibility.json) 是联合测试政策，固定合同主版本、组件最低版本、源码路径和各端必测场景。实际组件版本从各自 `Cargo.toml`、`pubspec.yaml`、`package.json` 读取，不在本仓复制 `word-core` 或 Flutter 代码。一次运行的 `report.json` 记录各仓（包括 `word-core` 的本地路径依赖 `ioffice/libs/core-libs`）HEAD、脏状态、源码指纹、组件版本、插件包 SHA-256、原生内核 SHA-256、命令日志和 E2E 证明。开发态允许脏树以便验证正在改写的代码；正式发布要求全部仓库 clean 且签名密钥显式提供。发布后将报告和各平台产物摘要归档为不可改的发行记录。

| 变更 | 版本动作 | 必测门禁 |
| --- | --- | --- |
| `word-core` 内部修复、保真或性能变化 | Rust patch；若更改公开编辑语义或 FFI，连同 FFI 版本递增 | 内核金文件、FRB、Flutter 样例、全部目标端 E2E；性能基线对比 |
| Rust FFI/Flutter 编辑表面新增兼容能力 | 各自 minor；更新能力协商和 `compatibility.json` | 旧插件包和新包分别在新 Host 上安装；输入法、选区、保存重开 |
| 公开命令/编辑表面不兼容变化 | 提升 `wordApiMajor` 或 `editorSurfaceMajor`；旧接口留过渡期 | 不兼容包拒绝安装；并行维护旧稳定线；迁移/回滚 |
| Ribbon、快捷键、模板、字体或开关变化 | 插件 patch/minor；重新签名 | 资源校验、签名篡改、Host 安装、离线启动和受影响功能 |
| 扩展服务合同变化 | 扩展自身版本递增；破坏性变更用新操作 ID | 请求/响应合同、预算、错误码和多端禁用策略 |
| 仅测试计划变化 | 递增政策修订，更新本文件和验收用例 | 联合计划重新运行；历史报告保留原政策摘要 |

版本数字表示兼容意图，能力集合表示真实功能。Host 先比较 Profile 主版本，再读取运行时能力，最后应用签名包的功能开关；不能因为版本够新就自动宣称保存、协作或字数扩展可用。在线协作的同步协议和会话修订由 `ioffice`/Host 持有，插件只可声明协作入口与低频命令。离线编辑和在线协作使用同一文档模型；协作不可用时仍应完成离线打开、编辑、保存、重开。

## 开发循环与一键入口

在三仓并列的工作区根目录，先安装本仓 Node 依赖及 Flutter/Rust/平台工具链。在 `Muse-Plugin-Ecosystem` 执行：

```sh
npm run word:plan -- --platform desktop
npm run word:build -- --platform desktop --scope render --suite quick
npm run word:e2e -- --platform desktop --scope render --suite quick
```

`--platform` 接受 `desktop|android|ios|web|all`，`all` 需要 macOS；`--suite full` 跑全部 Flutter 样例测试。`--scope render` 是首版只读预览门禁，目前仅支持 Desktop；默认 `--scope edit` 是完整编辑门禁。`word:plan` 不编译，显示检测到的版本与命令。`word:build` 用一次性开发密钥签名包并验签，运行所选门禁的插件、内核、FFI 与 Flutter 测试，再编译 Host；其成功状态是 `build-passed-not-e2e`。`word:e2e --scope render` 还须证明签名安装、能力路由、DOCX 打开渲染、离线重开以及 OpenMuse 原生进程启动。完整编辑门禁未来还要求保存、升级和回滚证据。每次运行输出 `.word-stack-runs/<run-id>/report.json` 与分阶段日志；失败也保留报告。Dev 公钥写入该报告目录，私钥只在临时目录使用后删除。

联合计划单独运行 `word_editor` 产品壳组件测试，检查标签切换、禁用控件无副作用和命令分发。G2/G3 阶段继续将壳层截图对比、菜单与上下文标签测试加入同一报告。

日常提交路径：改动组件源码或测试计划 → 更新相关组件版本及合同/能力矩阵 → `word:plan` → `word:e2e --platform <affected>` → 评审报告和视觉/性能差异 → 合并。每个合并到集成线运行 quick Desktop；涉及 Rust/Flutter/资源合同的合并运行受影响平台；夜间或候选版运行 `--platform all --suite full` 并在真机/浏览器矩阵补齐离线验证。若某平台当前无运行设备或钩子，报告为阻塞，不能声称该平台已验收。CI 可直接调用同一 npm 命令；CI 工作区必须按本地三仓并列布局检出所选修订，不能依赖本仓构建时自动拉取任意分支。

## Host E2E 钩子合同

Desktop 钩子已在 `Muse-Client/scripts/word-product-e2e-desktop.sh` 实现，会将本次 Rust 动态库装入 OpenMuse.app、重新签名、执行安装与 Flutter 渲染测试，再启动完整原生应用检查 Word 渲染与 DSH WebView 就绪信号。人工可用 `Muse-Client/scripts/launch_word_preview_macos.sh` 重新打开同一隔离安装。Release 包由 `Muse-Client/scripts/package_macos.sh` 生成；指定 `OPENMUSE_WORD_CORE_FFI` 和 `OPENMUSE_WORD_CORE_FFI_X86_64` 时会把两个 Rust 切片合成并签入通用 macOS 应用。Android、iOS、Web 钩子待实现，届时必须真正启动对应 Host/设备或浏览器。编排器传入 `WORD_STACK_BUNDLE`、`WORD_STACK_PUBLIC_KEY`、`WORD_STACK_KEY_ID`、`WORD_STACK_RUN_REPORT`、`WORD_STACK_E2E_RESULT_PATH`，以及 `WORD_STACK_BUNDLE_SHA256`、`WORD_STACK_CORE_SOURCE_DIGEST`、`WORD_STACK_CORE_LIBS_SOURCE_DIGEST`、`WORD_STACK_EDITOR_SOURCE_DIGEST`、`WORD_STACK_ENGINE_SOURCE_DIGEST`、`WORD_STACK_HOST_SOURCE_DIGEST`、`WORD_STACK_NATIVE_ENGINE_SHA256`。`WORD_CORE_FFI` 指向刚构建的本机 FRB 动态库，供样例和 Desktop 测试显式加载。Mobile/Web 钩子要报告设备上实际加载的原生库或 WASM 文件，不能把构建机的动态库冒充目标引擎。

每个钩子在 `WORD_STACK_E2E_RESULT_PATH` 写 JSON，形如：

```json
{
  "profile": "openmuse-word-stack-e2e/1",
  "target": "desktop",
  "bundleSha256": "<WORD_STACK_BUNDLE_SHA256>",
  "coreSourceDigest": "<WORD_STACK_CORE_SOURCE_DIGEST>",
  "coreLibsSourceDigest": "<WORD_STACK_CORE_LIBS_SOURCE_DIGEST>",
  "editorSourceDigest": "<WORD_STACK_EDITOR_SOURCE_DIGEST>",
  "engineSourceDigest": "<WORD_STACK_ENGINE_SOURCE_DIGEST>",
  "hostSourceDigest": "<WORD_STACK_HOST_SOURCE_DIGEST>",
  "hostArtifact": {"path": "/absolute/path/to/host-binary", "sha256": "<sha256>"},
  "engineArtifact": {"path": "/absolute/path/to/loaded-engine", "sha256": "<sha256>"},
  "cases": {
    "signed-install": {"status": "passed", "evidence": ["/absolute/path/to/install-log.json"]}
  },
  "completedAt": "2026-10-22T00:00:00Z"
}
```

`cases` 必须覆盖所选 scope 的 common 和目标端列表，每例有可读取的证据文件；编排器核对源码、包、产物 SHA-256 和每例状态。Desktop 通过 `sourceNativeEngineSha256` 追溯刚构建的 `WORD_CORE_FFI`，通过 `engineArtifact.sha256` 核对重新签名后装入应用的库。Host 钩子负责证明目标进程实际加载这些产物，并记录 Host/引擎版本、文档输入哈希、自动化追踪、设备信息；完整编辑门禁还需输出文档哈希和性能数据。成功退出但缺少证明同样算失败。对于 Web，钩子必须证明 WASM 缓存后的断网重载；仅 Host Web 页面构建通过不算 Word 可用。在线协作加独立场景：两端同文档修订、断线编辑、重连冲突解决、权限撤销和协作不可用时离线保存；在协作功能正式开放前不把这些列入基础离线编辑门禁。

## 发布与回滚

1. 开发线持续产生签名测试包和联合报告。稳定候选版冻结三仓提交、版本及政策，跑所有目标端 full E2E、保真与性能基线；使用市场测试环境检验原子安装、升级和回滚。没有通过目标端的候选版不得标该端可发布。
2. 发布作业用 `npm run word:e2e -- --platform all --suite full --mode release --private-key ... --public-key ... --key-id ...`。生产私钥由发行环境注入，不能落仓；发布作业要求 clean 源码。将 Host 构建、插件包、各端内核、报告和依赖锁文件的摘要绑定成发行清单。CI 再从该清单推广到 canary 与 stable，推广不重编译。
3. Host 先验证签名、合同、能力和平台后安装到新槽，再切换活动收据；失败保持旧槽。回滚只切换插件资源与可兼容的 Host/内核组合，用户文档单独持久化，文档格式升级需有迁移与备份计划。撤回签名包后阻止新会话，既有文档仍可访问。

首版渲染门禁已跑通 macOS 原生应用，Android Release 也已完成独立包名的真机人工验证。下一步是将 Android 设备安装、打开指定 DOCX、页数和渲染截图写入同一 `word:e2e` 报告，再补齐 M1 的 DOCX 保存、M2 的完整命令/快捷键与功能区配置消费、M3 的生产密钥信任和回滚，以及 iOS/Web 钩子。每完成一个阶段，更新政策中的必测用例与版本下限，持续用同一入口复验。

完整编辑门禁仍被 `word-core` 的 `04_function_stage3_golden` 阻止：`hello` 样例第二个 glyph 的 x 坐标为 1905，金文件期望 1920。`--scope render` 运行更聚焦的 FFI 打开/绘制测试，因此可独立验证首版预览，不能代替排版精度验收。`--suite full` 还要求 DOCX 保真、性能预算和可访问性证据；这些用例尚待完善。
