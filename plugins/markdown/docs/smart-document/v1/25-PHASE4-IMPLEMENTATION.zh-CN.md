# P4 实施：稳定块编辑、代码块与三端 Cloud 回归

2026-11-06（Asia/Shanghai；原始日志部分 UTC 时间为 11-05）。变更输入为 [CR-SD-PARITY-20261106](24-SIYUAN-PARITY-PLAN.zh-CN.md)，沿用既有冻结方案和 Mobile 视觉稿。本批完成 P4-A 与 P4-B 的有限切片，**不等于思源编辑全量一致或完整协作已交付**。机器结果见 [P4 结果](execution/phase4-20261106/result.json)，后续范围见 [50 项功能台账](siyuan-collaboration-parity.json)。

## 已落地行为

### 稳定块身份与类型命令

新增 `DocumentBlockReference {objectId, blockId}` 与控制器按 ID 解析/批量转换接口。它是智能文档领域地址，不是全平台唯一内容模型，也不携带授权。菜单打开时捕获目标 ID，执行时重新查找；前面插入兄弟块后仍修改原目标。跨对象地址、已删除目标和空选区明确失败，不回落到“当前位置”。

Rust `set_type` 在原 AppFlowy document 的同一个 block Y.Map 中更新 `ty/data`，保持 block ID、children ID、external Y.Text ID、文字、marks 和无关属性。支持正文、H1–H6、无序/有序/待办、引用和代码；标题级别严格校验，切出标题/待办清理旧类型属性，同类型待办保留完成状态。整批先在候选状态校验，再一次提交；使用原 AppFlowy origin 撤销边界。

Mobile 的 Aa/列表类型操作与 Desktop/Web 块类型菜单共用该命令。桌面实际测试暴露的两个问题一并修复：菜单重建不能丢失捕获目标；弹出菜单不抢走正文焦点，转换后能继续切换类型。选区路径按仍存在的块 ID 重定位，类型转换不改变文字偏移。

这不是通用树移动完成声明：旧缩进/拖拽/部分上游快捷键仍可能采用 delete/insert。并发移动的单父、无环和删除目标冲突需在下一批单独解决。当前块引用也尚未提供用户可见的引用/反链产品。

### Markdown 与代码编辑

三端共用字符快捷处理：`#`–`######` 加空格、无序列表、数字列表、引用、待办，以及三反引号加可选语言标签后换行。前缀删除、类型和相关属性在同一内核批次中提交，一次撤销恢复输入前状态。数字列表前缀当前限制六位；语言标签当前匹配字母/数字/下划线/加减号，不宣称覆盖所有语言名称。

代码块采用真实 AppFlowy rich text 编辑组件和等宽字体，不再只保存一个无法编辑的 code 节点。代码内部 Markdown 快捷转换关闭，换行和 `#` 保留字面内容。iOS 通过实际输入连接回调写入 `print("智能文档😀")`、换行和 `# literal`，新进程精确读回。语法高亮、语言选择器、复制和退出代码块的完整交互仍未实现。

同一 renderer registry 还替换了上游只显示叶节点的标题 renderer：段落转换为标题后，其既有嵌套子内容继续显示。当前 registry 是内置 Flutter 组件表，尚未完成第三方元素协议或任意插件动态扩展。

### 投影与跨布局修复

远端/领域更新仍投影到同一个 EditorState，不替换整个编辑器。删除旧节点后再插入新类型时，最终索引不能被事务路径变换再次计算，否则会把中间块错误放到文首。兄弟顺序变化时先处理该层重建，再递归；避免目标子对象被前一步递归复用后从目标父节点脱离。

界面阅读态与实际写权限分别判断。Mobile 阅读态暂时关闭编辑器输入，切换到 Desktop 尺寸后仍按真实权限恢复编辑；真实只读/撤权/内容失败不会借布局切换绕过限制。

## 原 Cloud 与协作边界

本次恢复的是 `muse-smart-document-stage1` 隔离 Compose 项目及登记 PID 的本地 AppFlowy-Cloud，没有重置业务数据或操作其他项目。`dev_stack.py start` 现在检查 auth、Postgres、Redis、storage 和 Cloud，不能仅凭 Cloud `/health` 为 200 就提前返回。已有 Cloud 进程必须与登记的可执行文件匹配；未登记的端口占用在修改容器前拒绝。

传输仍是既有 `appflowy.full-sync/1` + `yrs.update-v1`。本轮未新增服务器、修改 wire 或把协作绑定到思源 AST。沿用既有 full-sync 入队前 ACL 与删除集合修复。双账号 HTTP 同步、原始越权拒绝与离线恢复已验证，**没有实现 WS 在线光标、耐久 ACK、完整分享/评论/历史/Agent**。UI“服务已接收”继续只表达当前 exchange 成功。

