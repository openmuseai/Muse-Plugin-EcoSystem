# Word 壳层 0.1.12：开始 → 样式图库

本轮核对 GenOffice `apps/docs/src/renderer/style-gallery.ts`、`components/Ribbon.tsx` 的 `renderStyleCards` 与 `styles.css` 的 `.style-gallery`/`.style-card`。源实现按文档样式表筛选 `qFormat`，处理默认正文、`semiHidden`/`unhideWhenUsed`、优先级与选区激活状态；无文档样式时只有 Normal、Heading 1–3 四项缺省预览。内联卡片为 74×62 像素，溢出按钮宽 17 像素，完整图库最大宽 478 像素。

| 0.1.11 Host 首页 | 0.1.12 Host 首页 | GenOffice 源 CSS 规则参考 |
| --- | --- | --- |
| ![改动前首页](evidence/0.1.12/before-0.1.11-home-styles-shell.png) | ![改动后首页](evidence/0.1.12/after-0.1.12-home-styles-shell.png) | ![源 CSS 规则参考](evidence/0.1.12/source-css-quick-styles-reference.png) |

参考图是[独立 HTML](evidence/0.1.12/source-css-quick-styles-reference.html)根据上述 CSS 尺寸和缺省数据构造的局部视图，**不是 GenOffice 应用运行截图**。两张 Host 图使用相同 1365×860 测试窗口和同一份 8 页 DOCX。新版还原内联卡片、溢出入口和样式窗格入口；点击溢出后可看到四张缺省卡片：

![macOS 样式图库与文档页面](evidence/0.1.12/after-0.1.12-desktop-styles-menu.png)

Android 小屏保留同一份签名菜单数据，将样式图库作为触控底部弹层显示，卡片按可用宽度重排。以下两图分别显示离线打开文档时的 Ribbon/页面/状态栏，以及样式弹层：

| Android 离线文档 | Android 样式图库 |
| --- | --- |
| ![Android 文档](evidence/0.1.12/after-0.1.12-android-open.png) | ![Android 样式弹层](evidence/0.1.12/after-0.1.12-android-styles.png) |

## 模型与边界

- 插件 `ribbon.json` 声明 `gallerySource: document.quickStyles` 和样式组布局；`menus.json` 只保留从 GenOffice `FALLBACK_STYLES` 核对的四项**缺省预览**。新增 `audit:quick-styles`，一键流水线检查源数据与签名资源的一致性。
- Flutter `WordStyleSnapshot` 是由文档引擎或 Host 提供的只读展示快照。`quickStyles` 依照源规则筛选排序；`WordProductShell` 用它替换缺省卡片，`WordStyleCard` 负责 74×62 卡片和样式文字绘制。数据不持有可编辑文档树；菜单叶节点仍受命令能力门禁控制。
- 当前 Rust FFI 只提供排版绘制数据，**尚未导出样式表与选区快照**，所以实际 DOCX 的壳层显示四项缺省预览，不能据此声称已完成文档样式实时还原或样式应用。单元测试已验证快照替换、隐藏/使用规则和文档视图隔离。下一步是由 `word-core` 增加有版本的只读样式/选区接口，并接入 Host，随后做真实文档样式金图和应用命令闭环。

## 构建验证

本轮流水线、签名插件、macOS Debug ZIP、Android Debug APK、包内摘要和设备环境记录见[平台验证清单](evidence/0.1.12/platform-verification.json)，并保留[流水线报告](evidence/0.1.12/stack-report.json)及[桌面端到端用例](evidence/0.1.12/desktop-e2e.json)。调试包与开发测试签名仅供人工验证。
