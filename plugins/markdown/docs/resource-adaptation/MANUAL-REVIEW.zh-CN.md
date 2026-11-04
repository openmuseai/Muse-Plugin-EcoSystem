# 原生编辑器人工验收

> Mobile 后续已修复 Tasks 底部留白。最新 Android / iOS 普通客户端位于 `/Users/mac/src/openmuse-io/Muse-Client/target/manual-acceptance/mobile/2026-11-02-tasks-bottom/`，验证见 [Tasks 修正记录](/Users/mac/src/openmuse-io/Muse-Client/docs/evidence/mobile-tasks-bottom/2026-11-02/README.zh-CN.md)。下方统一目录保留本轮插件适配基线。

2026-11-02。本轮保留资源编辑器原有操作，不再提供额外的 Block note / Edit / Save 栏。以下产物使用 `lib/main.dart`，可持续人工操作，不是自动断言入口。

## 普通客户端

统一目录：`/Users/mac/src/openmuse-io/Muse-Client/target/manual-acceptance/siyuan/2026-11-02-editor-parity/`。

| 平台 | 文件 | 验收范围 |
| --- | --- | --- |
| macOS ARM64 | `OpenMuse-macos.app` | 编译、签名及原生 Host 资源 UI；安装位置 `/Users/mac/Applications/OpenMuse Resource Review 20261102.app` |
| Android ARM64 | `OpenMuse-android-arm64-debug.apk` | 普通独立包 `com.openmuseai.mobile.siyuanreview`，覆盖安装保留数据；OPPO PKM110 / Android 16 |
| iOS ARM64 模拟器 | `OpenMuse-iOS-simulator.app` | 独立 `.siyuanreview` 包；iPhone Air / iOS 26.5 |
| iOS ARM64 设备 | `OpenMuse-iOS-device-unsigned.app` | Release 无签名构建；需开发者签名和设备授权，不能作为 iPhone 真机 UI 通过证据 |

各平台构建命令、内核和 runtime 摘要在产物目录分平台 JSON 中。最终验收见 [本轮报告](EDITOR-PARITY-ACCEPTANCE.zh-CN.md)，对应实现见 [编辑器适配](EDITOR-PARITY.zh-CN.md)。最低声明 macOS 12 / iOS 15.1；没有将新系统上的测试推导为最低系统实测。

## 操作顺序

1. Home → 本机 / This Device，反复切换最近和本机；应正常展开设备与 Workspace，没有红色类型异常。
2. `+` → 块笔记 / Block note，新建 `.sydoc`。Desktop 使用 OpenMuse 标签，Mobile 使用共享资源页。
3. 内容区保留原生面包屑、锁按钮、文档菜单、标签、图标、封面。非空原生标题仍显示；空标题不再额外占一行 Untitled。没有第二套 Workspace、全局 tab、Dock、品牌启动页或附加保存工具栏。
4. 点击原生锁按钮进入编辑，输入文字，插入图片/附件、选择图标或封面。输入后自动保存，直接返回或关闭标签应等待保存完成；正常流程无需另按 Save。
5. 从最近重开，检查文字、图片、封面和附件仍在；进入编辑，点击靠近视口底部的正文，系统键盘升起后光标应在原生键盘操作栏上方。
6. 点击包内附件链接：有本机资源 handler 时交给该插件，没有 handler 时使用系统应用；返回后原笔记仍可继续查看。检查实际 `test.sydoc` 的 JPG 图片和 Word 附件。文件已移除或系统没有可用应用时应提示失败，不能把笔记替换成 JS 错误页。

自动化复现：Desktop 执行 `flutter test integration_test/siyuan_resource_ui_acceptance_test.dart -d macos`。Mobile 构建同名 integration target 到 `.acceptance` 包，再使用插件 `scripts/accept_resource_android.py` / `scripts/accept_resource_ios.py` 收集完整原生套件。`--visual-checkpoints` 暂停在图标选择、图片、跨插件文档和键盘处用于 CUA 截图；iOS 需原生 UIKit 点按建立 first responder，Flutter 合成 pointer 不能替代该触摸。

`.sydoc` 保持原生包结构；原始 `.sy` 只读。图谱、闪卡、整库迁移等尚未逐项验收的内容仍列在 [开发计划 B](IMPLEMENTATION-PLAN.zh-CN.md)，不由本轮编辑器回归推导为全部完成。
