# Word 壳层 0.1.16：状态栏页码与定位面板

## 源码对照与实现边界

GenOffice `App.tsx` 的 `status-page` 是按钮：点击后打开工作区右上角的 `FindPanel`，并聚焦“定位”标签。`FindPanel.tsx` 中可选择页、节、行、书签、批注、脚注、尾注、表格与标题；页码接受绝对数字和 `+N` / `-N`，并有“上一个”“下一个”“定位”动作。`styles.css` 将桌面面板放在工作区顶部 8px、右侧 20px，采用白底、6px 圆角、8×10px 内边距，输入框 28px 高。

0.1.16 接通**页**目标：签名产品包声明面板文案及 `word.navigation.goTo` 低频视图命令；Flutter 壳响应状态栏页码，编辑表面拥有实际滚动控制，`word-core` 继续独占文档模型和排版。桌面面板贴近源码的工作区右上角，手机显示底部面板以避开软键盘。查找、替换标签灰显，其他结构目标尚未显示，直到相应的内核快照与命令接入。

## 同文档前后对比

桌面为同一份 8 页 `sample2.docx`、1365×860 视口。左图来自上一版 0.1.15，右图点击新版状态栏页码、输入 `4` 并定位后取得；页码和中间纸页随滚动更新。

| 0.1.15：页码静态文本 | 0.1.16：页码定位到第 4 页 |
| --- | --- |
| ![旧版桌面文档](evidence/0.1.16/before-desktop-home.png) | ![新版桌面定位面板](evidence/0.1.16/after-desktop-go-to.png) |

390 逻辑像素宽的同一 Flutter 源码使用触控底部面板，长提示可截断，动作与输入框可达。

| 0.1.15：窄屏文档 | 0.1.16：窄屏定位面板 |
| --- | --- |
| ![旧版窄屏文档](evidence/0.1.16/before-mobile-width.png) | ![新版窄屏定位面板](evidence/0.1.16/after-mobile-go-to.png) |

Android ARM64 模拟器关闭 Wi-Fi 与蜂窝数据后，从 Downloads 打开同一 DOCX，点击状态栏页码并执行定位。

| Android 文档 | Android 定位面板 | 关闭面板后的第 4 页 |
| --- | --- | --- |
| ![Android 文档](evidence/0.1.16/after-android-open.png) | ![Android 定位面板](evidence/0.1.16/after-android-go-to.png) | ![Android 第 4 页](evidence/0.1.16/after-android-page4.png) |

## 验证与待办

[联合流水线报告](evidence/0.1.16/stack-report.json)、[DOCX 渲染记录](evidence/0.1.16/render-evidence.json)和[平台验证清单](evidence/0.1.16/platform-verification.json)记录签名包、端到端用例、两端构建、离线打开和 DSH 面板。源 `resolveGoToIndex` 的绝对页、相对页、边界钳制及无效输入在 Flutter 单元测试和桌面端到端跳页中验证。

人工验证包位于 `Muse-Client/dist/OpenMuse-word-0.1.16-macos-debug.zip` 与 `Muse-Client/dist/OpenMuse-word-0.1.16-android-debug.apk`。两包内的 Word 功能包 SHA-256 均为 `990326579485e8e0bb4c53fb149139bb1c14ae1fd2a171fa804290b4fb03be04`；详情见[封包校验记录](evidence/0.1.16/package-verification.json)。

本轮只完成“页”目标。节、行、书签等源 `FindPanel` 目标，以及完整查找/替换、输入焦点与快捷键，仍需后续版本接入 `word-core` 的只读结构快照和版本化命令。当前没有同文档的 GenOffice 运行截图；这里提供的是源代码规格与 0.1.15/0.1.16 前后视觉证据，不能当成整套 Word 壳已经像素级 1:1 完成。
