# Mobile M3-A 执行证据

目标输入 [SD-MOB-1.3](../../22-MOBILE-DESIGN-REVIEW.zh-CN.md)，实际范围见 [实施报告](../../23-MOBILE-IMPLEMENTATION.zh-CN.md)。状态 **partial**，本机切片通过，Cloud 门未完成。

- [汇总](result.json) / [iOS 两个进程回执](ios-local-result.json)：同一 objectId，精确 Unicode/样式/列表/对齐恢复；最终批次要求真实软键盘可见。
- [编辑集成日志](mobile_document_test.dart.log) / [新进程重开日志](mobile_reopen_test.dart.log)。自动 TextInputClient 回调不代表人工中文候选认证。
- [8 项原生回归](mobile-native-final-tests.log)、[analyze](mobile-final-analyze.log)、[真实 Chrome WASM/IndexedDB](mobile-web-regression-final.log)。
- [Cloud preflight 失败](cloud-preflight-result.json)，不以本机模式替代协作成功。
- [Android 构建日志](mobile-apk-build-arm64.log) 是之前的构建证据，早于最终增量适配修复；Android 安装/运行已按用户指令取消，独立测试包已移除，不把旧 APK 作为当前已验收产物。
- ios-*.png 是 Simulator 运行产品截图，内容为合成数据；WPS 私人文档参考截图不进入归档。

`source-lock.json` 标记本轮代码输入的 SHA-256；`manifest.json` 标记本目录产物。测试账号/defines、安装包、App 沙箱、原始 WPS 屏幕和全局缓存不归档。工作区尚未提交，不把已有 commit hash 冒充本轮改动已提交。

只读校验：在 v1 目录执行 `python3 scripts/verify_mobile_evidence.py`；加 `--source` 可对比当前工作区输入摘要。最后 Aa 按钮的 padding/圆角/单行文字为纯视觉修整，已重新编译、analyze 与实际截图检查；功能回执保留原执行结果。
