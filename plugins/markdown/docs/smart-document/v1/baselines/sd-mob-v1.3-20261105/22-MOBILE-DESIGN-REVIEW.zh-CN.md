# Mobile 视觉交互稿与实施基线

2026-11-05 · **SD-MOB-1.3-20261105** · CR-SD-MOB-20261105。

用户已确认初步对齐，并要求落实稿件后继续开发。本基线追加于 SD-BL-1.2 / SD-F1，不改写两份历史冻结快照。产品输入为 [Mobile 产品与交互规格](21-MOBILE-PRODUCT-UX.zh-CN.md)，来源为 [WPS 实机观察](20-WPS-MOBILE-REFERENCE.zh-CN.md)。AI 只保留输入与功能浮层样式，不要求完整复刻 WPS AI。

## 交付与查看

打开 [可交互视觉稿](mobile-functional-review/index.html)，或在本目录运行 `python3 -m http.server 18081 --bind 127.0.0.1 --directory mobile-functional-review` 后访问 localhost。20 个画面与 24 项 MA 需求关联；画面左侧切换、右侧规格属于评审工具。追加 `?presentation=phone&frame=list` 可检查纯手机布局。

| 画面 | 目标与验收重点 | MA |
| --- | --- | --- |
| MF-01–03 | 阅读胶囊、编辑顶栏、完整八入口与系统键盘避让 | 01–03、14、24 |
| MF-04 | H1–H6/正文、B/I/U/删除线、18 字体色含渐变、10 高亮色 | 06–09、15 |
| MF-05–06 | 保持键盘的三项列表和五项对齐/缩进浮层 | 10–11 |
| MF-07–08 | 插入分类、图片块内两来源与六项上下文、文本工具禁用 | 05、12、16 |
| MF-09 | 仅用户提及；云文档独立进入 + 插入 | 13 |
| MF-10 | AI 功能浮层、输入条替代普通工具、键盘保留、修改预览 | 04、15 |
| MF-11–13 | 目录定位、个人阅读偏好、完整文件/更多分类 | 18–20 |
| MF-14–16 | 锚点评论、成员权限、历史恢复为新版本 | 21–22、24 |
| MF-17–18 | 表格上下文与独立 Word/PDF/工作簿来源 | 17、23 |
| MF-19–20 | 只读、权限与离线/保存/同步状态 | 24 |

## 视觉与行为约束

正文留白约 24，默认字级 16、标题 29；导航 52、工具栏 51，点击目标至少 44。系统状态栏、安全区、输入法高度由设备提供。320–430 宽度保留键盘开关，前七项横向滚动。Aa 是约 400 高的滚动面板；列表/对齐是紧凑浮层；AI 功能区浮在输入条上方。更多按钮采用三横线，不解释为目录。

原型中的系统键盘为布局示意；标题/作者/成员全部为合成数据。不要把模拟键盘、内存撤销、评论和 AI 建议演示当作 Cloud/输入法/通知/Office 的工程验证。真实来源图片留在忽略目录，版本化产物只包含重绘稿和结构化观察，避免传播用户文档及水印。

## 已执行的原型检查

[design-qa.json](mobile-functional-review/design-qa.json) 记录 20 个画面、4 种视口宽度的 DOM 几何；均无页面横向溢出。核对 Aa 七文本类型、18 字体色与 10 高亮色，列表/对齐保留键盘，AI composer 替代普通工具栏，图片六上下文项。额外通过本地交互验证：插入 3×2 表格后从一张变两张，撤销后恢复一张；评论回复可显示。已修正图片占位图标尺寸导致的黑块，并复查图片来源按钮布局。

截图：[阅读](mobile-functional-review/screens/read.png)、[输入与工具栏](mobile-functional-review/screens/keyboard.png)、[Aa](mobile-functional-review/screens/format.png)、[列表](mobile-functional-review/screens/list.png)、[对齐](mobile-functional-review/screens/align.png)、[AI](mobile-functional-review/screens/agent.png)、[更多](mobile-functional-review/screens/more.png)、[图片](mobile-functional-review/screens/image.png)。

## 从设计反推实施

1. Flutter 自适应 surface，继续复用同一 AppFlowy EditorState、Rust CRDT、public SDK resource session 与 Cloud provider；不引入第二份移动内容模型。
2. Mobile Shell 管阅读/编辑、面板、键盘和返回顺序；文档 controller 管事务、保存与 origin undo。Scaffold 只应用一次 IME inset；列表/对齐不关闭正文输入连接。
3. 先交付正文输入、八入口位置、Aa 普通色/高亮、H1–H6、列表、对齐与基础缩进、后台 flush、资源保存/重开。渐变、图片/表格、@ 身份目录、分享/评论/历史、Agent provider 分批接入；缺能力明确不可用，不返回假成功。
4. 块类型转换目前沿用 AppFlowy replacement transaction，文本 marks 和子树需要保留，但会生成新块 ID。正式评论锚点和资源嵌入之前必须加入稳定身份转换/锚点迁移，不能假定类型变化仍是同一 block ID。移动切片不替换领域协作合同。
5. 首批 M3 验收包含真机/模拟器编译、系统 IME 连接、Unicode 回调经 AppFlowy 到 Rust、选区格式、列表/对齐、权限、后台持久化、双账号 Cloud、公开 SDK CAS 与关闭重开。手工中文候选词输入、旋转/外键盘、完整 accessibility 仍需单独验收。

## 后续排期与退出条件

| 批次 | 工作包 | 依赖 | 退出证据 |
| --- | --- | --- | --- |
| M3-A | mobile 编译/ABI、Shell、正文工具与 IME | F1/F2 | analyze、Android/iOS 原生 artifact、真实 SDK 集成测试 |
| M3-B | 图片/表格/稳定锚点、普通色跨端与渐变 schema | A、元素 registry | 同一资源 ID 的跨端 round-trip；不丢未知元素 |
| M3-C | 身份目录 @、评论/分享/历史、presence/WS | B、授权与 annotation 服务 | 双成员/访客/撤权原始 update 验证 |
| M3-D | Muse Agent composer/provider、scope/预览/应用 | B、Host Agent 合同 | 用户确认应用、过期预条件拒绝、不越权读取 |
| M3-E | Mobile 完整回归与发布接入 | A–D | Android/iOS 手工 IME、后台/进程重启、无障碍、Desktop/Web 回归 |

以上是开发顺序，不把人员缺失时的估算写成承诺日期；原完整 0.1 工期和 G0 门槛保持独立。实机未展开的深层菜单/iOS 参考依旧列在观察清单，不影响已确认布局进入开发。
