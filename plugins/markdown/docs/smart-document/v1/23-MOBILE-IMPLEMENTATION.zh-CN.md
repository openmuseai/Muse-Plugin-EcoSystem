# Mobile 首批实施与验证（M3-A）

> 后续进展（2026-11-06）：隔离后端已恢复，iOS 双账号 Cloud + 新进程代码块恢复通过；稳定类型命令已替换 Aa/列表的旧 replacement 路径，见 [P4 新报告](25-PHASE4-IMPLEMENTATION.zh-CN.md)。下文保留 M3-A 当时失败与边界，原归档不改写。

2026-11-05 开始，2026-11-06 完成归档。输入为 **SD-MOB-1.3-20261105**：[产品交互](21-MOBILE-PRODUCT-UX.zh-CN.md) → [完整视觉稿与计划](22-MOBILE-DESIGN-REVIEW.zh-CN.md)。本轮完成 Mobile 本机纵向链路与部分编辑能力；**M3-A 尚未完成 Cloud 互通门，完整智能文档 0.1 尚未验收**。

## 本轮实现

同一 `SmartDocumentView` 在窄屏选择新的 `MobileSmartDocumentView`；仍使用原 AppFlowy EditorState、同一 Rust/原 AppFlowy-Collab 文档会话、原 Cloud provider 和公开 SDK resource session，没有增加移动专用文档副本或协作协议。

| 能力 | 实际运行状态 |
| --- | --- |
| 阅读/编辑 | 阅读胶囊、完成、undo/redo、更多、同一正文连续编辑；资源标题和本机/同步状态可见 |
| 键盘功能区 | AI / + / Aa / 列表 / 对齐 / 图片 / @ 用户 / 键盘开关八入口；前七项窄屏横向可达，44 点击目标 |
| Aa | H1–H6/正文、B/I/U/删除线、普通字体色与高亮、清除颜色；渐变尚不可用 |
| 列表/对齐 | 有序/无序/待办三项浮层；左中右/减少增加缩进五项浮层；根级减少缩进禁用；保留输入连接 |
| 插入 | 正文、引用、代码、分隔线；表格/图片/云文档/文件/视频尚不可用 |
| AI | 浮动功能菜单、输入条/渐变边线、键盘布局；未接 Agent provider，发送和实际 AI 任务不可用 |
| @ / 协作业务 | @ 保持用户语义；身份目录、分享/评论/历史 provider 尚未接入，不返回模拟成功 |
| 保存与生命周期 | 后台 Flutter lifecycle callback 触发本机 flush，失败保留会话；公开 SDK CAS 检查点与新进程重开 |
| 原生构建 | iOS arm64 simulator / device、Android arm64 / x64 的 native asset 目标已配置；本轮运行验收为 iOS arm64 simulator。Android arm64 曾成功构建，按用户指令不继续安装/真机验证 |

当前是实现上述交互的首批功能面，尚未达到目标视觉稿所有 20 画面的产品覆盖。封面/页面设置、完整元信息、资源 tabs/Host 关闭、完整个人视图设置等仍按 MA 矩阵分批接入。

## 实际修复

**键盘状态：** Scaffold 负责 resize，并从 body 的 MediaQuery 消费 IME inset。使用内部 MediaQuery 判断键盘会误判，现读取 `FlutterView.viewInsets` 并监听 metrics；不重复添加 bottom inset。系统仅隐藏键盘但仍保留输入连接时，展开按钮会重新建立连接，避免相同文本的 fast path 跳过 show。iOS 原生测试实际看到软键盘 335 逻辑像素、工具栏 bottom 539，工具栏位于键盘上方。

**对齐后重开出现重复正文：** AppFlowy 的 UpdateOperation.oldAttributes 是稀疏 inverse。全量 attributes 中有未变化的 delta，inverse 则不含 delta。旧转换代码将缺失旧值当 `[]`，把全文再次插入 Rust；当前编辑树看似正确，重开才暴露。现仅在 inverse 含 delta 时计算文字差异，普通块属性更新保持为属性增量。新增真实文件重开回归，并将 Mobile 新进程重开升级为精确文本比较，避免只检查 contains 掩盖重复。

块类型/缩进转换仍沿用 AppFlowy replacement transaction，可能生成新块 ID；正式评论/嵌入前须交付稳定身份转换及锚点迁移，不能宣称已有稳定跨类型锚点。

## 实际验证与证据

详见 [本轮证据目录](execution/phase3-mobile-20261105/README.zh-CN.md) 与 [机器可读结果](execution/phase3-mobile-20261105/result.json)。

