# Spreadsheet 产品壳方案

相邻的 `plugins/spreadsheet/gridcraft/` 是独立的 GridCraft 源码副本，**不是**可热安装的产品包，也不应直接把其 egui UI 嵌入 OpenMuse。本目录是可签名、可离线安装的 Spreadsheet 产品资源包，采用和 Word、PDF 一致的分层：

- `ioffice/vendors/gridcraft`：首版唯一工作簿模型、公式计算、XLSX 读写与命令引擎来源；通过 Host 随包发布的版本化 Rust 桥接层提供能力。
- `ioffice` 的 Flutter `spreadsheet_editor`：同一源码负责网格绘制、编辑、公式栏、行列标题、选区、触控、输入法和工作表标签；编译进各端 Host。
- 本目录的 `spreadsheet-product` 签名资源包：声明 GenOffice 风格的 Ribbon、菜单、主题与功能开关；首版已可离线安装和启用，图标/快捷键/模板仍按计划补齐。
- `Muse-Client` Host：安装验签、文件授权、窗口/标签页、保存提交、内核槽位与兼容性校验。

`ioffice/libs/ss-core` 将在能够通过同一桥接合同打开、编辑、计算和保存真实工作簿后替换 GridCraft 适配器。当前该 crate 没有 `src/`，不能把它标为已接入能力。

详细设计见 [架构与边界](docs/01-ARCHITECTURE.zh-CN.md)、[GenOffice 壳清单](docs/02-GENOFFICE-CHROME-INVENTORY.zh-CN.md) 和 [开发与验收计划](docs/03-DEVELOPMENT-PLAN.zh-CN.md)。

第一至十八轮记录见 [开发与验收计划](docs/03-DEVELOPMENT-PLAN.zh-CN.md)。当前 `0.1.18` 的 GenOffice 弹窗模糊、顶底状态消息、同工作簿视觉差异及双端构建见 [第十九轮证据](docs/22-ROUND-19-MODAL-STATUS-VISUAL-AND-BUILD.zh-CN.md)。在同一工作区运行 `bash Muse-Client/scripts/spreadsheet-product-e2e.sh all` 可重新生成签名产品包、构建 macOS/Android 内核和 Host、运行真实 XLSX 测试并输出截图与哈希报告。
