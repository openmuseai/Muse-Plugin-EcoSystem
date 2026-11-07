# P25：复用原 AppFlowy 数学公式编辑器（实施中）

承接 [P24 单选分组看板](47-PHASE24-SINGLE-SELECT-BOARD.zh-CN.md)，继续推进思源基础编辑对齐。公式采用固定 AppFlowy 客户端已有的 math_equation 块、formula 字符串和 flutter_math_fork 0.7.3 渲染器。保留原 TeX 引擎、布局与字体，不新建数学排版引擎或以 WebView 承载正文。

## 产品与交互

Desktop / Web 插入菜单、Mobile 原插入功能区增加“公式”。输入 LaTeX 源时显示原 Flutter 渲染器预览；应用后插入原公式块，点击该块再次编辑。新建公式在应用前只属于草稿，不先写空块。沿用现有文档框架、协作成员、保存状态、撤销/重做与跨端编辑布局。

公式源弹窗支持多行、预览、取消、应用；已有公式提供删除，原作者撤销可恢复同一块。公式源草稿固定对象与块 ID，提交前验证原值摘要；远端改动或删除后拒绝旧草稿，保留输入与焦点。只读时可以查看源，不能应用或删除；访问撤销后源输入与预览从弹窗隐藏。弹窗期间编辑器全局快捷键不应截获输入框的局部撤销。

## 领域与存储

公式字符串仍保存在原 Block.data.formula，不增加平行 Y.Text，也不把渲染结果写入 CRDT。插入依据稳定前序块地址提交时重新解析；更新与删除按稳定块 ID 定位。原 Document 事务、Yrs、作者撤销、Cloud 与检查点继续共用。读取不迁移，不丢弃已观察到的未知元数据。

同一公式是原属性寄存器的替换语义；本地摘要只防止覆盖已观察到的远端变更，不是跨端全局 CAS，也不等于字符级 TeX 协作。不同公式块、公式与独立正文的并发需要保持。原远端对象通道仍为 Document0，不增加新的 CollabType。

## 原实现与 Flutter 适配

原客户端锁定 flutter_math_fork 0.7.3，原公开包 SHA-256 为 284bab89b2fbf1bc3a0baf13d011c1dd324d004e35d177626b77f2fc056366ac。源码与 KaTeX 字体许可完整保留，381 个原文件逐一记录摘要。原包在当前 SDK 编译失败，原基线 LayoutBuilder 缺少新的布局回调 mixin，且仍调用已移除的 rebuildIfNecessary。

项目内副本只修改一个文件：接入 RenderObjectWithLayoutCallbackMixin 并于 performLayout 调用 runLayoutCallback，补丁可逆到完整原包。没有修改全局 pub 缓存或原 AppFlowy 仓库。适配依据：[Flutter 官方 mixin](https://api.flutter.dev/flutter/rendering/RenderObjectWithLayoutCallbackMixin-mixin.html)、[官方回调约束](https://api.flutter.dev/flutter/widgets/RenderAbstractLayoutBuilderMixin/runLayoutCallback.html)。固定思源 mathRender 与安全策略作为行为参考，Flutter 不执行其 HTML 或动态脚本。

新输入限定 8192 UTF-8 字节；已存原公式允许更大的有界源并保留。当前渲染配置限制嵌套、命令数量和宏展开，链接/HTML、定义宏及未限定尺寸命令不直接渲染；无法解析或超过渲染范围时显示原文保留提示，用户仍可打开源。渲染能力限制不通过清空公式解决。

## 验收顺序与剩余范围

先验证原公式 schema、失败事务原子性、稳定插入地址、未知元数据、公式/正文真正并发、作者撤销和重开。随后验证三种宽度下插入/源编辑/预览、过期草稿、删除恢复、局部键盘历史、只读与访问撤销。再进入 macOS / iOS 公共资源宿主、Web 两账号同一原生对象、离线重开及服务重启回读。

行内公式、完整 KaTeX/mhchem、用户宏、$$ 快捷输入、Markdown 双向格式桥、公式内字符级协作与全部复制/无障碍尚未由本轮交付。完整产品与协作总门保持 NOT COMPLETE。Android 按用户要求不安装。

## 验收环境记录

当前完整测试命令发现旧 `media_web_readback_test` 依赖原 fixture 中此前通过真实浏览器文件选择器上传的特定图片；当前 fixture 已无该图片，旧探针在查找标记图片时失败。该结果保留诊断，未记作通过。探针增加明确手动验收标签，仍保留全部断言与默认独立执行行为。常规文档回归用 `flutter test --exclude-tags=manual-browser-filepicker`，该探针必须先对同一个 fixture 完成真实文件选择上传，再单独运行。

## 2026-11-07 进度评审补记

截至本次盘点：Document Rust 31 项、常规文档回归 51 项通过；macOS / iOS 模拟器各 9 项真实 UI + 3 项独立进程重开通过。原数学库 381 个源文件、原包校验和与一个可逆兼容补丁核对通过。Web 源码已写入，静态分析仍有 6 项风格提示；尚未进行本轮浏览器同一对象端到端操作、离线与 Cloud 重启回读，尚未冻结 P25 执行档案。状态保持“待完成验证”，不能记为已验收切片。后续入口见 [更新开发计划](50-REVISED-DEVELOPMENT-PLAN.zh-CN.md) 的 SDR-01。
