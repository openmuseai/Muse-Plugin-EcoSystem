# 编辑器原生交互恢复

2026-11-02。本轮修正独立编辑入口裁减过度的问题。资源管理、资源引用和插件间交接由 OpenMuse 负责；进入资源后使用上游编辑器原有的 UI 和交互实现，不另加「Block note / Edit / Save」工具栏。

## 实现边界

| 区域 | 实现 |
| --- | --- |
| 外层资源标题、来源、返回、版本和打开方式 | OpenMuse 通用资源框架 |
| Mobile 文档标题 | 上游 `Title` 与 `initEditorName`，包括名称校验、输入法、Enter 和标题保存逻辑 |
| 面包屑及操作按钮 | 上游 `Breadcrumb`，含命令、锁定、文档操作和更多菜单 |
| 封面、标签、文档图标及选择器 | 上游 `Background`、Emoji Dialog，保留原交互 |
| 输入与键盘工具栏 | 上游 Mobile Protyle、touch、`initKeyboardToolbar`、mobile bars 和光标滚动逻辑 |
| 导出 | 原客户端文件导出桥复用到资源 surface；不进入 Host 领域代码 |
| 资源写回 | 插件导出原生包，通过受限 `ResourceEditorSession.commit` 做 CAS；Host 不解析笔记内容 |

Mobile 使用独立的 `resource-mobile` 构建，执行上游 `MOBILE=true` 代码并加载原 Mobile 样式；Desktop 继续使用对应 Desktop 编辑器。原 Mobile 主编辑器由 `window.siyuan.mobile.editor` 注册，避免重复进入 `getAllEditor`。不实例化原应用的 Workspace、全局文档标签或应用底栏。

## 保存与关闭

原生锁按钮负责进入/退出编辑。资源默认查看态映射到上游「默认只读 / 临时解锁」策略，避免把资源预览锁错误地写成文档持久属性。

插件在输入和原生事务后自动写回，650 ms 空闲合并，不移动焦点或收起键盘。快照前等待原生待处理输入和事务；导出期间发生新编辑则重试，提交期间发生新编辑则保留脏状态继续保存。冲突或保存失败保留工作副本并反馈错误。

Desktop 关闭标签、Mobile 返回前，通用编辑会话等待插件完成保存屏障。正常退出不要求点击额外保存按钮；保存失败仍提供留在编辑器或明确放弃的选择。此扩展是格式无关的可选回调，也可供后续 Word/Excel 等插件使用。

## This Device 错误

原 `ExpansionTile` 只有 `ValueKey`，会沿用祖先列表的 PageStorage 标识，把滚动位置 `double` 当成折叠状态 `bool?` 读取。分组改用包含账号、设备及 Workspace 的独立 `PageStorageKey<String>`。回归显式写入 `42.0` 滚动状态，再反复切换 Recent / This Device，验证不再发生类型异常。

## 验收与产物

实际结果、截图、构建和安装记录见本轮 `docs/evidence/editor-parity/`；未取得完整原生套件通过结果前不认定 UI 通过。Mobile 流程使用真实系统键盘，要求平台 IME inset 大于零，并检查末行光标在编辑视口内且位于原生键盘工具栏上方。测试设置短暂停留点用于截图，不将中途检查点当成整套成功。

本轮不将图谱、闪卡、整库迁移等此前计划 B 的全部模块宣称为已验收。现有原生数据格式及 Go 内核保持不变，vendor 工作树不修改。

## 链接、图片与空标题修正

原独立入口缺少 `addBaseURL()`，导致 `assets/...` 图片和封面按 `/stage/build/resource-mobile/` 解析；文件仍在包内却无法显示。现在复用原客户端的基址初始化，Desktop 与 Mobile 都在挂载 Protyle 前完成。验收必须在保存、关闭、重新导入后检查图片 `complete`、`naturalWidth` 和 `naturalHeight`，仅发现包内存在文件不足以通过。

原客户端的 `openByMobile` 依赖完整应用的 `window.siyuan.ws.app` 和平台对象。独立资源入口通过插件的 `openLink` 出口接管外部文档，不补造第二套 App 壳。包内附件在插件中使用本地会话读取，再通过格式无关的 `ResourceEditorSession.openLinkedContent` 交给已安装 handler；共享资源中心创建带来源版本的只读快照，不接收思源数据目录、内核端口或会话凭证。没有本机 handler 时使用系统文件查看器；网页使用系统浏览器。路径/文件不可用时提示失败并保留当前笔记。系统打开的临时副本不自动反向修改笔记附件。

空文档标题按原生 `custom-sy-title-empty` 状态处理：保留文件页顶部标题，隐藏空标题的额外占位行，不再显示多余的 Untitled。非空原生标题及原生重命名仍保留；不删除正文中用户自己输入的同名段落。原生标题更新完成后刷新占位状态，Host 不解析思源标题属性。
