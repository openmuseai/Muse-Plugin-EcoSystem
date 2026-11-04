# Word 壳层 0.1.15：字数统计弹窗与状态栏入口

本轮逐行核对 GenOffice `apps/docs/src/renderer/components/WordCountDialog.tsx`、`App.tsx` 与 `styles.css`。源弹窗有页数、字数、亚洲字符、非亚洲语言单词、字符数（不计/计空格）、段落数、行数八项；外框宽 440 像素、圆角 16 像素、内边距 22×24 像素；表格为 13 像素字体与每行 7×4 像素内边距。源状态栏的字数是可点击入口。0.1.14 只显示真实总字数，本轮补上可点击入口与八行只读弹窗。

## 同文档视觉对比

桌面使用同一份 8 页 `sample2.docx`、1365×860 测试窗口。左图为 0.1.14 状态栏，右图为 0.1.15 点击状态栏字数后的弹窗。右图的八项数据来自当前 `word-core` 会话与页面布局，并非插件中的固定示例值。

| 0.1.14：状态栏字数 | 0.1.15：统计弹窗 |
| --- | --- |
| ![旧版桌面文档](evidence/0.1.15/before-desktop-home.png) | ![新版桌面统计弹窗](evidence/0.1.15/after-desktop-statistics.png) |

窄屏复用同一 Flutter 组件。390 逻辑像素宽时弹窗缩至可用宽度，八行、关闭按钮和底部状态栏均可见，未出现布局溢出。

| 0.1.14：窄屏文档 | 0.1.15：窄屏弹窗 |
| --- | --- |
| ![旧版窄屏文档](evidence/0.1.15/before-mobile-width.png) | ![新版窄屏弹窗](evidence/0.1.15/after-mobile-statistics.png) |

Android ARM64 模拟器在 Wi-Fi、蜂窝数据均关闭后，从 Downloads 打开同一 DOCX，并点击状态栏字数。实际设备截图如下。

| Android 文档 | Android 统计弹窗 |
| --- | --- |
| ![新版 Android 文档](evidence/0.1.15/after-android-open.png) | ![新版 Android 统计弹窗](evidence/0.1.15/after-android-statistics.png) |

## 命令、模型与插件边界

- `word-core` 0.1.1 从唯一文档模型的主文本绳生成 `schemaVersion: 1` 的只读统计快照；桌面和 Android 的 Rust FFI 0.1.1 公开 `text_statistics_json()`。全量扫描使用 4096 字符缓冲区，不在插件进程、排版循环或逐字输入路径运行。`word_editor` 0.4.11 从当前渲染命令估算可见行数、从排版页信息取页数，并原生绘制弹窗。
- 已签名 `chrome.json` 决定标题、关闭文案、八项标签和顺序。`word.tools.wordCount` 现为 Host 门禁下的本地只读视图命令；原有 `extension.word-count.v1` 保留为独立、默认关闭的 `word.tools.extensionCount` 命令。扩展不能替代内核文档模型。
- 源 GenOffice 的“视图”Ribbon 不含独立统计组，因此删除了旧插件多出的“统计”组。状态栏字数入口与源结构一致。其他 Ribbon 页签和多级菜单仍按[逐项台账](08-RIBBON-MENU-INVENTORY.zh-CN.md)继续验收。

## 验证与限制

[联合流水线](evidence/0.1.15/stack-report.json)的 18 个阶段和 [8 个桌面端到端用例](evidence/0.1.15/desktop-e2e.json)均通过；[真实 DOCX 证据](evidence/0.1.15/render-evidence.json)记录 8 页、5654 字、43 段及 185 条估算可见行。[平台验证清单](evidence/0.1.15/platform-verification.json)记录 macOS Debug ZIP、Android Debug APK、同一签名产品包、离线设备截图及打包后启动检查。

当前段落数依据主文本绳中的段落分隔符，行数依据实际绘制命令的文本基线合并估算；复杂表格、页眉页脚、批注与 GenOffice 结构化统计的精确一致性尚待金文件验收。我们尚未取得同文档的 GenOffice 弹窗运行截图，因此本轮证明了源代码规格和前后实现差异，不能宣称全套 Word 壳像素级 1:1 完成。
