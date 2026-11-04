# Easel 社交媒体管理插件

Easel 是可选的第三方社交媒体管理应用。`0.5.0` 把旧 `Muse-Client/plugins/easel` 的媒体加工、抖音/知乎发布代码与六个直接依赖脚本收进本目录，交付为独立 MCPB。OpenMuse 客户端只识别公开的 MCP Registry、MCPB、MCP Tools、MCP Apps 和 npm `bin` 约定；平台选择器、浏览器自动化、登录态、文章解析、回执和依赖安装都由本插件维护。

## 已实现的交付边界

| 层 | 职责 | 位置 |
| --- | --- | --- |
| 市场 | 上传、审核、目录、SHA-256、通用 MCPB 安装 | `Muse-Plugin-Ecosystem/market-service` 与 Host 通用市场 |
| 插件应用层 | MCP server、安装向导、CLI、平台脚本和第三方声明 | 本目录，打入 `easel-0.5.0.mcpb` |
| 用户本机依赖 | Python venv、Pillow、Playwright、Chromium、FFmpeg/ffprobe | `~/.openmuse/easel/runtime`；包里不预装，不在市场下载时静默执行 |
| 用户数据 | 平台浏览器 profile、授权状态、发布回执、输出 | `~/.openmuse/easel/{profiles,state,outputs,cache}`；绝不打包上传 |

当前 `0.5.0` 的 MCP Apps 页面是安装向导，完整社媒命令通过安装包自带的 `easel` CLI 调用。Desktop macOS 是本版已声明兼容的平台；Windows/Linux 所需的 FFmpeg 获取、路径与浏览器检查尚未验收，因此不在此版兼容声明中。Mobile 本机不安装此插件业务代码。旧 `com.openmuse.easel` 的私有 `.omplugin` 发行方式不再继续；市场条目为 `io.openmuse/easel`。

## 市场安装与插件专属引导

1. 市场只下载、校验并解压 MCPB，建立签名/摘要收据，然后用标准 MCP `tools/list` 验证入口。此时**不**执行 pip、Playwright 或 Homebrew，也不打开社交平台。
2. 宿主的通用逻辑在安装完成后发现零参数 MCP Apps 入口，打开插件自己的 `ui://easel/setup` 页面。宿主不包含 Easel 名称、依赖列表或发布业务分支。
3. 页面调用只读 `easel_setup_status`：检查受支持的 Python 3.11–3.14、FFmpeg、ffprobe、专用 venv 和浏览器目录，展示将写入的本机数据位置。
4. 用户选择 Python 路径、已有 FFmpeg 目录，或者勾选 `brew install ffmpeg`。页面明确展示联网下载和 Homebrew 修改范围。按“开始安装”才调用 `easel_setup_start`。
5. `easel_setup_start` 启动插件自己的异步安装作业，页面轮询 `easel_setup_job` 显示日志。`runtime/install.py` 创建 venv，安装 `requirements.txt`，将 Chromium 下载到专用 `runtime/browsers`，检查 ffmpeg/ffprobe，并原子写 `install-status.json`。失败保留日志，不写成功状态；再次启动可修复。
6. 安装完成后用户按平台调用 `easel douyin check` / `easel zhihu check`、扫码登录、离线预览、最终显式发布。插件不会把“应用安装”当成“账号授权”或“允许发帖”。

若没有合适的 Python，向导会报 `PYTHON_3_11_TO_3_14_REQUIRED` 并要求用户提供解释器。若没有 Homebrew 或不愿使用它，用户可先通过自己信任的渠道安装 FFmpeg，再输入同时含 `ffmpeg` 和 `ffprobe` 的目录。已安装的 FFmpeg 不会被重复安装。安装脚本只在用户启动向导后运行；卸载应用时默认保留用户 profile、素材和发布回执，清理这些数据须另行明确选择。

### 安装状态与回滚

- 市场解压阶段使用临时目录、摘要校验和收据；失败不替换已安装版本。
- 依赖准备阶段只在插件数据目录写 venv/Chromium；Homebrew 是单独的显式选项。安装失败不会回滚用户已有的 Homebrew 软件。重试复用或修复 venv。
- 插件升级不迁移或清除账号 profile。旧 `.omplugin` 工作区不会自动复制；迁移时应先停用旧插件，人工备份旧 `profiles` 与 `state`，核对账号后再导入新数据目录，避免并行浏览器使用同一 profile。
- 发布前预览是默认路径；`--exec` 才真正提交。知乎图文含内容哈希回执，重复提交默认阻断，`--force` 才能重发。平台读回失败必须报告未核实，不得称成功。

## 运行命令

市场安装后，通用 MCPB `bin` 机制提供 `easel` 命令。运行前先完成向导。

```sh
easel status
easel douyin check
easel douyin plan --title '示例' --content '仅生成预览'
easel zhihu check
easel zhihu inspect --article /path/to/article.md
easel zhihu publish-article --article /path/to/article.md       # 默认预览
easel zhihu publish-article --article /path/to/article.md --exec # 明确提交
easel video process --input /path/to/input.mp4 --output /path/to/output.mp4
```

账号登录由平台脚本启动独立浏览器 profile，二维码与 cookie 仅留在本机。视频和图文输入路径指向用户主动选定的文件；本版 CLI 尚未走 MCP 的选文件资源授权，Agent 侧不要把任意工作区路径自动传给它。抖音/知乎网页结构可能变化，平台检查通过不等于真实发布验证；真实账号发布应有人工预览和平台侧读回。

## 开发、验证、发布

```sh
cd plugins/easel
npm test
python3 scripts/pack.py
shasum -a 256 dist/easel-0.5.0.mcpb
```

`npm test` 构建并打包，再用独立 MCP 客户端连接实际 stdio server，验证工具发现、只读环境检查、MCP Apps 资源和包摘要；Python 测试覆盖知乎图文解析与防重复提交。安装向导的网络步骤需在干净的 macOS 用户环境手动验收，包含 Python 缺失、FFmpeg 缺失、下载中断、重新运行和卸载后数据保留。发布前还应使用真实 Desktop Host 安装已审核包并确认自动打开向导。

有开发者令牌时提交审核：

```sh
MARKET_DEVELOPER_TOKEN=... python3 scripts/publish.py \
  --registry https://plugins.openmuseai.com
```

脚本只上传本版 MCPB 与标准 `server.json`，返回 `submissionId` 和 `pending`；只有审核批准后公开目录列出本版，才算应用市场正式上架。开发者流程不使用审核员凭据。此包应随审提交源码、Apache-2.0 上游许可证、`UPSTREAM-NOTICE`、依赖清单、隐私说明、构建摘要和测试结果。

### 待完成的生产门槛

1. 对 `shared/scripts/douyin_publish.py` 头部所述移植来源做逐文件许可证复核，并补齐第三方许可证文本；Easel 根许可证不足以代替所有来源核对。
2. 固定 Python 依赖的散列、Chromium 构建和 FFmpeg 获取来源，形成可复现、可扫描的安装清单；目前 `Pillow>=10,<13` 仍是范围约束。
3. 给 MCP 工具增加选文件内容传递、结构化预览和一次性发布确认，替换现阶段依赖本地路径的 CLI；把二维码状态通过标准 MCP Apps 呈现，并验证手机远端控制。
4. 完成真账号抖音/知乎回读及断网、风控、重复发布测试。知乎网页曾出现 `40362`，不能仅凭提交前图数宣称发布后图文完整。

这些门槛决定何时可从本地联调/审核候选进入正式公开发布，不应在未验证时宣称已完成。
