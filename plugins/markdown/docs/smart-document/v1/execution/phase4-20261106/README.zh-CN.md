# P4 实际执行证据

2026-11-06 Asia/Shanghai。主报告：[25](../../25-PHASE4-IMPLEMENTATION.zh-CN.md)；范围：[24](../../24-SIYUAN-PARITY-PLAN.zh-CN.md)；[机器结果](result.json)。状态为 **partial / fullProductAcceptance: not-complete**。

- Rust 7、本机 Flutter 14、隔离环境 helper 2、完整能力门 helper 3 项回归通过；analyzer 无问题。
- `browser-regression/`：本批重新运行原完整 F2 执行器，含 native 16 步回归、Web 12 步执行器、实际页面 7 组、整页重载 1 组、native 读回 3 组；原执行器 phase 名保留，不冒充旧 F2 历史证据。两张 Web PNG 来自实际浏览器页面。
- `macos/`：最终原生 App 的 8 组检查，含真实块类型菜单连续转换、原始资源 SDK/CAS/重开与另一认证成员更新；截图是实际运行界面。
- `ios/`：最终主流程 8 组、新 App 进程 3 组，核对同一 objectId，保留代码多行精确文本；经过原 AppFlowy-Cloud 的第二账号修改可见。键盘连接存在，但该次外接键盘模式下 `imeHeight=0`，不将其认证为软键盘视觉或人工中文 IME。
- 完整能力台账结构检查通过；`--require-complete` 返回 1 是预期拒绝，50 项全量编辑/协作门尚未达成。Android 按用户要求未安装/运行。

原始 UTC run ID 保留，部分为 20261105；本地时间为 11-06。隔离 Cloud 和依赖的可用性已恢复，旧 M3-A 环境阻断记录不改写。

`source-lock.json` 是本批归档时的源码输入指纹，不是已提交 Git revision。浏览器回归保留自己的运行 source-lock；最终桌面菜单的状态/焦点修复晚于该浏览器 bundle，由最终 macOS GUI 覆盖。iOS 完成于桌面专用菜单修复之前，共用内核、代码 renderer 与 Mobile 操作代码没有后改。

从 `smart_document` 目录验证：

```sh
python3 ../docs/smart-document/v1/scripts/verify_phase4_evidence.py
python3 ../docs/smart-document/v1/scripts/verify_phase4_evidence.py --source
python3 scripts/verify_parity.py
```

证据目录只包含合成账号生成的文档、日志、回执、源码指纹和截图；凭据/defines、可执行包、私有 WPS 手机参考图不归档。新一批修改源码后，`--source` 应指出版本变化；默认仍能验证本批历史工件的完整性。
