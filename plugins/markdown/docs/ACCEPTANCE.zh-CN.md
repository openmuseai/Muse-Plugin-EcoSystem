# 思源客户端插件验收

> 本文保留 0.1 完整应用壳的历史基线。0.2 资源化适配请查看 [本轮报告](resource-adaptation/ACCEPTANCE.zh-CN.md) 和 [普通客户端](resource-adaptation/MANUAL-REVIEW.zh-CN.md)。

日期：2026-11-01。上游固定提交：`d3af9d5782082b379d45a69eedf4ebcfe8ba6889`（SiYuan 3.8.9）。验收直接运行原版 Browser Desktop/Mobile 前端与插件内的本机 Go 内核，无远端思源实例。

后续已完成真实 Host 内的 UI 验收及普通客户端安装，见 [人工验收说明与产物](MANUAL-REVIEW.zh-CN.md)。Desktop 验证了已安装插件入口、真实键盘输入和进程重启后内容恢复；Android 真机与 iOS 模拟器各通过 5 项 Host UI 检查，原生测试绑定均报告整套通过。本轮修复了 Mobile 预览的 A2UI catalog 标识，并补上 Desktop 的通用面板打开入口。补充回归：Desktop 工作台 22 项通过、1 项跳过；Mobile 相关测试 20 项通过。

| 环境 | 结果 | 原生结果记录 |
| --- | --- | --- |
| macOS Desktop / ARM64 | 14 项通过 | [macos.json](evidence/macos.json) |
| Android 真机 / ARM64 | 14 项通过 | [android.json](evidence/android.json) |
| iOS 26.5 模拟器 / ARM64 | 14 项通过 | [ios.json](evidence/ios.json) |

每端检查：本机内核启动；未授权回环请求被拒绝；内核退出 API 不终止 Host；内核使用设备本地时区；笔记本与 Markdown 导入；块写入及搜索索引；Markdown 导出；原版 Protyle 渲染；内核报告真实平台类型；界面输入真实落盘；原版 ZIP 导出与原生保存桥；加密笔记锁定、解锁后的内容恢复；本地 OCR 运行库可用；停用撤权、重新启用后内容保留。

主 Host 构建也已通过，见 [构建记录](evidence/host-builds.json)：macOS Debug 应用、Android ARM64 Debug APK、iOS 设备目标的无签名 Release 应用。Android 最终 APK 同时包含语音插件的 `libonnxruntime.so` 和思源独立的 `libsiyuan_ort.so`，已验证包完整性。iOS Release 可执行文件保留全部 6 个思源 FFI 入口，应用包含原版前端资源；这项检查验证编译与链接，不包含真机签名安装。

导出保存桥的自动验收使用受控导出回调，核对原版导出 ZIP 的实际 Markdown 内容；系统保存对话框不作为自动测试的输入。核心验收使用独立应用包名，避免覆盖正式应用和用户工作空间。Android 使用与仓库原生移动验收一致的 Skia 启动参数。iOS 结果属于模拟器，不等同于 iOS 真机、TestFlight 或 App Store 验收。

补充回归：Desktop Host 相关测试 21 项通过、2 项跳过；Mobile Host 相关测试 20 项通过；通用原生详情页与目录测试 2 项通过；资源安装安全与更新保留测试 2 项通过；导航边界测试 2 项通过；语言映射测试 1 项通过；本机会话鉴权、停用撤权及退出保护的 Go 测试通过。原版前端 TypeScript 检查和插件 Dart 分析通过。

领域边界：Host 应用源码不包含思源 API、笔记模型或插件 ID 分支。平台装配集中在 distribution，SDK 的新增接口只描述通用原生详情表面。原始 vendor 工作树保持干净，所有构建适配在插件的隔离构建目录生成。用户数据与版本化的只读资源分开保存。

兼容范围：本轮为 ARM64 的 macOS、Android、iOS。Host 最低系统为 macOS 12、Android API 24、iOS 15.1；当前官方 macOS OCR 库另要求 macOS 14。这里没有宣称 Windows、Linux、Intel Desktop 或旧系统已通过实机验收，也不替代上游全部功能的逐项人工测试。
