# 第二阶段：Web 真核心与独立协作合同

2026-11-05，阶段 **SD-F2-20261105**。承接 [F1 原生闭环](17-PHASE1-ACCEPTANCE.zh-CN.md)，沿用 SD-BL-1.2 产品/设计与 SD-F1 工程输入；不覆盖任何冻结快照。当前文件定义阶段实现与验收边界，实际运行结果见 [19](19-WEB-COLLAB-ACCEPTANCE.zh-CN.md)。

## 1. 本轮增量与目标

选择 T02/T03.d 的可运行切片：同一内容核心在 native 与浏览器运行，Web 有实际本机保存能力，并能通过现有 Cloud 与 native 互读。协作端口从内容 package 中独立出来，开始验证“内容模型与协作传输解耦”。本轮不宣称 G0-A–G 全部完成，也不提前交付 Mobile、完整角色/Office/Agent 或 WS。

| 批次 | 实施内容 | 退出证据 |
| --- | --- | --- |
| F2-01 | 纯 Dart `muse_collab_contract`；中立 binding/二进制 provider；领域前置兼容检查 | 无 Flutter/内容 AST 依赖；合同正反例和错误绑定拒绝 |
| F2-02 | 同源 Rust 生成 `wasm32-unknown-unknown` 产物 | 真 WASM 二进制、固定 bindgen、来源/补丁/产物摘要 |
| F2-03 | Dart 条件适配、浏览器 loader 与 IndexedDB | 实际 Chrome 运行；事务完成才记保存；关闭重开/账号隔离 |
| F2-04 | Flutter Web workbench + 原 Cloud CORS | 不关闭浏览器安全；两个注册账号实际交换及越权拒绝 |
| F2-05 | native → Cloud → Web → Cloud → native | 同一 object/block ID、Unicode、marks、块结构与 undo 验证 |
| F2-06 | 整页重载 + native 回归 + 证据归档 | Web 无网络 provider 从 IndexedDB 恢复；F1 原生整条链路继续通过 |

## 2. 实际包边界

* `Muse-Client/packages/muse_collab_contract`：内部预览 `muse.collab.transport/0.1`。`CollaborationBinding` 表达 protocol/engine/encoding/schema/epoch；provider 只读写不透明字节，不定义段落、单元格或 Flutter 类型。
* `smart_document/flutter/lib/src/core_api.dart`：正文领域的固定 binding，保留为领域责任。控制器在触碰存储/网络前拒绝不兼容绑定；不通过更改 provider URL 偷换引擎或 epoch。
* `smart_document/flutter/lib/src/cloud_provider.dart`：同一个 `http` adapter 供 native/浏览器使用。当前 adapter 仅支持现有 Document profile，仍随内容实现维护；以后出现第二个真实领域消费者再收敛更通用的 Cloud adapter。
* `native_core_io.dart` / `wasm_core.dart`：仅装载方式不同，JSON 命令进入同一 Rust `Session/Document`，不是两套可写 AST。
* `store_io.dart` / `store_web.dart`：文件与 IndexedDB 适配同一 store port。IndexedDB 以账号/工作区/对象命名空间隔离；成功边界为 readwrite transaction complete，不以单次 put 成功代替。
* `flutter/web_example`：内容层浏览器验证宿主，复用同一 Flutter 控制器和编辑面。它没有绕过现有正式 Web Host，也不把未适配的 `muse_resource_center_io` 或 `dart:io` 塞进浏览器；正式 Web SDK/资源装配仍待后续。

独立 contract 已落地，不等于完整中立 runtime/公开 wire 协议已发布。会话权限与细粒度 scope、durable receipt、订阅/awareness、队列/背压及 provider/engine 迁移仍按 [09](09-COLLABORATION-PACKAGES.zh-CN.md) 实施。原 strict resource 合同不增加字段。

## 3. 固定上游的浏览器适配

继续使用 AppFlowy-Collab `e59260e524f33104b0ddcd6bb8f6218cad0f7e18` / Yrs 0.23.5。原版本的 collab 模块调用 `Awareness::new`、`undo::Options::default`，而 Yrs 在 wasm 上要求显式 clock，因此未经适配不能编译。

