# 原生编辑器修正验收

2026-11-02。对应 [适配方案](EDITOR-PARITY.zh-CN.md) 和 [普通客户端人工流程](MANUAL-REVIEW.zh-CN.md)。以完整原生套件成功为通过依据，截图检查点不代替套件结果。

## 本轮结果

| 平台 | 结果 | 证据目录 `docs/evidence/editor-parity/` |
| --- | --- | --- |
| macOS / ARM64 | 10 项通过 | `macos.json` 与完整 native suite |
| OPPO PKM110 / Android 16 | 15 项通过 | `android-device.json` 与完整 native suite |
| iPhone Air 模拟器 / iOS 26.5 | 15 项通过 | `ios.json` 与完整 native suite |

Desktop 覆盖共享 Workspace 标签、新建、原生编辑与默认查看、自动保存关闭屏障、最近重开、原生包图片实际解码，以及无额外 Block note / Edit / Save 栏。Mobile 另外覆盖本机/最近切换、原生文档结构、图标选择器、包内附件交给已安装 Notes handler 并返回、空标题无 Untitled 占位及多余高度、真实软键盘与光标位置。

Mobile 的跨插件附件使用真实内核上传和原始链接点击，不用假 WebView 或模拟成功的文件保存。Word/Excel/PPTX 的 MIME 回归另验证 OOXML 的 ZIP 文件头不会覆盖其文档格式；这不等于这些格式的所有编辑器均已完成适配。

## 输入与视觉证据

Flutter 原生 integration binding 驱动资源中心与返回操作，正文使用原 Protyle DOM 输入。Android 的实际平台 IME inset 为 906 物理像素；iOS 为 1239。光标底边必须小于原生键盘操作栏顶边，且在内容视口内。具体数值保存在平台 JSON。

iOS UiKitView 不接收 Flutter 合成 pointer 所代表的真实 UITouch，故使用 CUA 原生 Simulator 点按建立 first responder，再由 integration assertions 检查 IME 与 caret。没有把这一步称为完全无人值守的 Flutter 触屏测试。

截图位于 `screens/`：`android-package-image.png`、`ios-package-image.png`、`ios-keyboard-caret.png`、两端原生图标面板与跨插件附件页。套件结束后的截图以 `after-suite` 标识，不用来证明软键盘正在显示。

## 原有文档的定向检查

实际 `test.sydoc` 的 JPG 和 Word 附件均存在于插件私有资产区。图片与封面失败源于漏掉原客户端的资源基址初始化，已修复，并通过两端保存重开后真实图片解码回归。空标题使用原生 `custom-sy-title-empty` 状态隐藏占位，不删除正文，也不覆盖非空标题。

Word 链接原先解引用不存在的完整应用 `ws.app`。已改为资源出口，并由 Android 定向测试上传有效 DOCX、点击原生链接。系统状态已确认进入 `andes.oplus.documentsreader` 文档查看器；用户随后在真机确认图片、封面和 Word 链接「已经 OK」。此项记为人工通过；此前自动化截图因 Mac 锁屏中断，仍不把它计入上表的 15 项自动化成功。

## 构建与范围

四份普通客户端均来自 `lib/main.dart`，分平台 JSON 与 `artifacts.json` 记录命令、runtime、适配器和原生产物摘要。macOS 深层严格签名检查通过；Android 10 个 ARM64 ELF 的 16 KiB 对齐及依赖闭包通过；iOS 无签名 Release 保留六个内核 FFI 入口。

已覆盖安装 Android 普通客户端，并安装 macOS 普通客户端和 iOS 模拟器普通客户端。iOS 设备产物未签名，未进行 iPhone 真机 UI 验收；没有把 iOS 26.5 模拟器结果等同于 iOS 15.1 最低系统实测。没有提交、推送或上传商店。

本轮定向回归：runtime 8 项、插件适配器 4 项、共享资源中心 7 项、SDK 关闭屏障 2 项、Mobile Shell 15 项均通过。生产 Host、Mobile Shell、SDK 与资源中心代码未加入思源名称或领域分支；上游 vendor 工作树干净。内核、格式、标题、图片路径和链接解释均在插件内。

图谱、闪卡、整库迁移等未逐项验证的剩余模块仍按 [计划 B](IMPLEMENTATION-PLAN.zh-CN.md) 管理，本轮没有宣称完整思源产品的全部高级 UI 均已验收。
