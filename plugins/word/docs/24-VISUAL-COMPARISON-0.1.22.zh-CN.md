# Word 壳层 0.1.22：GenOffice 水平标尺第一阶段

## 源码、领域边界与实现

GenOffice 的 [`Ruler.tsx`](../../genoffice-pptx/vendor/genoffice/apps/docs/src/renderer/components/Ruler.tsx) 以节的页宽、左右边距和当前段落为输入，在文本起点两侧绘制刻度、灰色边距区、半英寸默认制表位；[`styles.css`](../../genoffice-pptx/vendor/genoffice/apps/docs/src/renderer/styles.css) 规定标尺高 20px、下方间隔 6px，随文档缩放；[`App.tsx`](../../genoffice-pptx/vendor/genoffice/apps/docs/src/renderer/App.tsx) 在多页排列时隐藏标尺。

0.1.22 将“视图 → 显示 → 标尺”接为已签名的 `word.view.ruler` 命令。插件仅声明按钮和低频视图操作；Flutter `word_editor` 保存开关，以 `word-core` 的实际页面尺寸/边距计算标尺几何并绘制。中文等公制地区默认厘米，美英制地区默认英寸，刻度从文本起点双向编号。`word-core` 的文档模型、分页和 187 条页面绘制命令在切换中不变。`word_editor` 升为 0.4.18、产品插件升为 0.1.22，兼容清单同步更新。

## 同文档前后对比

两图均为本轮 `sample2.docx` 第 1 页，桌面窗口 1365×860、缩放 166%。标尺开启后与纸页左边缘对齐，页内容沿垂直方向下移标尺所占高度；Ribbon 中“标尺”呈选中态，底部页数/字数/缩放值保持一致。

| 关闭标尺 | 开启标尺 |
| --- | --- |
| ![桌面关闭标尺](evidence/0.1.22/desktop-before.png) | ![桌面开启标尺](evidence/0.1.22/desktop-after.png) |

[窄窗口截图](evidence/0.1.22/narrow-after.png)使用同一 Flutter 编辑面，在 390×844 窗口、整页适配 43% 缩放下显示标尺和正文，没有横向溢出。这是桌面 Flutter 的窄窗口测试，**不是 Android 设备截图**。[像素度量](evidence/0.1.22/visual-metrics.json)显示桌面开关前后有 169163 个像素变化、平均每通道绝对差 17.24/255；此数据只说明本轮开关效果，不代表与 GenOffice 运行截图的像素误差。

## 验证

[一键流水线](evidence/0.1.22/stack-report.json)的 20 个阶段与 8 个桌面端到端用例全部通过，覆盖签名插件安装、离线重开、原生文档窗口、嵌入窗口、DSH 面板和真实 DOCX 渲染。[渲染证据](evidence/0.1.22/render-evidence.json)记录 8 页、187 条绘制命令、5654 字；[端到端记录](evidence/0.1.22/desktop-e2e.json)记录安装与 Host 产物哈希。测试还验证标尺与纸页左边缘对齐、切入多页视图时隐藏标尺、窄屏宽度与 Flutter 无溢出；几何单元测试核对厘米/英寸刻度和缩放尺寸。

本轮已重新构建并运行 macOS Debug Host，供本地查看的应用位于 `Muse-Client/app/openmuse_host/build/macos/Build/Products/Debug/OpenMuse.app`。本轮未制作新的分发 ZIP。

## 下一阶段与验收边界

当前标尺提供**只读页面几何**。GenOffice 还能显示并拖动显式制表位、首行/悬挂/左右缩进和节页边距；这些值需要 `word-core` 提供当前节与段落的版本化快照及编辑命令，之后再接通鼠标、触屏和键盘交互。为避免显示与真实文档不符的标记，本轮没有绘制假定的段落缩进或提供无效拖拽。

本轮对照了 GenOffice 源码和 OpenMuse 同文档前后图，尚未取得**同文档、同窗口的 GenOffice 运行金图**。完整 Ribbon、中间编辑区与状态栏的像素级 1:1 仍需逐项金图验收；导航窗格、分页预览、Web 版式、大纲和窗口操作仍在计划中。