将该 revision 的 `collab` 运行时子集以 `git archive` 方式归档到 `vendor/appflowy_collab`，保留原许可、原文件哈希、补丁和来源。Cargo patch 只替代此 crate；`collab-document`/`collab-entity` 仍由同一固定 git revision 提供。两个改动文件为 workspace members 收敛及 clock 适配：wasm 注入 JS Date 毫秒时钟，native 继续调用原默认实现。没有修改全局 cargo 缓存、改 Yrs 编码或升级 Cloud 引擎。

wasm 同时明确开启 UUID/fastrand 的 JS 适配；浏览器 realm 必须获得独立 client ID，不能使用无 JS 支持的固定随机种子。native/Web 的 Cloud zstd 回包统一用固定 `ruzstd 0.9.0` 解码，避免 Web/移动构建依赖 C zstd 工具链；输出与窗口均设上限，协议仍是原 full-sync。

`wasm-bindgen 0.2.128` 与 CLI 精确匹配；构建脚本为生成的无模块 glue 增加命名空间全局导出，供 Dart interop 调用，避免与其他 Office/WASM provider 共用默认全局名。生成 JS/WASM 随应用 assets 分发，记录摘要；不是运行时从第三方 CDN 下载内核。

Dart 使用 [JS interop / package:web](https://dart.dev/interop/js-interop/package-web)，WASM glue 使用官方 [wasm-bindgen 部署模式](https://rustwasm.github.io/docs/wasm-bindgen/reference/deployment.html)，zstd 采用 [StreamingDecoder](https://docs.rs/ruzstd/0.9.0/ruzstd/decoding/struct.StreamingDecoder.html)。Flutter Web surface 当前编译为 JS，**Rust 内容核心为真 WASM**；两者不能混称 Dart2Wasm 全栈构建已通过。

## 4. 交互、身份与保存语义

正式产品继续以冻结 WPS 功能区/编辑区/协作为目标；本轮复用 F1 最小编辑面。只有验收 fixture 显示验证面板，正常本机 Web 模式不显示工程状态清单。

Web 仍分别显示本机保存与协作接受。IndexedDB transaction complete 是浏览器本机提交，不承诺浏览器存储不会被驱逐，也不等于硬件断电认证；Cloud exchange 仍不等于 durable ACK。HTTP 请求使用 Cloud 已允许的 `Device-Id` 头，保持原认证和 CORS 检查，不设置通配 Cloud origin 或关闭浏览器安全。

普通 Web 模式没有测试账号。只有隔离验收构建从忽略目录注入合成测试账号；产物只在回环地址审阅，不可作为正式公开发行物。资源内容/缓存不写 token，报告不归档定义文件或合成账号凭据。正式 Host 的共享身份和受限会话装配仍是后续工作。

本轮浏览器验收通过测试应用的按钮发起，验证操作由 Dart 控制器执行；另保留原生输入回归。它不是人工 CJK IME、OS 键鼠或复杂选区验收，不能据此填完 AC-02/17。

## 5. 运行与后续

从 `smart_document`：

```sh
python3 scripts/build_web_core.py
python3 scripts/verify_phase2.py
```

第二个命令运行合同、WASM、原生回归、native 种子和 Web 构建，然后打印审阅 URL。打开 `http://127.0.0.1:18080/` 点击“开始验证”；通过后进入 `?reopen=1` 再点验证，随后脚本执行 native 读回并归档。未操作、缺服务、缺回执或任一校验失败均不能记为通过。自动化代理使用浏览器控制接口完成这两个 UI 操作。

正常本机 Web 运行：先构建 WASM assets，再从 `flutter/web_example` 执行 `flutter run -d web-server --web-hostname=127.0.0.1 --web-port=18080`；该端口被验收服务器占用时应先停止本轮服务器，不抢占无关进程。普通模式不依赖 Cloud 或定义文件。

下一步仍为 T03.d–j：浏览器长文/输入/语义和存储故障矩阵；Mobile 原生产物；公共会话/权限、WS provider 和耐久回执；随后按 15 的 M1–M4 补正文、评论/历史/Agent、Office 与 Dataset。完整产品周期不因单个增量通过而缩短。

停止本轮浏览器审阅服务：从 `smart_document` 运行 `python3 scripts/stop_web_fixture.py`。脚本核对登记 PID 的实际命令，仅停止本任务服务器，保留 IndexedDB 与独立 Cloud；可加 `--dry-run` 先做只读检查。
