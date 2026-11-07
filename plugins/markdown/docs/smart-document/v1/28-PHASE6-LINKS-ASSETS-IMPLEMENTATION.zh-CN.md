# P6：超链接、私有图片与可复用传输适配

2026-11-06，CR-SD-REUSE-20261106 的实施增量。延续 [复用与交付计划](27-SIYUAN-REUSE-AND-DELIVERY.zh-CN.md)，产品目标、Desktop/WPS 与 Mobile 冻结设计不缩减。**本批是增量，完整思源编辑和完整协作尚未完成。** 最终仍以 50 项台账及细项缺口为准。

## 实际复用与新增边界

| 层 | 运行实现 | 必要适配 |
| --- | --- | --- |
| 编辑与显示 | 固定 AppFlowy Editor 的 rich text、href、原 ImageBlockComponent/ResizableImage | 每会话链接打开端口；图片授权字节 resolver/wrapper；图片尺寸/源变化时更新已有组件状态，保留正在进行的拖拽 |
| 内容内核 | 固定 AppFlowy Document、Y.Text、Yrs StickyIndex、origin undo | UTF-16 合法边界、相对范围、链接命令；结构图片引用与按属性合并的元数据 |
| 资源 | 原 FileDocumentStore / IndexedDB 与 Cloud bucket storage | 独立 AssetRepository/cache；可重试上传草稿；对象级私有附件 API，阻断旧公开路径绕过 |
| 协作传输 | 原 Cloud collab read/create/full-sync | `Muse-Client/packages/muse_appflowy_transport` 纯 Dart package；传入 binding 与原 collabType，内容领域仍负责编码、校验和合并 |
| 公共合同 | `muse_collab_contract`、新增 `muse_asset_contract` | 不包含编辑器、文档 AST、权限凭据或本机路径；第三方内容插件可以独立接入 |

思源来源继续固定为 3.8.9 / `d3af9d5782082b379d45a69eedf4ebcfe8ba6889`。链接参考 `menus/protyle.ts` 与链接测试；图片参考 `imageResize.ts`、`imageTitleEditor.ts`、`imageActions.ts`。不把 `.sydoc` 旧插件能力记作本批成果，不接入第二份 Go 文件真源。

## 链接命令

`captureTextRange` 返回版本化 `{objectId,blockId,textId,start,end,text}`，其中 start/end 是原 Yrs 相对位置编码，不保存瞬时编辑器路径。`apply_link` 在原 Y.Text 上格式化 href；改变显示文字时检查当前锚定文字仍与捕获值一致，避免覆盖协作者修改。前方插入不会移动目标到另一段文字；跨文档、跨 Y.Text、已删除对象和 emoji 半个代理对均拒绝。

使用原 href 属性；网址允许明确 scheme 并拒绝脚本、data/file、控制字符及 URI 凭据。HTTP(S)/mailto/tel 可通过平台打开，muse/siyuan 需要注入资源插件解析器。对话框支持插入、编辑、移除、复制和打开；Desktop 工具栏与 Cmd/Ctrl-K，Mobile 既有 ＋ 面板共用命令。Markdown 入口仍须补齐逐项语料验收，不能据此宣称全部链接功能保真。

## 图片与持久化

图片是结构块，不分配 Y.Text，不把二进制塞进文档。`asset` 保存 `version/provider/scope/owner/key/mediaType/byteLength/sha256`；`url` 仅为 `muse-asset://owner/digest` 逻辑引用，授权地址和 token 留在 repository。当前格式为 PNG/JPEG/GIF/WebP，单文件 12 MiB，最长边 20000、总像素 4000 万。复用 image package 读取头信息限制分配，再使用 Flutter 跨端 codec 验证实际图片；不能在 Web 读取不支持的 ImageDescriptor.width。

流程为 **选择文件 → 校验 → 本机保存草稿 → 私有上传 → 保存回执 → 一次文档插入 → 清理草稿**。失败保留待处理状态，重试复用同一块 ID；清理失败后用户已撤销图片，重试不会使其复活。取消不删除远端 blob；历史保留与 GC 另行设计。当前忙碌态为不确定进度，尚无传输字节进度和进行中取消。

