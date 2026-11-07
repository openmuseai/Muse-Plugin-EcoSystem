> 历史 v1.1 原型。当前功能对齐稿见 [v1.2](../12-FUNCTIONAL-ALIGNMENT.zh-CN.md) 和 `../wps-functional-review/`。

# 视觉交互稿源码与检查

2026-11-05。此处仅为产品评审原型，不是 Flutter 产品或协作服务实现。画面/流程说明见 [视觉评审](../10-VISUAL-REVIEW.zh-CN.md)。

`prototype.fragment.html` 是可编辑的视觉稿源，提供工作区协作、专注创作与 Mobile 三种方案。主题依据 Host token，所有示例交互在本地状态中完成，无真实邀请、剪贴板写入、文件保存、网络或账号调用。

使用当前 visualize 技能的 `scripts/render.py` 将 fragment 包装到本地预览，然后执行：

```sh
node review-check.cjs /absolute/path/to/rendered-preview.html
```

检查默认寻找本工作区 AppFlowy Web vendor 的 `@playwright/test`，使用已安装 Chrome 的隔离 headless 会话。其他环境可用 `REVIEW_PLAYWRIGHT_MODULE` 指定本地模块路径；这里不自动安装浏览器/依赖。检查结果与截图写入 `screens/`。

覆盖内容：同一对象多入口、移除引用不删源、Agent 对数据集与正文的明确目标、前置条件冲突、评论者边界、连接服务不可用、历史只读、布局切换、Mobile 上下文与窄屏/主题。真实内核、服务端 ACL、耐久与 CRDT 仍按产品验收规格执行。

原型的普通按钮可直接点击；方案由预览中的方案切换器切换，键盘可聚焦切换按钮后按 Enter。连接状态也可在“保存与协作”对话框中演示。修改视觉稿后重新包装并复查，保持源、截图与 QA 对应。
