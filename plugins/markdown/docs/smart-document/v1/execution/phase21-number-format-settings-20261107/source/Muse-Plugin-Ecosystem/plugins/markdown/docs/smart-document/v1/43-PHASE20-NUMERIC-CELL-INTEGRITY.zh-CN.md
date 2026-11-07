# P20：数字字段的精度与无损编辑（切片已验收）

承接 [P19](42-PHASE19-DOCUMENT-OUTLINE.zh-CN.md) 与 [数据库适配设计](29-DATABASE-ADAPTER-DESIGN.zh-CN.md)，继续思源 number 字段对齐。本轮覆盖数字值边界与真实编辑链路，不据此宣称 18 种字段或全部数字格式已完成。

## 复用与语义

继续使用原 AppFlowy Database/Row、NumberCellData、NumberTypeOption 和类型 reader/writer。固定思源 kernel/av/value.go 区分 Content、IsNotEmpty、Format、FormattedContent 的设计：数字值与显示文本分开，不将格式化结果回写为真值。保留 Decimal 字符串精度，编辑过程不经过 Dart/JavaScript double。

当前原 AppFlowy formatter 会提取部分数字，并可能对货币做显示舍入；直接用显示文本预填编辑框会破坏原精度。本轮新增只读查询字段提供原始编辑文本和未解析状态，原单元格存储仍为 type 1 / data 字符串。数值读取、原格式显示、筛选、排序继续使用原内核。

新写入在原 writer 前验证完整数字语法及既有 Decimal 精度/范围，支持小数、符号、科学计数和清空，拒绝 NaN/Infinity、非法尾部、超出精度/范围值。空值与零分开。旧原值和未知格式保持原编码；无法无损解释时不能自动“修复”为截断数字或空白。

## 交互与关注点

原 Grid/记录详情/内嵌资源共用数字编辑入口和原对话框布局，Mobile 继续使用数字键盘与至少 44px 的取消/应用入口。输入框取原值；显示舍入不改变编辑精度。没有修改时关闭对话框，不产生单元格写入或正文/数据库历史。非法输入留在当前草稿中并提示，原记录不变。

应用时携带原单元格与字段摘要作为本地过期草稿保护；并发改变后不能静默覆盖旧草稿。该保护不是跨客户端全局 CAS。原 Row 继续拥有值，DatasetRoot 拥有字段定义；文档仅保留原资源引用，协作契约和传输不引入数字专用协议。

## 验收计划

先用原数字格式样本复现显示值回写丢精度与非法输入隐藏问题；覆盖极值、零/空、28 位小数、科学计数、原字段未知配置及未知原值保留。随后执行真实 Cloud 双用户字段/行同步、草稿冲突、原作者撤销、离线重开与同对象 Native/Web 读回，检查原始 data 字符串。macOS / iOS 模拟器 / Web 通过后再冻结本轮证据；Android 延续不安装要求。

思源百分比倍率、各地区货币/千分位外观、全部格式设置及旧数据显式转换仍需各自建立语料映射，不能只因原 AppFlowy 存在同名枚举就认定等价。本轮不改变这些尚未对齐的语义。


## 源码映射与受控适配

八份原始源码/许可证固定在 smart_document/vendor/number_reference，包含思源的 value.go、attributeValue.ts、cell.ts、cellValue.ts，以及 AppFlowy 的 NumberTypeOption changeset 与 number cell bloc。思源的界面将未格式化 content 放在 data-content，再填入 number input；本轮沿用这种数值/显示/草稿分离。

思源原 Content 使用 float64，前端为 JS number；本轮以原 AppFlowy 的数字字符串与既有 Decimal 提供更精确的边界，不复制浮点精度损失。原 AppFlowy writer 允许任意字符串，其 formatter 可提取部分数字；本轮新增完整语法检查并保留无效草稿，属于明确的输入保护适配。旧未知原值保持原编码，不自动清空或取前缀。

本轮 SDK 增加原 NumberTypeOption 格式配置适配命令，带字段摘要且仅修改原 format/symbol，保留其他选项与单元格。它用于原格式兼容与协作样本，不代表完整格式设置 UI 已开放，也不代表思源百分比倍率和所有地区货币外观已对齐。

真实 macOS 验收还发现提交失败后控件重新启用时输入焦点未恢复，后续编辑仍可能提交旧草稿。现为原 TextField 明确管理 FocusNode，并在错误后的下一帧恢复焦点；测试通过真实点击和输入重验。它只影响界面草稿，不改变原 Row 或协作协议。

## 实际验收与设计关联

继续沿用冻结的 Grid、单元格对话框和 Mobile 编辑布局；新增错误文案在输入框下方呈现，不把技术错误码暴露给产品用户。[实际交互与视觉稿](number-functional-review/index.html) 展示原值编辑、非法草稿、远端单元格冲突、远端格式冲突和离线重开。右侧英文检查面板属于测试夹具，不进入产品界面。

Dataset Rust 56 项、Dataset Flutter 54 项、公开 Dataset SDK 3 项通过；三个宽度 320/430/1100 的数字交互测试包含在 54 项内。Dataset、示例和 Web 静态分析通过。macOS、iOS 模拟器各通过 8 项真实 UI 检查和 3 项独立进程重开；Web 主端 9 项、协作端 5 项、离线重开 5 项，随后重启本任务独占 Cloud 服务，Native 对同一 Document / Dataset / Row 执行 4 项落库回读检查。

真实输入包括 `9007199254740993.123456789`、`-1.25e-2` 和最终 `12345678901234567890.12345678`。后者在 Row4 中仍为原字符串，超出 JavaScript 安全整数的部分未丢失。Alice 打开旧草稿后，Bob 分别修改行值和根字段格式，Alice 的应用被拒绝，旧草稿保留，远端值不被覆盖；这仍是本地摘要检查，并非分布式原子 CAS。原作者撤销、零与空值、未知格式与未知旧原值保留均有单独检查。

固定 Decimal 的本轮科学计数配置要求尾数能被其精确解析，指数结果也必须落在既有范围内；没有宣称支持任意精度科学计算。原 AppFlowy 超长货币文本的千分位分组在真实 Web 截图中仍有差异，显示舍入与地区格式也尚未完成思源对齐。本轮选择保留原 formatter，并将原始输入与之分离；后续应以 SiYuan 数字格式样本建立独立显示映射，不能把这个差异隐藏在已通过的无损存储验收中。

早期非法输入基线失败与 Native 焦点失败保留为诊断，不计作通过。本轮 Cloud 二进制沿用 P19 的原 Yrs GC 删除尾部修复；未增加数字协作协议、未引入新 CRDT。证据冻结于 [P20 执行目录](execution/phase20-numeric-integrity-20261107/result.json)，提供清单、源码输入快照和复验脚本。

本轮不关闭完整产品门：18 种字段、全部数据库视图与绑定、完整格式 UI、文本单元格字符级协作、生产资源会话与权限、完整共享/评论/历史、持久 ACK/outbox、Agent/Office 以及 Android 等仍有独立缺口。Android 依用户要求未安装，实体键盘/中文 IME 和真实手机软键盘几何也未以模拟器替代认证。
