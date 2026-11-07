# 第一阶段开发计划与工程冻结：原 AppFlowy 协作链路

2026-11-05。产品输入：[SD-BL-1.2-20261105](13-FROZEN-BASELINE.zh-CN.md)。阶段方案 ID：**SD-F1-20261105**。本文件与 [14 技术方案](14-ENGINEERING-DESIGN.zh-CN.md)、[15 总执行计划](15-EXECUTION-PLAN.zh-CN.md) 形成阶段工程输入；归档入口见 `baselines/sd-f1-20261105/BASELINE.zh-CN.md`。

## 1. 阶段目标与完成边界

第一阶段交付一个真实可运行的纵向增量：**共享资源创建器 → 智能文档插件 → Flutter/AppFlowy Editor → 原 AppFlowy Collab/Yrs → 本机保存 → Muse AppFlowy-Cloud → 第二账号 → 资源检查点与重开**。

当前验证目标是 macOS 原生及真实双账号 Cloud；不将这一增量称为全部 G0 或完整 0.1 发布。Web/Mobile 实际产物、完整输入法、Office/数据集/Agent/评论/历史产品功能继续按 T03.d–j/T08–19 和 AC 台账实施。本阶段不默认开启生产 Host，也不改动现有用户数据或思源工作空间。

## 2. 固定技术输入

| 项目 | 第一阶段采用值 / 决议 |
| --- | --- |
| Collab | 复用当前 Cloud 固定 revision `e59260e524f33104b0ddcd6bb8f6218cad0f7e18`，不引入新的协作服务器/合并算法 |
| Yrs | 实际解析 0.23.5；由 Cargo.lock 固定，不以客户端旧 path 声明代替可构建源码 |
| Flutter Editor | `470c4e77c71b63f693ce0923a927afcd667d6f3b` / 5.2.0 运行时源码子集；补 Flutter 输入回调、可注入领域 undo、intl 范围兼容，保留原始许可与 patch |
| 传输 | 复用 Cloud 已有认证 HTTP full-sync/protobuf 接口；固定轮询交换，**未实现 WS 实时推送/awareness** |
| 状态权威 | Rust `collab_document::Document`；Flutter node 是投影；文本更新按原 editor 适配思路计算增量 |
| 本机保存 | 原子替换、写入 flush、私有账号/资源隔离路径；资源中心 CAS 仅作检查点，不充当协作协议 |
| undo | 使用原 Collab/Yrs 的本地 origin 栈；远端更新采用独立 origin，不重放旧整段快照 |
| Native 产物 | Dart build hook 编译并随应用捆绑 Rust 动态库；无需依赖测试环境里的库路径变量 |
| 文件/对象 | 阶段格式 `muse.smart-document/phase1`、`.musedoc`；文件含 objectId/docState，不含 Cloud token/用户凭据 |
| Cloud fixture | 独立 Compose project、独立卷、15432/16379/19999/19000/18000 回环端口；镜像以 digest 固定 |

使用 Cloud 的已有 git 固定版本解决新模块的可构建来源；未修补/替换旧完整客户端的 vendor path，也没有将完整 AppFlowy 应用整体接入。原来的 `.sy/.sydoc` 路径保持独立。

## 3. 开发批次与退出条件

| 批次 | 对应总任务 | 第一阶段具体交付 | 退出条件 |
| --- | --- | --- | --- |
| F1-01 基线/构建 | T01/T02 | 产品/设计校验，阶段方案归档，源/版本/锁/许可来源 | 从固定来源编译原 Collab，不依赖私改缓存 |
| F1-02 正文领域 | T03.a/T05 切片 | 块、文本/marks、UTF-16、候选校验、稳定 ID、undo/redo、FFI | 并发/回滚/重开/错误范围测试通过 |
| F1-03 Flutter 编辑 | T03.a/T08 切片 | 事务到领域增量、格式工具、受支持 slash/插入、远端投影 | UI 修改进入 Rust，本机状态与错误可信 |
| F1-04 本机与资源 | T03.c/T04/T07 切片 | 私有快照、保存错误恢复、资源 creator/handler/context、关闭屏障/CAS 检查点 | 保存重开不丢字，不同资源/账号隔离，不绕过 SDK |
| F1-05 Cloud | T03.b/T06 切片 | 原 full-sync 接口、两账号工作区、离线合并、非成员拒绝 | 真网络、真 DB/Redis、语义收敛与服务重启通过 |
| F1-06 原生端到端 | T20/T21/T22 切片 | 实际 Flutter macOS 程序及共享 SDK workbench | 创建/输入/格式/远端更新/检查点/重开，全程真实产物 |

