# Easel 0.5.0 审核资料

**提交状态：仅生成待审核包；未上传线上市场。** 用户选择先准备审核候选。当前审核对象为 `dist/easel-0.5.0.mcpb`，摘要在 `dist/mcpb.sha256`，拟提交的标准 MCP Registry 记录在 `dist/server.json`。`server.json` 的包 URL 在上传前尚不可下载。

| 项目 | 内容 |
| --- | --- |
| Registry 名称 | `io.openmuse/easel` |
| 显示名 | Easel 社媒管理 |
| 版本 | 0.5.0 |
| 格式 | MCPB manifest 0.3、MCP stdio、MCP Apps 安装向导、npm `bin` CLI |
| 已测试目标 | 本机 Muse-Client checkout `cbd243e`，macOS arm64；Host 握手协商 MCP `2025-11-25`。公开兼容矩阵中的 Desktop `1.0.0` 发布构建仍需单独验收。 |
| 声明平台 | `darwin`，Node ≥22 |
| MCP 工具 | `easel_open`、`easel_setup_status`、`easel_setup_start`、`easel_setup_job` |
| 用户授权 | 页面明确显示 pip/Playwright 下载和可选的 `brew install ffmpeg`；发布另需账号扫码及 CLI `--exec` |
| 文件位置 | 应用代码在 Host 管理的 MCPB 安装目录；依赖与账号数据在 `~/.openmuse/easel` |
| 网络去向 | 安装期 Python 包源、Playwright CDN、可选 Homebrew；使用期用户所选社交平台网页 |
| 内容处理 | 素材由本机 Python 脚本处理；发帖时内容、图片或视频提交到用户操作的平台。插件没有自建远端上传服务。 |

## 验证记录（2026-10-22）

1. `npm test`：独立 MCP 客户端连接 stdio server，发现四个工具，读取 MCP Apps HTML，校验包中全部社媒脚本和 SHA-256；三项 Python 知乎图文单元测试通过。
2. 在临时 macOS 用户目录运行安装器：使用 Python 3.12 创建 venv，安装 Pillow 12.3.0、Playwright 1.63.0、Chromium 1243、Chromium headless shell 1243，核验 FFmpeg/ffprobe 9.0.2，生成成功收据。独立 Python 解释器复制模式失败后已改用符号链接模式，并以成功安装重测。
3. 从实际 MCPB 解压目录执行 `easel douyin plan`，只生成离线发布步骤；执行 1 秒测试视频的 `easel video process`，输出 3 秒带封面的 MP4 和 PNG，退出码为 0。
4. Host 的通用 `McpRegistryMarket.install` 测试使用该 MCPB 字节完成安装、启动 Node MCP server、发现 MCP Apps 入口并读取 HTML，Flutter 测试通过。
5. 通过 MCP tool 启动一次已有临时环境的依赖修复任务，异步进度从 `running` 到 `complete`，状态 `ready=true`。

## 审核需重点核对

- 抖音脚本头部说明参考了 [WJZ-P/douyin-upload-mcp-skill](https://github.com/WJZ-P/douyin-upload-mcp-skill) 的选择器与流程。Easel 的元数据称其为 Playwright 重写、未引入原 Node 源码；该参考仓库的 [LICENSE](https://github.com/WJZ-P/douyin-upload-mcp-skill/blob/main/LICENSE) 为 AGPL-3.0。本包保留其许可证文本及来源说明，但是否构成衍生作品仍需法律/许可证审核。审核批准前请不要把包标为已正式公开。
- 所复制的 `web_publisher.py` 包含本机 Easel 源码工作树尚未提交的 138×138 知乎二维码阈值修正；来源与修改已在 `UPSTREAM-NOTICE` 中标明。
- 目前 `Pillow>=10,<13` 尚未以 hash 锁定，Chromium 与 Homebrew 下载链尚无插件级供应链签名证明。生产审核应决定是否接受动态安装，或要求固定版本和哈希。
- 真账号抖音/知乎发布、登录二维码在 MCP Apps 页面展示、Mobile 远端控制尚未按新 MCPB 路径验收。旧 `.omplugin` 的实机记录不能直接作为本版市场发布证明。
- 发布有外部副作用。CLI 默认预览，只有 `--exec` 执行；知乎图文靠内容哈希回执防止默认重复，网页读回失败时不得误报已核实。

## 审核结论栏

本文件提供审查材料，不代替审核决定。生产市场需在源码仓库包含本版、开发者上传签名/摘要校验、许可证复核、恶意软件扫描与独立审核通过后，才公开 Registry 条目。