原 AppFlowy 块属性整体更新存在并发覆盖风险。图片扩展使用原 document.meta 中的平面 Y.Map 寄存器：`muse.image.v1:` 加 JSON `[blockId,property]`；title/alt/align 独立，width/height 为 size 原子对，asset/url 为 source 原子对。读出时投影回标准图片属性。说明与尺寸并发互不覆盖；同一属性遵循原 Yrs 收敛规则。原图片手势仅更新 width，适配层按当前比例更新 size 对。此扩展需随领域 binding 维护兼容策略，不能让不识别扩展的原客户端直接编辑它。

插入回执使用同一 metadata map 的 receipt 寄存器，记录插入负载 SHA-256。回执不进入人的撤销范围，以阻止草稿重放导致复活。正文、回执在同步核心调用中完成，返回后才执行本机快照持久化。

## 私有附件与旧路径隔离

`PUT/GET /api/file_storage/{workspace}/private/{object}/blob/{sha256}` 继续使用原 bucket storage、身份与访问控制服务。每次请求检查 workspace、对象、guest 权限，并从 SQL 校验 object 属于指定 workspace 且未删除。上传校验长度与摘要；GET 使用 private/no-store、attachment、nosniff。

私有对象占用保留 parent namespace。旧 v0/v1 下载、上传、删除、metadata、多段上传及公开列表不能绕过该 namespace。缓存默认重新请求远端权限，只在明确网络不可用且策略允许时使用已授权本机副本；403/404 不回退。授权撤销后的已下载本机副本不能被宣称可远程抹除。

## 设计与验收

沿用既有连续编辑区、Desktop 功能区、Mobile 八入口与 44px 点击目标。图片进入 ＋ 与现有图片入口，说明/alt/尺寸/对齐及删除进入块设置；链接共用原有文本上下文。没有新增另一套应用壳。数据库与评论/分享/历史仍按其独立任务推进，禁用状态不计作实现。

验收必须同时覆盖：实际控件点击、协作者在对话框打开期间修改、非法输入不提交、私有原始 HTTP 路由、并发属性、撤销与同资源无凭据新进程重开。截图需等实际解码帧，尺寸需检查实际渲染宽度；组件存在或 JSON 属性正确均不够。Web 另行实际调用浏览器文件选择器，随后由第二用户的原生内核读回精确字节。Apple 集成测试的文件选择适配器是合成输入，不冒充相册/系统选择器验收。

本批实测结果和源码指纹将收录到独立的 P6 evidence，不改写 P4/P5 及冻结快照。Android 按用户此前“仅继续 iOS，暂不安装”的要求保留未运行。

## 持续开发缺口

- 图片替换、相册/拍照/云图片、粘贴/拖入、传输进度/取消、来源撤权推送、跨资源引用生命周期、离线本机图片转在线附件和 GC 尚未完整交付。
- 内部块/文件链接的完整导航、链接编辑的全部思源语料及三端交互仍需扩展。
- 数据库运行内核资格已推进，独立对象/字段/视图与 UI 接入见后续数据库方案；普通表格不等于数据库。
- WS/presence、相对远端选区、所有写入口的服务端领域校验、耐久 ACK、私有评论/@、分享、历史、Agent 与 Office 协作仍是完整门的必做范围。
- 正式 Host 发布装配、真机输入、无障碍和性能还未全量验收；本批不发布正式产品。

## 本批证据固化

[独立 P6 evidence](execution/phase6-media-20261106/README.zh-CN.md) 已归档 **76 项产物、104 个源码指纹**。Rust 17 项、Flutter 本机回归 24 项、独立资产合同 1 项、独立传输 2 项通过；私有附件 HTTP 8 组通过。macOS/iOS 各 7 项实际 UI/协作检查与 4 项无凭据新进程检查；Web 10 项、整页重载 3 项、原生读回 6 项通过。浏览器实际文件选择器另有说明/alt/96px 属性与第二用户字节读回证明。数据库仅为原内核运行资格。

完整编辑/协作门执行后仍按预期拒绝完成。可运行 `python3 docs/smart-document/v1/scripts/verify_media_evidence.py` 校验历史完整性；追加 `--source` 比较当前工作树，本轮之后继续开发会使源码比较发生预期差异，不得回写历史证据。源仓库保持工作树交付，未形成正式多仓库发布提交。