这些是总任务的已执行切片，不能将 T05/T06/T08 等整项标为完成。通用协作 package/版本化公开合同的发布仍待后续工程门；第一阶段 port 独立于 UI/AST，但暂在同一内容 package 内，不先建设空的跨领域引擎。

## 4. 代码归属

* `plugins/markdown/smart_document/rust`：薄领域包装、原 Collab/Yrs、FFI、同步 wire 编解码与结构校验。
* `plugins/markdown/smart_document/flutter`：领域控制器、存储/协作 port、原 Cloud adapter、Flutter 编辑面与 native build hook。
* `plugins/markdown/smart_document/vendor/appflowy_editor`：固定 revision 的运行时子集；补丁及原始来源清单随源码记录。
* `Muse-Client/plugins/smart-document`：公开 SDK creator/handler/context 与受限资源会话；不向 Host 写内容类型分支。
* `smart_document/flutter/example`：使用现有 ResourceCenterHub/LocalResourceProvider 的真实 SDK workbench 验证宿主；与用户生产 Host 发布装配分开。
* `Muse-Server/AppFlowy-Cloud`：full-sync 入口写权限/路由校验、删除集合同步修复；不升级协作协议或替换存储。

## 5. 端到端验收口径

| 证据组 | 通过条件 | 不计入的能力 |
| --- | --- | --- |
| 原生领域测试 | 中文/emoji 并发、marks、原子失败、ID 重开、非法范围拒绝、来源 undo | 任意复杂树/完整表格/大规模性能 |
| Flutter 存储/角色 | 真实 FFI/真实文件重开、只读、保存故障恢复 | 服务器 Commenter 权限、设备崩溃/断电认证 |
| 双账号 Cloud | 两个注册账号、同一工作区、原接口、离线合并、undo、块增删、非成员读写拒绝、进程重启 | WebSocket/presence、跨区域多实例、完整 G0-G |
| macOS 原生 | 真 app、原生粘贴快捷键、选区工具、远端投影、共享 SDK/CAS、资源重开、截图 | 人工中文 IME 认证、生产 Host 全量发行、Mobile/Web |

测试中的 synthetic 用户和数据独立于既有 Muse 环境；邀请明确 `skip_email_send=true`，不发邮件。单元测试框架的 HTTP mock 必须显式关闭，Cloud 测试不能在无服务时 skip 后宣告通过。

第一阶段回执只显示“协作服务已接收”，不冒充云端耐久 ACK。服务重启恢复是单独验证证据，不据此宣称每次交换都具备 durable receipt。性能目标仍沿用 PRD，尚未作固定口径测量。

## 6. 发布/回退与后续

第一阶段保持实验入口，未默认装配到生产 Host；mobile/Web 未具备对应产物时必须明确不可用。新数据只进入新对象/私有目录，不自动迁移旧知识库。网络服务可暂停而本机编辑继续；读取权限拒绝后停止共享写入。

后续顺序：完善共享合同与 WS provider、Mobile/Web 原型门 → 三端编辑/存储/可访问 → 评论/历史/Agent → 真 Office/数据集/扩展；每步复用当前已验证的领域/资源边界。完整排期仍为 [15](15-EXECUTION-PLAN.zh-CN.md) 的受控区间，不能用本轮小闭环替代全量交付估算。

实际命令、产物、结果和限制写入[第一阶段验收报告](17-PHASE1-ACCEPTANCE.zh-CN.md)及 `execution/phase1-20261105/`，不覆盖既有冻结快照。
