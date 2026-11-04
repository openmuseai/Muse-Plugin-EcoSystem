# 资源化适配验收

> 编辑器交互已按后续反馈修正；当前实现与人工流程见 [原生编辑器适配](EDITOR-PARITY.zh-CN.md) 和 [最新验收](EDITOR-PARITY-ACCEPTANCE.zh-CN.md)。本文件保留原资源化阶段记录。

2026-11-02；补验更新于当日。本报告对应 [计划 A：资源化主流程](IMPLEMENTATION-PLAN.zh-CN.md)，不代表完整思源的所有工具面板均已迁移；剩余范围明确列在 B 阶段。

## 实现与边界

- 插件贡献 `.sydoc` 新建、打开、编辑、基础 AST 文本提取；原始 `.sy` 只读，原生文档 `.sy.zip` 可打开；整库/多笔记本备份导入属于 B1。普通 Markdown 和任意 ZIP 不被本插件抢占。
- 编辑区独立构建 Protyle，不实例化原应用 App。Host 保持工作区、标签和导航，Mobile 复用新 Home 资源中心；无思源应用外壳或品牌启动动画。
- 资源编辑使用插件私有工作副本，待处理输入/事务确认后导出原生包，通过共享编辑会话 CAS 写回。资产导入改用原生引用重写并分配独立身份，避免同名不同内容的附件覆盖另一资源。
- Host 新增的代码仅为通用资源 presentation/session 与工作区标签衔接及非文件 URI 兼容。生产 Host/Mobile/SDK/资源中心源码的 `siyuan / SiYuan / 思源` 检索为零；领域接口、原生内核、原生包解释均在插件中。vendor 工作树保持干净，未提交或推送。

## 实际验证

| 层级 | 结果 | 证据 |
| --- | --- | --- |
| macOS 真正 Host 工作区 | 7 项主流程通过；另断言原有文件标签保留、无旧文件预览只读 banner | [业务结果](../evidence/resource-adaptation/macos.json)、[完整 native suite 输出](../evidence/resource-adaptation/macos-native-suite.log) |
| Android API 34 ARM64 模拟器（此前基线） | 6 项主流程通过；最终修复版以真机补验为准 | [结果](../evidence/resource-adaptation/android-emulator.json)、[native suite](../evidence/resource-adaptation/android-emulator-native-suite.json) |
| Android 16 / OPPO PKM110 真机 | 最终修复版 7 项主流程通过，native suite 为 true | [结果](../evidence/resource-adaptation/android-device.json)、[native suite](../evidence/resource-adaptation/android-device-native-suite.json) |
| iOS 26.5 / iPhone Air ARM64 模拟器 | 最终修复版 7 项主流程通过，native suite 为 true | [结果](../evidence/resource-adaptation/ios.json)、[native suite](../evidence/resource-adaptation/ios-native-suite.json) |
| macOS 原生内核与独立编辑器（数据基线） | 8 项数据/内核检查通过；后续修复未改变该归档/Go 内核逻辑 | [数据检查](../evidence/resource-adaptation/native-core.json) |
| 格式与能力 | 3 项通过：无嵌套应用贡献、不抢 ZIP/Markdown、原始 sy 只读 | `.build/resource-capability-tests.log` |
| 归档校验 | 4 项通过：原生结构/资产保留、raw sy、路径/重复目录拒绝、非法归档拒绝 | `.build/resource-archive-tests.log` |
| Host / 文件预览回归 | 28 项通过，1 项既有跳过 | `.build/resource-host-regression-followup.log` |
| Mobile 回归 | 22 项通过 | `.build/resource-mobile-regression.log` |
| 共享资源中心 UI / 连接 | 6 项通过，含失效挂载恢复、动态停用 creator、320px/大字 | `.build/resource-center-ui-regression.log` |
| 资源 IO / CAS / 授权回归 | 29 项通过 | `.build/resource-io-regression.log` |

最终三端各 7 项：资源中心真实创建、无嵌套应用壳、编辑器主题与图标加载、脏关闭后继续编辑、编辑与版本化保存、最近重开/只读查看、Host 导航与标题。原生 integration suite 使用 Flutter 控件操作及原 Protyle DOM 输入，并触发 mouseup/dblclick/键盘选区处理；业务 JSON 只在对应完整原生 suite 成功后采信。