| 验证 | 结果与边界 |
| --- | --- |
| 设计原型 | 20 个画面、320/360/390/430 四宽度无页面横向溢出；原型与原生产品分开记录 |
| Dart analyze | 无问题 |
| Native 回归 | 6 项 controller + 2 项 Mobile widget 测试通过；含 full attributes 对齐后保存/重开不重复、只读拒绝、保存失败恢复、44px 目标和一次 IME 避让 |
| 浏览器回归 | 真实 Chrome WASM/IndexedDB 关闭重开 1 组通过；本轮未重新跑 Cloud Web 双账号，既有 F2 历史证据保持原样 |
| iOS 原生集成 | 实际 App 的资源 creator/provider/hub/plugin → 系统输入连接 → Unicode 回调 → AppFlowy → Rust → Aa/H6/列表/对齐 → 本机持久化 → SDK CAS → 重开通过；软键盘实际可见 |
| iOS 新进程 | 第二个独立 Flutter test 启动进程，复用同一资源 objectId，精确检查中文/emoji 只出现一次，列表、居中、选区加粗保留；关闭前执行 SDK prepareToClose |
| 原生 UI 视觉与按键 | 使用 CUA 在 Simulator 检查真实软键盘与功能区；真实 OS 按键 x 进入正文后，通过原生撤销恢复原文，未操作用户文档；截图是运行产品 |
| Cloud | 首次 iOS Cloud 尝试失败于 CLOUD_1057；独立 preflight 确认 auth 连接被拒、Redis 不可达、Docker engine 不能启动。本轮 Mobile Cloud 双账号验收未通过；本机模式不被计为协作成功 |
| Android | 用户选择“仅继续 iOS，暂不安装”；取消时安装队列已完成，随后已移除独立测试包，未继续真机测试，不触碰其他 App 数据 |

自动输入使用同一 TextInputClient 回调，**不等同于人工拼音候选、长按选区、中文组合输入、外接键盘的完整验收**。生命周期检查为 Flutter callback 路径；真实 OS 后台长期挂起/杀进程、物理 iPhone、旋转/平板与无障碍专项仍未全部覆盖。新进程重开通过也不能替代突发断电的耐久性证明。

## 可重跑

进入 `smart_document`：

```sh
python3 scripts/verify_mobile.py --device <明确的iOS设备ID> --local-only --require-soft-keyboard
```

该命令在指定设备安装独立测试 App，以全新 run 执行编辑和第二个新进程重开，用 `--no-uninstall` 保留沙箱，核对两个回执的 objectId 相同，结果写入忽略目录 `.build/mobile-runs/`。本机模式显式标记 Cloud 未运行。`--require-soft-keyboard` 会断言实际键盘可见；模拟器先临时断开硬件键盘连接，检查后恢复原配置。

恢复隔离后端后省略 `--local-only`，使用 `--fixture` 指向本地合成账号文件；preflight 不通过即失败，不退化为本机模式。Cloud 模式会增加第二认证用户的原服务 full-sync 检查。凭据文件为私有 mode 0600，不能发布测试 App 或把 defines 放入证据包。

原生手工预览：在 `flutter/example` 执行 `flutter run -d <iOS设备ID>`，不传账号文件即是本机模式。固定 Rust target、Xcode/NDK 与 release native asset 构建逻辑见 `flutter/hook/build.dart`。32 位 Android 不在当前 ABI 支持范围；通用 APK 构建须显式限定受支持的 64 位 target。本轮 Android fixture 使用 file_picker 10.3.10 override 和 AGP finalizeDsl 对旧依赖设置 compileSdk 36，未修改全局 pub cache 或生产 Host。旧 keyboard_height_plugin 在 iOS 回退 CocoaPods，Android 依赖仍使用 KGP，这两项实际构建兼容债在生产接入前处理。

## 接下来的开发门

1. **M3-A 协作门：** 恢复本地 Docker/GoTrue/Redis，重跑 Mobile 双账号及断线合流；补跑 macOS/Web Cloud 回归。已有 Cloud provider 的“服务已接收”仍不冒充耐久 ACK，也没有新增 WS presence。
2. **M3-B：** 稳定块身份/锚点、图片资源草稿与上传、基础表格、元素 registry、渐变版本化样式；各项必须先明确领域 schema/unknown element round-trip，再接 UI。
3. **M3-C/D：** 身份目录 @、annotation/分享/版本与权限，Muse Agent scope/预览/预条件/应用。保留资源、协作与业务插件的解耦，不让工具栏直接写服务端或拼接协作 JSON。
4. **M3-E：** 真 iPhone 中文输入、后台/进程终止、外键盘/旋转/无障碍，按用户后续授权安排 Android；达到完整 MA/AC 门后再纳入生产 Host 发布。
