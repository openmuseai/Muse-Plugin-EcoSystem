# 智能文档 v1.2 功能对齐视觉稿

产品/交互基线已冻结为 [SD-BL-1.2-20261105](../../../13-FROZEN-BASELINE.zh-CN.md)。可直接打开 [独立可点击设计预览](index.html)。

当前 Desktop/Web 设计评审入口，替代旧 `visual-review/` 的桌面布局。详细规格见 [05](../05-UX-SPEC.zh-CN.md)、[证据等级](../11-WPS-DESKTOP-REFERENCE.zh-CN.md)及 [功能映射/WF 状态/架构反推](../12-FUNCTIONAL-ALIGNMENT.zh-CN.md)。

`prototype.fragment.html` 为内联可点击源，约 52KB；包含自有样式与脚本，无外部 API。样例是独立虚构的产品共创周报，不读取企业文档。不是 .fig 文件、Flutter 实现或已上线编辑器。

可以操作文字选区格式、段落样式/移动/复制/移除、slash 搜索插入、基本表格、任务、来源共用、评论/回复/解决/重开、共享角色预览、历史及恢复、Agent 目标冲突。页脚“交互评审设置”用于模拟权限和连接，不能移入生产权限流。

在当前技能环境生成本地预览：

```sh
python3 /Users/mac/.codex/plugins/cache/openai-bundled/visualize/1.0.66/skills/visualize/scripts/render.py prototype.fragment.html /absolute/path/preview.html --force
node review-check.cjs /absolute/path/preview.html /absolute/path/new-evidence
```

检查脚本使用本仓 vendor Web 的 Playwright 和已安装 Chrome，仅访问生成的本地预览。检查支持第三个参数指定新证据目录，冻结副本禁止写回快照。实际结果以 `screens/QA.json` 为准；截图可分别检查主界面、选区、插入、评论、共享、历史、离线、深色和窄屏。

评审状态通过宿主 widgetState 保存；快照限 15KB，较大的演示状态不再写回。无真实文件持久、Cloud、CRDT、通知、邀请、PDF/Office 渲染或账号权限操作。真产品验收仍按 AC-01–AC-17。指定企业参考页的精确视觉核对尚待补证。
