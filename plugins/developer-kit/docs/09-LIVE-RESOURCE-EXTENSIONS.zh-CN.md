# DevKit 0.3.1：在真实文档上开发讲解扩展

先选择现有或新建 Workspace，再打开该 Workspace 终端。安装 GenOffice PPTX 0.7.0、PDF Reader 0.2.0 和 DevKit 0.3.1；DSH Agent 由用户配置模型。开发者不需要构建 Host 或文档引擎。

```sh
muse search pptx
muse search pdf
muse init --name document-narration --capability pptx --capability pdf --template document-explainer
muse check
muse dev
```

初始化仍在当前目录事务生成 main.js、devkit.project.json、devkit.lock.json 和 README.md；不会覆盖已有文件。模板是本生态的文档讲解参考，不是 MCP 标准定义的业务组件。模板把消费者逻辑和 SDK 捆入自己的 MCPB，运行时不依赖 DevKit。

muse dev 上传本机候选到 Host 的短期开发通道。Host 原生授权后识别公开 Resource Extensions v1 目录，将浮层挂到已有 PPTX/PDF 编辑器；返回 resource-extension-development。修改 main.js 再次执行 muse dev，只重建候选浮层，编辑器/文档内容保留。普通 multi-resource 模板继续使用独立全页预览。终端关闭、会话过期或账号切换会撤销开发候选；生产插件没有获得这些开发权限。

main.js 的默认 run(api) 调用 api.mountNarration()。可修改初始化和 UI 逻辑；底层使用官方 MCP Apps App、公开通用路由和 Provider 业务合同。DSH 的私有 HTTP/session/bridge token 不会出现在工程中。新的通用浮层目录与工具文档见 ../../../contracts/resource-extensions-v1/README.zh-CN.md；实时 Provider 语义见各插件开发文档。

## 真实测试报告与提交

两种资料各完成至少一页真实模型输出后，模板向本候选 Server 的 record_run 提交分项结果。报告明确标记 genoffice-live/pdfjs-live，只有全部选定 Provider 均有结果才进入 passed。接收请求、安装成功、空白页、模型失败或取消都不能生成通过项。报告仍是开发客户端报告，不能称为可信服务端远程证明，也不能替代审核员独立复验。

```sh
muse report
muse pack
muse submit
```

submit 只产生 pending。开发者没有 approve 接口或审核凭据；审核员确认发行 SHA、权限、数据出站、合同和目标设备测试后独立审核。包中只有运行依赖与源码，不包含本机授权、DSH 会话、用户文档或发布令牌。

当前模板只包含 PPTX/PDF 的实时文字讲解和 DSH 适配，不包含通用依赖图、公开 npm 发布、语音、Mobile/Web 真机验证。UI 和业务均由消费者负责，Host 的通用目录不应加入按文件类型或讲解命令的分支。

## 0.3.1 修正

安装和开发候选调用允许十分钟交互授权；普通查询保持两分钟超时。相同 SHA 的开发候选在修订后的 Host 中复用原回执，避免网络/授权超时后重试重建已工作的 View。资源扩展新候选替换旧候选并释放旧目录，不积累至四次后无法继续开发。隐藏终端并关闭最后一份文档不会再销毁已创建的终端会话。讲解条的当前页与下一待讲页分开，完成页后的等待期间不提前显示下一页。