此前 [M3-A 报告](23-MOBILE-IMPLEMENTATION.zh-CN.md) 中 Cloud 环境阻断属真实历史。本批环境恢复后重新运行通过，保存为新证据，不改写旧归档。

## 实际验证

| 层级 | 实际结果 | 适用边界 |
| --- | --- | --- |
| Rust | 7 项通过 | 类型保留所有身份/marks/children，错误批次原子性，类型与另一成员文字并发收敛、撤销保留对方文字 |
| Flutter 本机 | 14 项通过：controller 8、Markdown/code 2、Mobile 3、响应式布局 1 | 捕获目标/兄弟插入、标题子内容显示、代码字面换行、文件恢复、四宽度、响应式权限；菜单连续转换由真实 macOS GUI 覆盖 |
| 隔离环境 helper | 2 项通过 | Cloud 已存活仍恢复依赖；未登记 listener 不被复用 |
| 完整 native/Web 回归 | 原 native 16 步 + Web 执行器 12 步通过 | 真 WASM/IndexedDB，原 Cloud，原始非法写，不跳过失败步骤 |
| 浏览器实际页面 | 7 组 Cloud/编辑检查 + 1 组整页重载通过；native 读回 3 组 | 双成员 Unicode/marks、离线/幂等、origin undo、稳定新增块、越权、IndexedDB 完成；新 H6 核心持久化测试通过 |
| 最终 macOS GUI | 8 组检查通过 | 实际粘贴/选区加粗/类型菜单/第二账号/资源 CAS/重开；在修复菜单状态与焦点之后重跑 |
| 最终 iOS GUI | 主流程 8 组 + 新进程 3 组通过 | 真实模拟器 App、同一资源、代码 renderer、第二认证成员更新和新进程精确文本恢复 |
| 源码与冻结输入 | analyzer、固定上游 hash、三套既有冻结快照校验 | 历史冻结内容保持不变；本批新源码另做 SHA-256 清单 |
| 全量门 | `verify_parity.py --require-complete` **预期拒绝** | 50 项范围未全部实现/全平台通过，不将结构检查绿灯当作产品完成 |

iOS 本批 Cloud 测试时模拟器连接硬件键盘，回执为 `softKeyboardVisible=false`、`imeHeight=0`。这一结果只证明输入连接与编辑/协作/恢复链路，不能证明本批软键盘几何。此前 M3-A 有真实软键盘 335px 的独立证据；人工中文候选输入、物理 iPhone、后台长期挂起与完整辅助功能仍未认证。按用户“仅继续 iOS，暂不安装”要求，本批没有安装/运行 Android；其最终验收状态保留 unrun。

浏览器全量回归先于桌面菜单焦点最终修复；后者由最终 macOS GUI 覆盖，独立 widget 回归另覆盖响应式权限。归档保留两次运行各自 source-lock，不用最终源码 hash 冒充早期浏览器 bundle。Web 实际截图同样属于上述已运行 bundle。

## 复现与源码

在 `smart_document` 中运行（原有 Xcode/Flutter/Rust/Docker 依赖沿用）：

```sh
python3 scripts/dev_stack.py start
cargo test --manifest-path rust/Cargo.toml
python3 -m unittest discover -s scripts -p 'test_*.py'
python3 scripts/verify_phase2.py
python3 scripts/verify_mobile.py --device <明确选择的iOS设备ID>
python3 scripts/verify_parity.py
python3 scripts/verify_parity.py --require-complete
```

Web 执行器要求实际浏览器点击开始、收取回执及整页重载；没收齐会失败。Mobile 命令会向指定设备安装独立测试 App；目前只选择 iOS。凭据留在忽略的 0600 私有 defines 中，不进入证据包或发行物。

主要实现：`smart_document/rust/src/lib.rs`；`flutter/lib/src/{core_api,controller,editor_components,document_view,mobile_document_view}.dart`；新增 `editor_commands_test.dart`、`document_view_test.dart`；增强原生/iOS/浏览器实际测试。协作中立 package 和公开 SDK 依赖方向保持不变，生产 Host 装配本批仍未开启。

下一批按 [24 的 P5/P6 任务](24-SIYUAN-PARITY-PLAN.zh-CN.md#4-下一批的具体技术任务) 推进稳定树操作、表格/媒体模型与真实协作、在线状态/权限/annotation。50 项台账的“partial”不等于功能组已全部交付，也不按百分比掩盖重要缺口。
