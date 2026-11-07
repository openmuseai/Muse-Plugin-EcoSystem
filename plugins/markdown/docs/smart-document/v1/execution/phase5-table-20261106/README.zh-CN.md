# P5-A 表格执行证据

2026-11-06 Asia/Shanghai。主报告：[26](../../26-PHASE5-TABLE-IMPLEMENTATION.zh-CN.md)。[结果](result.json) 为 **partial / fullProductAcceptance: not-complete**；只覆盖固定网格表格切片。

- Rust 10 项、本机 Flutter 17 项通过；包括同格/异格并发、原子拒绝坏网格、origin undo、稳定地址插入、文件重开及布局不写内容。Python 5 项基础设施/完整门辅助测试通过。
- `macos/` 与 `ios/` 各为主流程 6 组 + 第二个独立进程 4 组。实际菜单、真实 rich text、平台输入连接、工具栏、原 Cloud 两个认证用户和 SDK 资源检查点均接通。新进程仅传同一 run，不传 Cloud 凭据，核对同一资源、表格/文字身份和精确文本。
- 最终指针测试将命中警告视为失败；点击前清掉插入光标并等待 Mobile 选择控件的后续布局。`regressions/` 保留此前没有等待该布局帧时的实际失败，和最终成功记录分开。
- `web-regression/` 重新运行原完整 native/Web 执行器：12 步、Web 页面 8 组、整页重载 2 组、native 读回 4 组。重载前将预期 table/cell/text block/external Y.Text ID 和精确 delta 存在独立测试 IndexedDB namespace，重载后逐项比对。测试证明 Cloud 未配置时从本地恢复；不证明浏览器驱逐或断电耐久。
- Web PNG 是最终实际页面；Apple PNG 是实际运行 App 的 surface。截图前关闭键盘，Apple 回执中该字段表示截图时状态，不能解释为输入过程的软键盘几何认证。人工中文候选、物理 iPhone、完整无障碍与性能专项未认证。Android 按用户要求未安装/运行。

`source-lock.json` 是归档时工作区输入指纹，不是已提交 Git revision。最终 Mac 表格验证后，测试等待条件为 iOS 的后续选择布局帧做了加强，运行产品代码未再改变；iOS 和最终完整 Web/native 回归使用加强后的测试输入。Web 执行器的独立运行锁同时保留。

历史 SD-BL/SD-F1/SD-MOB 快照、F1/F2/P4 回执保持不变。协作仍是原 full-sync；在线成员/光标、耐久 ACK、私有评论/@、分享/历史、完整撤权以及所有写入口的服务端领域校验未由本批实现。

在 `smart_document` 验证：

```sh
python3 ../docs/smart-document/v1/scripts/verify_table_evidence.py
python3 ../docs/smart-document/v1/scripts/verify_table_evidence.py --source
python3 scripts/verify_parity.py
python3 scripts/verify_parity.py --require-complete
```

最后一个命令预期返回非零。凭据、私有 defines、带凭据的测试可执行包和 WPS 私有参考图片均不归档；只保留合成文档、日志、截图和校验清单。
