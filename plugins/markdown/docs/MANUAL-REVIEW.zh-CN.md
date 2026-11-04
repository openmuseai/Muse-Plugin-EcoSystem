# OpenMuse 思源插件人工验收

> 本文保留 0.1 完整应用壳的历史基线。0.2 资源化适配请查看 [本轮报告](resource-adaptation/ACCEPTANCE.zh-CN.md) 和 [普通客户端](resource-adaptation/MANUAL-REVIEW.zh-CN.md)。

日期：2026-11-01。思源以原生插件随 OpenMuse 客户端编译预装，完整前端、Go 内核、工作空间及文件桥均在插件中。无需额外部署思源服务端。

## 已构建并安装的普通客户端

| 平台 | 人工验收产物 | 安装状态 |
| --- | --- | --- |
| macOS ARM64 | [OpenMuse Plugin Review 20261101.app](</Users/mac/Applications/OpenMuse Plugin Review 20261101.app>) | 已安装到当前用户 Applications |
| Android ARM64 | [OpenMuse-android-arm64-debug.apk](/Users/mac/src/openmuse-io/Muse-Client/target/manual-acceptance/siyuan/2026-11-01/OpenMuse-android-arm64-debug.apk) | 已安装到连接的 Android 真机 |
| iOS ARM64 模拟器 | [OpenMuse-iOS-simulator.app](/Users/mac/src/openmuse-io/Muse-Client/target/manual-acceptance/siyuan/2026-11-01/OpenMuse-iOS-simulator.app) | 已安装到 iPhone Air / iOS 26.5 模拟器 |
| iOS ARM64 设备目标 | [OpenMuse-iOS-device-unsigned.app](/Users/mac/src/openmuse-io/Muse-Client/target/manual-acceptance/siyuan/2026-11-01/OpenMuse-iOS-device-unsigned.app) | 无签名 Release；需开发者签名与设备授权后才能安装到 iPhone |

前三份均是 `lib/main.dart` 构建的普通客户端，可以持续人工操作，不是自动退出的测试程序。Android 和 iOS 模拟器验收包使用独立包标识 `com.openmuseai.mobile.siyuanreview`，保留已有正式应用及其数据。Android 桌面可能同时存在多个 OpenMuse 图标，可从本次 APK 的安装完成页打开。

## 打开插件

Desktop：启动上述应用，首次选择可用地区；登录页可以选 **Anonymous mode**。进入 **插件 → 我的插件 → SiYuan → 打开**。工作台通过通用面板贡献打开插件；重复打开聚焦已有面板，不替换现有文件。

Android / iOS：打开本次客户端，在 **Workbench / 工作台** 点击 **SiYuan** 卡片。卡片显示 `Local notebooks · Blocks · Search`，详情页应出现原版思源编辑器。本地笔记不要求连接 Desktop，也不要求登录思源云账号。

Desktop Agent 的 API Key 提示可以选择“稍后配置”，不影响本地思源笔记。原版 Desktop 页面在 WKWebView 中会显示 Chrome 兼容性提示；本轮已经验证的功能范围见下方记录，未将该提示隐藏。

## 建议的人工检查

1. 新建文档，输入中文和英文，加入列表、待办、表格与代码块。
2. 切换到另一篇文档后重新打开，确认内容仍在。
3. 搜索刚输入的文字，点击结果回到文档。
4. 使用原版导入功能选择 Markdown；导出时在系统保存对话框选择位置并检查文件。
5. 退出客户端并重新启动，再进入插件核对笔记。
6. 在笔记本设置中检查加密、锁定和解锁；需要 OCR 时选择本地 provider。

最低系统：macOS 12、Android API 24、iOS 15.1；随包 macOS OCR 库要求 macOS 14。iOS 本轮运行验收属于模拟器，未包括 iPhone 真机、TestFlight 或商店发行。

## 已完成的 UI 验收

- Desktop：在普通 Host 中从已安装插件入口打开，使用真实键盘输入笔记，退出进程后重新启动，界面恢复相同内容。[结果](evidence/host-ui/desktop.json)、[插件入口](evidence/host-ui/desktop-installed.jpg)、[重启恢复](evidence/host-ui/desktop-reopened.jpg)。
- Android 真机、iOS 模拟器：从真实 Mobile Host 的工作台进入，点击原版前端的新建按钮，通过 DOM 输入生成编辑事件，核对插件 `.sy` 文件落盘，再关闭并重新打开文档核对 UI。两端各 5 项通过，原生测试绑定的整套结果也通过。[Android 结果](evidence/host-ui/android.json)、[iOS 结果](evidence/host-ui/ios.json)、[iOS 安装入口](evidence/host-ui/ios-workbench.jpg)。
- 核心插件此前在三端各 14 项检查通过，包括加密、搜索、导出桥、OCR、鉴权和停用后数据保留，见 [核心验收](ACCEPTANCE.zh-CN.md)。系统保存对话框仍需按上面的人工步骤操作。

## 重新构建

在 `Muse-Plugin-Ecosystem/plugins/markdown` 运行，要求原生内核和前端资源已按 README 构建完成：

```sh
python3 scripts/build_host_review.py macos
python3 scripts/build_host_review.py android
python3 scripts/build_host_review.py ios-simulator --simulator 02C59B16-550A-49A6-B84D-CE1A8D961403
python3 scripts/build_host_review.py ios
```

默认输出到 `Muse-Client/target/manual-acceptance/siyuan/<日期>`，每个平台附带构建命令、日志摘要和资源摘要 JSON。iOS 模拟器命令使用 ARM64 和独立的 Debug 包标识，不修改正式 Release 的标识与签名配置。