Desktop 普通客户端另经 CUA 原生鼠标和键盘验证：输入正文 `Desktop keyboard verification 20261102`，关闭时继续编辑、保存、关闭标签、从最近重开，正文保留且重开为只读态。见 [可视结果](../evidence/resource-adaptation/macos-visual.json)、[保存后截图](../evidence/resource-adaptation/screens/macos-keyboard-saved.png)、[重开截图](../evidence/resource-adaptation/screens/macos-reopened.png)。此项不是测试入口截图，不代表全部移动触屏/中文输入法矩阵均已覆盖。

8 项数据检查覆盖：独立 Protyle、待处理输入 flush、原生数据库 roundtrip、原生附件 roundtrip、块引用 ID 重映射、同名不同附件隔离、两个资源编辑隔离、包内文档定位。数据库/附件/关联文档由真实内核生成 fixture，正文由原编辑器输入；没有用这些 fixture 冒充高级工具的完整 UI 操作。数据库所有字段类型、图谱、闪卡等 UI 没有穷举。

CAS、固定历史版本、远程只读等由既有共享 Provider 实现；插件通过受限 `ResourceEditorSession.commit` 进入该路径。本轮未宣称三端全部并发冲突 UI 已穷举。

## 构建、安装与未完成项

四份普通 `lib/main.dart` 客户端已构建；Desktop 已安装到用户 Applications，最终产物和已安装副本均通过 `codesign --verify --deep --strict`；iOS 普通模拟器客户端已安装；Android 普通 APK 已安装至真机。构建命令、web runtime 摘要、原生库摘要及 adapter 源码摘要见 [构建记录](../evidence/resource-adaptation/macos-build.json)、[Android](../evidence/resource-adaptation/android-build.json)、[iOS 模拟器](../evidence/resource-adaptation/ios-simulator-build.json)、[iOS 设备目标](../evidence/resource-adaptation/ios-build.json)。[关键源码摘要](../evidence/resource-adaptation/sources.json) 可用于复核。Desktop/Android 内含 Go 内核的 build ID 与本轮源产物一致，见 [内核链接核对](../evidence/resource-adaptation/linked-kernels.json)。

- Android 真机阻塞已解除。隔离自动化包和最终普通 `.siyuanreview` APK 均成功安装；真机已通过最终 7 项 native UI 流程。普通包已启动到地区选择页，手机上已安装 APK 的 SHA-256 与交付文件一致，见 [安装核对](../evidence/resource-adaptation/android-installed.json)。未卸载正式客户端。
- iOS 设备目标为无签名 Release；未在 iPhone 真机执行本轮流程。
- Mac 解锁后已完成上述普通客户端原生输入与可视复核。Android 镜像未完成普通客户端的整套触屏人工流程；真机端到端结论来自完整 native integration suite。中文输入法、暗色及全部尺寸/高级工具仍需对应矩阵，未从这次主流程推导为全部通过。
- 完整知识库 Provider、原有库迁移、跨资源块身份及图谱/闪卡/模板/历史等完整工具 UI 仍属计划 B，尚未完成。原有 userdata 保留。

[人工验收产物与操作说明](MANUAL-REVIEW.zh-CN.md)。

## 解锁后的补验修复

1. 历史 Workspace 挂载路径不存在时，只跳过该不可用目录，保留个人资源与其他挂载，并允许同一路径恢复后重试；新增回归覆盖失效目录位于有效目录之前的情况。
2. 独立 Protyle bootstrap 显式加载原生主题和图标，等待样式就绪，跟随 Host 主题并禁用原应用主题脚本。
3. 原生鼠标选区/键盘处理不再要求原应用状态栏存在；仅补丁 staged 源码，不新增隐藏状态栏或修改 vendor。
4. 使用共享资源 session 的 Desktop 标签不再附带旧文件预览插件的只读 banner。

四份普通客户端已同步上述最终 runtime，运行时 ZIP 摘要一致；[安装记录](../evidence/resource-adaptation/review-install.json) 已更新。
