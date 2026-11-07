# 协作传输合同：内部预览 0.1

独立的纯 Dart package，不依赖 Flutter、文件系统、网络实现或内容 AST。智能文档 native/Web 共用它；独立 Word/Workbook 等可声明自己的 schema/engine，不需要成为智能文档子块。

当前只交付两个真实边界：

* `CollaborationBinding`：中立的 protocol/engine/encoding/schema/epoch 描述，带严格版本/字段解析和兼容判断。
* `CollaborationProvider`：读取不透明状态、显式初始化状态、交换字节和关闭。领域负责校验/合并，provider 不持有第二份可写正文。

`exchange` 成功只表示接受，不提供 durable ACK。公开会话权限、订阅/awareness、持久回执、迁移屏障和通用 runtime 尚未在这个预览实现；它不是完整的平台 wire 协议。现有 strict resource 合同没有增加字段。

首个真实消费者为 `Muse-Plugin-Ecosystem/plugins/markdown/smart_document/flutter`。AppFlowy adapter 仍在内容实现旁，当前仅支持 Document profile；没有把 Cloud 的 `collab_type=0` 冒充通用 Word/Workbook provider。契约中不定义任何段落/单元格类型。

运行 `dart analyze` 与 `dart test`。测试覆盖独立文档/工作簿绑定的表示、未知版本/字段拒绝，以及 engine/encoding/schema/protocol/epoch 的隐式切换拒绝；工作簿实例是合同 fixture，不代表已实现工作簿领域协作。
