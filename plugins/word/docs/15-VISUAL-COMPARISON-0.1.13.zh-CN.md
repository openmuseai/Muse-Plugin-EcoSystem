# Word 壳层 0.1.13：真实 DOCX 快速样式

本轮继续核对 GenOffice `apps/docs/src/renderer/style-gallery.ts` 的 `quickStyleEntries`、`collectUsedStyleIds`、`activeStyleKey` 与 `components/Ribbon.tsx` 的样式图库。GenOffice 从当前文档样式表构建图库，按 `qFormat`、默认正文、`semiHidden`、`unhideWhenUsed` 和 `uiPriority` 筛选；0.1.12 只有四个签名缺省预览。现在 `word-core` 在同一个文档会话中生成版本为 1 的只读样式快照，经 Rust FFI 传给共用 Flutter 编辑面。插件仍只声明 `document.quickStyles` 图库位置、菜单层级、命令与缺省资源，不持有文档状态。

## 本轮视觉对比

以下桌面截图使用同一份 8 页 DOCX、同一 1365×860 测试窗口。左图显示 0.1.12 的四项缺省预览；右图显示 0.1.13 从该 DOCX `styles.xml` 实际读取的 `Normal`（其样式 ID 为 `1`）。内容页、顶部 Ribbon 与底部状态栏保持同一布局。

| 0.1.12：缺省样式 | 0.1.13：文档样式 |
| --- | --- |
| ![旧版首页](evidence/0.1.13/before-desktop-home.png) | ![新版首页](evidence/0.1.13/after-desktop-home.png) |
| ![旧版样式菜单](evidence/0.1.13/before-desktop-styles.png) | ![新版样式菜单](evidence/0.1.13/after-desktop-styles.png) |

样式卡片的 74×62 尺寸、17 像素展开入口和样式菜单来自 GenOffice 的实现与 CSS。右图在只有一个样式时仍保留展开入口。下图是按**源 CSS 与缺省数据独立重建**的参考，不是 GenOffice 应用针对该 DOCX 的运行截图，也不能证明全部菜单已达到像素级一致。

![GenOffice 源 CSS 局部参考](evidence/0.1.13/source-css-reference.png)

Android 在断开 Wi-Fi 与移动数据后打开本地 DOCX，显示第 1 页、共 8 页，样式触控弹层由原先四个缺省项改为文档实际的一个 `Normal` 项。桌面和 Android 均使用相同的签名产品包与 Flutter 编辑面源码。

| Android 0.1.12 样式 | Android 0.1.13 样式 |
| --- | --- |
| ![旧版 Android 样式弹层](evidence/0.1.13/before-android-styles.png) | ![新版 Android 样式弹层](evidence/0.1.13/after-android-styles.png) |

![Android 离线文档和状态栏](evidence/0.1.13/after-android-open.png)

## 代码与合同

- `word-core/api/StyleSnapshot.rs` 从已打开的 DOCX 读取样式定义与正文使用的样式 ID，`DocumentSession` 保存只读投影；样式与文档编辑仍只归内核所有。Rust FFI 的 `style_snapshot_json()` 采用 `schemaVersion: 1`，Flutter `WordStyleSnapshot.fromEngineJson` 验证版本并生成展示对象。
- 当文档没有 `styles.xml` 或没有样式定义时，编辑面继续使用插件中的签名缺省预览。卡片使用 Host 已加载的字体，避免 DOCX 声明了未注册字体时的黑块；样式原字体名称保留在快照中，待 FontHost 解析后再用于预览。
- 解析测试覆盖快速样式标记、隐藏后使用、优先级、默认字号和真实 DOCX ZIP。Flutter 测试覆盖版本化快照转换。样式应用命令仍经 Host 能力门禁，不因展示快照而绕开它。

## 构建与边界

[流水线报告](evidence/0.1.13/stack-report.json)的 18 个阶段与 8 个桌面端到端用例均通过；[包内验证清单](evidence/0.1.13/platform-verification.json)记录 macOS Debug ZIP、Android Debug APK、签名插件摘要及设备验证。已打包的 macOS App 另行启动并确认 `OPENMUSE_WORD_RENDER_READY:8:187`、DSH HTTP 200 与 WebView loaded，见[启动日志](evidence/0.1.13/packaged-macos-launch.log)。

当前快照在 DOCX 打开时生成；逐字编辑后的实时 `usedStyleIds`、光标位置的 `activeStyleKey`、应用/创建样式命令和字体资源解析尚需接通内核会话。底部实际字数与部分 Ribbon 命令也未完成，不能将本轮结果认定为整个 GenOffice Word 壳的 1:1 完成。下一轮应在 `word-core` 添加随文档修订号与选区变化的增量样式查询，随后把可用的样式命令接到 Host 能力接口，并用同一 DOCX 的 GenOffice 实际运行图逐项做视觉验收。
