# Word 产品资源与命令合同 v1

本文件定义插件公开 Profile，供 `ioffice` 和任何实现该 Profile 的 Host 使用。macOS Host 已支持首版资源验签与原生只读预览；编辑命令合同仍在迭代。插件不导入 Host 私有 Dart 类型；MCPB 的 `manifest.json` 保持标准 0.3 格式，Word 语义保存在 `product/` 的普通资源中。

## 产品包

`product/product.json` 使用 `openmuse-word-product/1`，声明插件 ID、语义版本、DOCX MIME、`wordApiMajor`、`editorSurfaceMajor` 和资源路径。当前壳层要求 `editorSurfaceMajor=2`；旧版只含命令列表的 Ribbon 属于 Surface v1，应明确拒绝或由独立迁移适配器处理。路径必须是包内相对路径，不能跳出 `product/`。资源包括：

| Profile | 文件 | 内容 |
| --- | --- | --- |
| `openmuse-word-commands/1` | `commands.json` | 稳定命令 ID、标签、所属功能、目标、操作与效果 |
| `openmuse-word-ribbon/2` | `ribbon.json` | 常规/上下文标签、组、控件种类、菜单与命令引用；不携带 Widget 代码 |
| `openmuse-word-menus/1` | `menus.json` | 有界递归菜单树；标题、分隔线、子菜单、叶节点与可选命令引用 |
| `openmuse-word-chrome/1` | `chrome.json` | 顶部、工作区、状态栏的有界视觉参数与槽位；不携带可执行 UI 代码 |
| `openmuse-word-shortcuts/1` | `shortcuts.json` | `Primary` 等平台无关快捷键声明 |
| `openmuse-word-features/1` | `features.json` | 默认开关与所需能力 |
| `openmuse-word-template/1` | `templates/*.json` | 有界段落与样式内容；内核负责实例化 |
| `openmuse-word-fonts/1` | `fonts/catalog.json` | 字体文件摘要、许可及回退目录 |
| `openmuse-word-extension/1` | `extensions/*.json` | 低频命令的版本、输入、输出与预算 |

现有 `scripts/validate.mjs` 检查资源路径、ID 唯一性、Ribbon/快捷键引用、模板大小和扩展操作映射。宿主还需要独立实现安装时验证，不能只依赖包内校验脚本。

`chrome.json` 的尺寸、颜色、响应式断点和状态栏槽位受校验器约束；Host 验签后把资源快照交给 Flutter `WordProductShell`。壳层不得从这些 JSON 执行代码。`ribbon.json` 的 `items[].command` 必须存在于同组 `commands` 和 `commands.json`；`items[].menu` 必须引用签名 `menus.json`。无命令的按钮不可执行；有菜单的按钮可以打开层级菜单，但无命令的叶节点不可执行。Host 还必须以运行时能力、资源权限和编辑会话状态再次判断命令是否可执行。

## 能力协商与可见性

Host 提供 `wordApiMajor=1`、`editorSurfaceMajor=2` 和该运行环境实有的能力集合。某功能可用当且仅当：插件发行配置 `defaultEnabled=true`，所有 `requires` 能力存在，用户有资源权限，当前文档状态允许该命令。未满足时应隐藏或明确置灰并说明原因。不能因为命令写在 Ribbon JSON 里就假定内核已实现。

`defaultEnabled=false` 是发行门禁，即使 Host 声称有能力也不自动开启。更改它需要新签名包和相应验收。功能区顺序可随产品包更新，命令 ID 的行为语义在 v1 内保持稳定；破坏性变化须提升 Profile 主版本。

## 命令调用

`word.command/1` 是 Host 与内核/编辑表面的建议接口。插件只声明命令，不自己维护 `Document`。一个显式命令请求的规范形状：

```json
{
  "profile": "word.command/1",
  "requestId": "opaque-id",
  "sessionRef": "opaque-session",
  "commandId": "word.format.bold",
  "baseRevision": "opaque-revision",
  "arguments": {},
  "source": "ribbon"
}
```

返回 `{profile:"word.command.result/1",requestId,status,revision,selection?,error?}`。`status` 为 `applied`、`unchanged` 或 `rejected`。`rejected` 的稳定错误至少包含 `UNSUPPORTED_CAPABILITY`、`STALE_REVISION`、`RESOURCE_REVOKED`、`READ_ONLY`、`BUDGET_EXCEEDED`。`sessionRef` 和 `revision` 是 Host/内核的不透明值，插件不能解析或持久化。保存命令由 Host 先请求内核导出新 DOCX，再检查基准资源修订并原子提交；插件不能直接写文件。

命令 `target` 只可取 `host`、`core`、`editor`、`extension`。`effect` 标注 `view`、`read`、`edit`、`write`，用于授权与遥测分层。`target=extension` 不允许承接键入、选择、光标移动、滚动、排版或逐帧绘制。Host 的全局快捷键优先于插件快捷键；重复绑定在安装时失败。

## 扩展调用

`extension.word-count.v1` 仅在用户点击“字数统计”或调用同等显式命令时执行。Host 从 `word-core` 获取已授权的 `word.snapshot.text.v1`，附带文档修订与范围，将文本传给 Desktop MCP `word_count_text` 或等效的本地受控实现；实现源码为 `src/word_count.mjs`。请求最多 100 万 Unicode code point；超限拒绝并提示用户缩小范围。返回 `word.count.v1` 的字符数、非空白字符数、词数和段落数。

当前字数算法将每个汉字计为一个词，非汉字的连续字母/数字词串计为一个词。这个算法是插件级统计定义，不参与内核排版，也不承诺等同 Microsoft Word 的计数规则。Mobile/Web 运行该扩展需要 Host 接入受控脚本适配器；在此之前 `word.wordCount` 保持关闭。

## 签名与发布

`npm run build` 生成标准 MCPB `manifest.json`、静态产品资源、Desktop 资源发现 Server 和可移植扩展逻辑。`npm run pack -- --private-key ... --key-id ...` 构建 `catalog.json`，按路径排序记录所有发行文件的字节数与 SHA-256，再用 Ed25519 对原始目录字节签名，最后生成 MCPB。生产密钥在发布环境管理，包中只有 key ID 和签名。Registry 的 `fileSha256` 保护包下载；Host 可信公钥和资源目录验签保护发布者身份及离线导入。修改任一模板、字体、脚本或命令都必须重新签名和审核。

Desktop 通过普通 MCP `resources/list/read` 发现 `application/vnd.openmuse.word-product+json` 资源；`tools/list` 仅暴露显式字数统计。Mobile/Web 可直接消费已验签的静态文件，不依赖 Node 进程。OpenMuse 需要新增公开 Word Product Profile 加载器；当前市场的通用文件编辑器发现不会因为 MCPB 安装就自动识别这些产品资源。
