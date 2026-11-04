# PDF 壳视觉对齐轮次与证据

每轮使用 GenOffice 仓库中的 [`PDF 产品截图`](../../genoffice-pptx/vendor/genoffice/docs/assets/readme/pdf-edit.webp) 与 [`App.tsx`](../../genoffice-pptx/vendor/genoffice/apps/pdf/src/renderer/App.tsx)、[`styles.css`](../../genoffice-pptx/vendor/genoffice/apps/pdf/src/renderer/styles.css)、[`tokens.css`](../../genoffice-pptx/vendor/genoffice/packages/ui/src/tokens.css) 为依据。早期轮次的固定截图使用深色、AI 轨道收起状态；`0.1.13` 已改浅色默认，`0.1.15` 已按 GenOffice 默认展开 AI。参照仍是英文三页业务 PDF，我们使用中文壳和两页测试 PDF，**不能将两个整图像素误差当作同场景验收**。确定性尺寸和图标几何按源码逐项比较，交互由测试与真实 Host 打开文档验证。

## 第 1 轮：`0.1.2` 图标、菜单与密度

| 检查点 | GenOffice 源码 | 本轮实现与证据 | 剩余差异 |
| --- | --- | --- | --- |
| 标签/Ribbon | 标签行 35px、工具带 80px；活动下划线限于文字宽度 | 产品资源声明 35/80；[开始截图](../../../../Muse-Client/dist/pdf-product-evidence-0.1.2/ribbon-home.png) 可见文字宽度下划线 | 悬停/按下动画需逐控件比对 |
| 图标 | `icons.tsx` 的 24 单位矢量、标准大图标 28px、AI 小图标 24px | `product/icons.json` 签名资源含 65 个原 SVG 几何和 79 个控件映射；七标签截图逐项检查 | Muse AI 保留自有品牌标志；若干状态图标仍需动态切换 |
| 多级菜单 | `rb-drop` 深色 `surface`、强边框、10px 圆角；菜单项 12.5px | [转换菜单截图](../../../../Muse-Client/dist/pdf-product-evidence-0.1.2/ribbon-home-convert-menu.png)；递归菜单由签名资源描述 | 高亮/绘制的完整颜色选择器、页面操作对话框、表单属性面板待实现 |
| 中央/底部 | AI 轨道 34px、缩略图栏 150px、状态栏 24px 且只跨文档区 | 同一 Host 测试打开并渲染两页 PDF；[页面标签截图](../../../../Muse-Client/dist/pdf-product-evidence-0.1.2/ribbon-page.png) 显示页面/缩略图/状态栏 | AI 展开面板、复杂 PDF 编辑覆盖层待内核与表面继续完善 |
| 窄窗口 | 工具带横向滚动、紧凑带 45px | 800px 组件测试验证滚轮横向到达；手机测试验证页签与底栏不溢出 | 折叠屏多窗口与放大字体的实机截图待补 |

完整桌面标签证据在 `Muse-Client/dist/pdf-product-evidence-0.1.2/ribbon-{home,annotate,edit,page,view,fillForm,formDesign}.png`。生成命令：先执行 `ANDROID_SERIAL=emulator-5554 bash scripts/quick-verify.sh all`，再执行 `bash scripts/capture-visual.sh`。后者从**刚构建的签名包**加载产品资源，并在 1365×860、1.0 DPR 截图；禁止用旧包图片替代本轮证据。

Android release APK 已安装到 `emulator-5554`；从 OpenMuse「添加内容→PDF 文档」选择固定两页文件后保存了[开始标签、页面和底栏截图](../../../../Muse-Client/dist/pdf-product-evidence-0.1.2/android-release-home.png)以及[页面标签截图](../../../../Muse-Client/dist/pdf-product-evidence-0.1.2/android-release-page.png)。设备画面显示真实 PDF 文本、`第 1 页，共 2 页` 与 `61%` 缩放。构建报告 [`quick-verify-all.json`](../dist/quick-verify-all.json) 为 `passed: true`，记录三仓提交、脏树、签名包与端产物摘要；macOS 应用 `codesign --verify --deep --strict` 和 APK v2/v3 签名验证通过。

## 第 2 轮：`0.1.3` 色板、真实菜单语义与响应式证据

| 检查点 | GenOffice 源码 | 本轮实现与证据 | 剩余差异 |
| --- | --- | --- | --- |
| 高亮和绘制颜色 | `packages/ui/src/color-picker.tsx/css`：260px 弹层、10 列主题色、5 行明暗色、10 个标准色、“更多颜色” | 签名 `chrome.json.palette` 保留 70 色与标签；[高亮色板截图](../../../../Muse-Client/dist/pdf-product-evidence-0.1.3/ribbon-home-color-palette.png)，绘制色板及自定义十六进制输入有组件测试 | Flutter 自定义颜色弹窗与 GenOffice 所用 OS 原生取色器不同；此项待目标平台适配 |
| 工具带收起 | `useRibbonCollapse`：再点当前标签收起，切换标签恢复 | [收起态截图](../../../../Muse-Client/dist/pdf-product-evidence-0.1.3/ribbon-collapsed.png)，组件测试验证页面和状态栏保留 | 跨重启密度持久化和快捷键待补 |
| 菜单真实性 | `App.tsx`：转换为 5 项；“排列”为需多选字段的单层 11 项；“水印”为对话框 | 移除旧版虚构的排列子层及图章子菜单；未具备字段选择/水印编辑 ABI 时入口禁用，避免假操作 | 页面处理与水印的真实参数弹窗尚未实现 |
| 窄视口 | 工具带压缩与横向可达；页面、底栏持续显示 | 同一真实两页 PDF 在同一会话中从桌面缩到[平板 800×600](../../../../Muse-Client/dist/pdf-product-evidence-0.1.3/tablet-home.png)、再缩到[手机 390×844](../../../../Muse-Client/dist/pdf-product-evidence-0.1.3/phone-home.png)；适应宽度模式随视口重算，页内容没有横裁 | 折叠屏硬件切换、放大字体及实体设备触控还需验收 |

本轮继续保存[七个一级标签截图](../../../../Muse-Client/dist/pdf-product-evidence-0.1.3/ribbon-home.png)与[转换菜单截图](../../../../Muse-Client/dist/pdf-product-evidence-0.1.3/ribbon-home-convert-menu.png)。图片由签名 `0.1.3` 包的 Host E2E 在固定视口生成；macOS 和 Android 构建由同一 `quick-verify.sh all` 执行，结果见 [`quick-verify-all.json`](../dist/quick-verify-all.json)。GenOffice 仓内参照图与本轮样本 PDF 的主题、语言和文档仍不一致，因此表中只对已确定的布局、色值、菜单结构作源码级比较，暂不宣称整图逐像素一致。

Android Release APK 在 `emulator-5554` 上重新安装后，人工从 OpenMuse 入口选中同一两页 PDF，保存了[开始/页面/底栏](../../../../Muse-Client/dist/pdf-product-evidence-0.1.3/android-release-home.png)、[色板弹层](../../../../Muse-Client/dist/pdf-product-evidence-0.1.3/android-release-color-palette.png)、[页面 Ribbon](../../../../Muse-Client/dist/pdf-product-evidence-0.1.3/android-release-page.png)三张设备原始截图；文字、页码和 61% 缩放均可见。[人工验证清单及截图摘要](../../../../Muse-Client/dist/pdf-product-evidence-0.1.3/manual-android-validation.json)单独保存，避免把人工动作冒充自动测试。

最终 `quick-verify-all.json` 标记 `macos/android/visual` 三阶段均完成；macOS 应用通过 `codesign --verify --deep --strict`、ZIP 完整性检查，APK 通过 v2/v3 签名验证。macOS `.app` 与 APK 内置的 `pdf.mcpb` SHA-256 均为 `c040b7ce27ede857cd3d7feb21a582d6ee32061eb9c73ae5d21415171e2f6b8b`，与独立签名包一致。APK 为本地测试签名，尚非商店发行包。

## 第 3 轮：`0.1.4` 页面抽取参数弹窗

| 检查点 | GenOffice 源码基准 | 本轮实现与视觉证据 | 差异与后续 |
| --- | --- | --- | --- |
| 入口行为 | `App.tsx` 的页面 Ribbon `openExtractDlg` 打开参数弹窗，缩略图菜单 `extractPage` 直接使用目标页 | [七标签中的页面 Ribbon](../../../../Muse-Client/dist/pdf-product-evidence-0.1.4/ribbon-page.png) 与 [桌面抽取弹窗](../../../../Muse-Client/dist/pdf-product-evidence-0.1.4/extract-range-dialog-desktop.png)；右键菜单仍直接传页码，组件测试断言两条路径 | 其他页面按钮所需的旋转、插入、替换、分割 ABI 未完成，保持灰态 |
| 弹窗形态 | `styles.css`：距顶部 96px，最窄 300px，16px 圆角，14px 内边距，13px 标题、28px 输入框和 32px 操作按钮；`strings.ts` 给出标题及范围提示 | 签名 `chrome.json.dialogs.extractRange` 保存中文文字；Flutter 在 [1365×860](../../../../Muse-Client/dist/pdf-product-evidence-0.1.4/extract-range-dialog-desktop.png) 和 [390×844](../../../../Muse-Client/dist/pdf-product-evidence-0.1.4/extract-range-dialog-phone.png) 均可见对话框、背景文档和底栏。首张截图发现按钮中文缺字与手机缩放未就绪，已修复并重截 | Flutter 原生控件的焦点边框、阴影与浏览器 CSS 仍需同文档同主题对拍；此轮按确定性尺寸核对，不宣称整图逐像素相同 |
| 输入与内核边界 | `parsePageRanges` 接受 `1-3,5`、中文逗号/en dash，排序去重，非法范围保留对话框 | 组件测试覆盖取消、错误输入和确认；产品会话用现有 `compose` ABI 抽取指定页集，单元测试覆盖范围与越界；Host E2E 从签名包打开真实两页 PDF 后截屏 | 抽取结果先作为当前文档打开，用户通过“保存副本”写出文件；与 GenOffice 自动弹出另存流程尚有差异 |

截图均由本轮 `0.1.4` 签名包和 Host E2E 产生。测试截图使用 macOS 平台控件绘制，手机宽度截图用于响应式几何检查；Android Release 应用的设备画面另行保存。GenOffice 仓库现有公开参照图未包含此弹窗，因此弹窗逐项参照 `App.tsx`/`styles.css`/`strings.ts`，不能宣称已经取得同场景像素差分结果。

Android Release APK 安装到 `emulator-5554` 后，人工沿 OpenMuse 入口打开同一两页 PDF，保存[打开与页面状态](../../../../Muse-Client/dist/pdf-product-evidence-0.1.4/android-release-home.png)、[页面 Ribbon](../../../../Muse-Client/dist/pdf-product-evidence-0.1.4/android-release-page.png)、[真实设备抽取弹窗](../../../../Muse-Client/dist/pdf-product-evidence-0.1.4/android-release-extract-dialog.png)和[抽取第 2 页后的单页结果](../../../../Muse-Client/dist/pdf-product-evidence-0.1.4/android-release-extracted-one-page.png)。[设备操作记录及截图 SHA-256](../../../../Muse-Client/dist/pdf-product-evidence-0.1.4/manual-android-validation.json)单独保存。设备上的 IME 自动弹起时可见文档临时重排；关闭弹窗后回到 61% 适应宽度，键盘期间的重排行为需在下一轮优化。

一键构建结果见 [`quick-verify-all.json`](../dist/quick-verify-all.json)：`passed: true`，macOS、Android、自动视觉三个阶段完成。macOS `.app` 通过 `codesign --verify --deep --strict`，ZIP 通过完整性检查，APK 通过 v2/v3 签名校验。两个应用内嵌的 `pdf.mcpb` 与独立 `0.1.4` 签名包 SHA-256 同为 `908f1e3b8934b4e55acb3bf449bbeeb95c8eda09ea701ae43768afde2302bb85`。此前因共享工作区的另一个 macOS 打包进程写同一 build 目录，出现 `build.db` 锁与临时签名竞争；等待其完成后整条流水线重跑并通过。APK 使用本地测试证书供人工验证。

macOS Release `OpenMuse.app` 也已实际启动，窗口可见工作区与插件导航，内置 DSH 子进程启动；[启动窗口截图](../../../../Muse-Client/dist/pdf-product-evidence-0.1.4/macos-release-home.png)供排查此前黑屏问题。桌面 PDF 编辑器的真实文档渲染由同一轮签名包 Host E2E 截图验证，尚未在发布窗口手动走文件选择器。

## 第 4 轮：`0.1.5` 文档内搜索条与命中导航

| 检查点 | GenOffice 源码基准 | 本轮实现与视觉证据 | 差异与后续 |
| --- | --- | --- | --- |
| 入口及几何 | `App.tsx` 的开始/视图搜索按钮控制文档区右上角工具条；`styles.css` 指定 top 8px、right 20px、180×26 输入框、8px 圆角 | 签名 `chrome.json.searchBar` 提供中文标签及 180px 输入宽度；[桌面空搜索条](../../../../Muse-Client/dist/pdf-product-evidence-0.1.5/search-bar-desktop.png)、[手机 390×844 搜索条](../../../../Muse-Client/dist/pdf-product-evidence-0.1.5/search-bar-phone.png)；手机右边距缩为 8px 以完整显示 | GenOffice 原实现为网页 CSS，Flutter 焦点边框/阴影尚未同主题逐像素比对 |
| 实际检索 | `App.tsx` 维护匹配集、当前索引，并循环导航；搜索层在页面坐标上标出命中 | Flutter 编辑表面复用 `PdfTextSearcher`，从产品 PDF 会话读取结构化文本、计数、滚动和高亮；[真实两页 PDF 的 1/2 命中截图](../../../../Muse-Client/dist/pdf-product-evidence-0.1.5/search-results-desktop.png)。Host E2E 验证下一处显示 2/2，关闭后移除工具条 | GenOffice 约 200ms 防抖，当前 pdfrx 搜索器为 500ms；大文档全文搜索性能尚需基准测试 |
| 分层 | 搜索命令由产品功能区发起 | 插件只描述标签、尺寸及命令；Host 内 Flutter 编辑表面处理文档文本和高亮，`pdf-rebuild` 会话仍为唯一 PDF 数据来源 | 大纲接口尚未具备，视图大纲入口继续禁用；表单/签名能力待 PDF 内核补齐 |

本轮截图均从签名 `0.1.5` 功能包在 Host E2E 中打开固定两页 PDF 后取得。对照依据是 GenOffice `App.tsx`、`styles.css` 与 `i18n/strings.ts`；参照工程现有 PDF 截图并非同一文件和视口，故不能声称整图达到像素级 1:1。桌面/手机截图是两种视口的同一插件资源和同一 Flutter 编辑表面。完整构建与真实设备验证结果记录在本轮报告和设备截图中。

Android arm64 Release APK 在 `emulator-5554` 上重装后，从 OpenMuse「添加内容→PDF 文档」选中本地两页样本，保存了[文档、Ribbon 与底栏](../../../../Muse-Client/dist/pdf-product-evidence-0.1.5/android-release-document.png)、[搜索条全宽画面](../../../../Muse-Client/dist/pdf-product-evidence-0.1.5/android-release-search-bar.png)以及[实际命中 `1 / 2` 和文本高亮](../../../../Muse-Client/dist/pdf-product-evidence-0.1.5/android-release-search-results.png)。第一版设备画面暴露出 Android 触控目标把按钮扩宽，使浮层左侧溢出；改用固定宽度且带语义标签的点击区域后，重建 APK 并重拍，最终画面工具条完整位于文档区内。软键盘弹起时 PDF 会暂时缩小，收起后恢复 61% 适应宽度。

[联合验证报告](../dist/quick-verify-all.json) 在最终重构建后标记 `passed: true`，macOS、Android 和自动视觉三个阶段均通过。macOS Release 应用代码签名与 ZIP 完整性通过，APK 安装至上述模拟器。两端应用内置 `pdf.mcpb` 与独立签名包的 SHA-256 均为 `6d5fe355483b37f56fa3b7d069a3c7cdfa952b3aa8541a72dc9255a33a3079a8`。APK 采用本地测试签名供人工验证。

macOS Release `OpenMuse.app` 已通过 `open -n` 启动，应用进程和其打包的 DSH Node 子进程均保持运行；桌面 PDF 页面、搜索命中和七个一级 Ribbon 的可见性由同轮 Host E2E 截图验证。尚未在 Release 窗口中人工完成文件选择器打开 PDF，故不把进程存活视为这一步的证明。

## 第 5 轮：`0.1.6` 拆分 PDF 参数弹窗与页面倒序

| 检查点 | GenOffice 源码基准 | 本轮实现与视觉证据 | 差异与后续 |
| --- | --- | --- | --- |
| 页面 Ribbon | `App.tsx` 页面标签四组：旋转、增删/抽取、几何、组合；组合组中的“倒序”和“拆分 PDF”分别执行 `reversePages`、`openSplitDlg` | [七标签页面 Ribbon](../../../../Muse-Client/dist/pdf-product-evidence-0.1.6/ribbon-page.png) 保留相同顺序；签名命令目录增加 `pdf.page.reverse` 和 `pdf.page.split`，Host 实时检查两页以上及页面组合能力 | 旋转、插入、替换、裁剪、N-up 拼版所需 ABI 仍未具备，控件保持可见且禁用 |
| 拆分弹窗 | `App.tsx` 默认每文件 1 页，要求 `1 ≤ N < 总页数`；`styles.css` 弹窗距顶部 96px、最窄 300px、16px 圆角、28px 输入框、32px 按钮 | [桌面 1365×860](../../../../Muse-Client/dist/pdf-product-evidence-0.1.6/split-pdf-dialog-desktop.png)与[手机 390×844](../../../../Muse-Client/dist/pdf-product-evidence-0.1.6/split-pdf-dialog-phone.png)显示相同签名资源文案；组件测试覆盖非法 5/5、有效 2/5、取消和命令参数 | Flutter 原生输入焦点边框与 GenOffice CSS 仍有细节差异；需要同主题同 PDF 的像素对拍 |
| 文件语义 | GenOffice 选择文件夹后按每 N 页输出多个 PDF | 产品会话对当前编辑快照按页段组合，单测验证 5 页以 2 页拆成 2/2/1；Host 在各端逐个调用现有系统保存入口，取消即停止后续文件。倒序对当前页序反转后重新打开 | 当前端侧是每个分片一次保存选择器，与 GenOffice 单次文件夹选择不同；需要统一的跨端多文件导出服务后再做到 1:1 |

桌面/手机截图均由 `0.1.6` 签名包的 Host E2E 打开固定两页 PDF 后生成；源码比较来自 `App.tsx`、`styles.css` 和 `i18n/strings.ts`。本轮继续使用不同于 GenOffice 仓库示例截图的文件和窗口主题，因此不报告不可比的整图像素误差。

Android arm64 Release 设备操作补充了[真实文档、页面及状态栏](../../../../Muse-Client/dist/pdf-product-evidence-0.1.6/android-release-document.png)、[拆分弹窗](../../../../Muse-Client/dist/pdf-product-evidence-0.1.6/android-release-split-dialog.png)、[系统保存选择器](../../../../Muse-Client/dist/pdf-product-evidence-0.1.6/android-release-split-save-picker.png)与[完成提示](../../../../Muse-Client/dist/pdf-product-evidence-0.1.6/android-release-split-saved.png)。首次点“确定”暴露 Android Host 未注册 `savePdf` 平台通道；现将选择器实现放入 Host 的 `PdfDocumentSaveBridge`，并在 Android 集成测试中检查通道错误合同。修复后，从 OpenMuse 入口打开两页 PDF，按默认每文件 1 页执行拆分，系统保存两次，提示 `已保存 2/2 个拆分文件`。两个实际导出结果 [第 1 页](../../../../Muse-Client/dist/pdf-product-evidence-0.1.6/split-1.pdf)、[第 2 页](../../../../Muse-Client/dist/pdf-product-evidence-0.1.6/split-2.pdf)均由 `pdfinfo` 验证为单页，SHA-256 不同。设备操作与摘要单独记录在[人工验证清单](../../../../Muse-Client/dist/pdf-product-evidence-0.1.6/manual-android-validation.json)，自动测试没有冒充文件选择器操作。

最终再次运行 `ANDROID_SERIAL=emulator-5554 bash scripts/quick-verify.sh all`，其[联合报告](../dist/quick-verify-all.json)记录 `macos/android/visual` 全部通过。macOS Release 应用通过 `codesign --verify --deep --strict`，ZIP 71577 项完整性检查无坏项；Android 本地测试签名 APK 通过 v2/v3 验签，安装至同一模拟器并复测拆分保存。独立签名包、macOS `.app` 和 APK 内的 `pdf.mcpb` SHA-256 均为 `76ec3e1249d8583f1864cea4ac12ccaa7a22c3ba3635f358ce7d6438e0604233`。macOS Release 已启动且打包的 DSH Node 进程存活；当前 Mac 锁屏，故本轮不宣称完成 Release 窗口的人工目视检查，桌面可见性依据固定视口 Host E2E 截图。

## 第 6 轮：`0.1.7` 一次目录选择与批量拆分导出

| 检查点 | GenOffice 源码基准 | 本轮实现与证据 | 差异与后续 |
| --- | --- | --- | --- |
| Ribbon/弹窗 | `App.tsx` 的页面标签打开拆分弹窗；`styles.css` 保持 96px 顶部间距、16px 圆角及 28px 输入框 | 签名 `0.1.7` 包在固定桌面及 390px 视口打开真实两页 PDF；[页面 Ribbon](../../../../Muse-Client/dist/pdf-product-evidence-0.1.7/ribbon-page.png)、[桌面弹窗](../../../../Muse-Client/dist/pdf-product-evidence-0.1.7/split-pdf-dialog-desktop.png)、[手机弹窗](../../../../Muse-Client/dist/pdf-product-evidence-0.1.7/split-pdf-dialog-phone.png)用于本轮对拍 | 视觉几何延续上一轮，原生输入焦点边框和 GenOffice 浏览器 CSS 尚未同场景像素校准 |
| 导出选择器 | `pdf-main.ts` 的 `splitPdf` IPC 只打开一次目录选择器，输出 `{base}-{index}.pdf` | 签名 `chrome.json.dialogs.splitPdf` 声明 `destinationMode=directory` 和文件名模板；Flutter 解释策略，Android Host 提供目录选择与批量写入，桌面端同卷暂存后发布 | 各 OS 的原生目录选择器外观不同；Android 失败时删除本次新建文件为尽力回滚，无法保证云文档 Provider 原子性 |
| 分层和可用性 | GenOffice 的 UI 调用低频文件操作服务 | 插件只管理交互/命名策略；PDF 会话负责页面组合；Host 负责本地目标授权和写入。Android 集成测试检查批量通道，桌面单测检查两文件写入与既有文件不覆盖 | iOS/Web 暂用逐文件降级路径，未纳入本轮 Mac/Android 交付矩阵 |

本轮仍使用与 GenOffice README 图不同的文档、主题和系统选择器；参考图只能做结构对照，不能把整图像素差称为 1:1。设备端真实目录选择与导出结果记录在本轮人工验证清单。

本轮 Android Release APK 在 `emulator-5554` 从 OpenMuse 入口打开两页样本，实际保存了[文档/Ribbon/状态栏](../../../../Muse-Client/dist/pdf-product-evidence-0.1.7/android-release-document.png)、[拆分弹窗](../../../../Muse-Client/dist/pdf-product-evidence-0.1.7/android-release-split-dialog.png)、[一次目录选择](../../../../Muse-Client/dist/pdf-product-evidence-0.1.7/android-release-directory-picker.png)和[保存 2/2 反馈](../../../../Muse-Client/dist/pdf-product-evidence-0.1.7/android-release-split-saved.png)。目标目录产出的 `pdf-017-source-1.pdf`、`pdf-017-source-2.pdf` 各为一页、摘要不同；[人工验证记录](../../../../Muse-Client/dist/pdf-product-evidence-0.1.7/manual-android-validation.json)保存设备步骤及截图 SHA-256。[联合构建报告](../dist/quick-verify-all.json) 的 `macos/android/visual` 均通过；macOS `.app` 通过严格签名验证、ZIP 完整性检查，APK 通过 Android v2/v3 验签。独立签名包与两个应用内嵌 `pdf.mcpb` 的 SHA-256 均为 `ff97147ac0750cadccd4ee8c845ce19efdf41453843a1eab4d5270afa1bea148`。macOS Release 窗口受当前锁屏限制，桌面可见性依赖固定视口 Host E2E 截图，未宣称完成手工窗口目视验收。构建脚本现将 macOS ZIP 另存为含 PDF 产品版本号的文件，避免共享输出路径被并行构建覆盖。

## 第 7 轮：`0.1.8` 抽取结果落盘及 GenOffice 文件名

| 检查点 | GenOffice 源码基准 | 本轮实现与证据 | 差异与后续 |
| --- | --- | --- | --- |
| 页面 Ribbon 和范围弹窗 | `App.tsx` 的 `openExtractDlg`/`confirmExtract` 使用当前页作默认值，范围解析后调用 `extractPagesToFile` | 签名 `0.1.8` 包保留七标签与多级菜单；[页面 Ribbon](../../../../Muse-Client/dist/pdf-product-evidence-0.1.8/ribbon-page.png)、[桌面弹窗](../../../../Muse-Client/dist/pdf-product-evidence-0.1.8/extract-range-dialog-desktop.png)、[手机弹窗](../../../../Muse-Client/dist/pdf-product-evidence-0.1.8/extract-range-dialog-phone.png)来自本轮真实两页 PDF 的 Host E2E | 弹窗几何与上轮相同，仍需相同系统字体和视口逐像素对拍 |
| 抽取生成文件 | `extractPagesToFile` 按首末页生成 `-pN`/`-pN-M`，`pdf-main.ts` 写入默认保存目录并打开结果 | 插件声明单页/页集命名模板与目标策略；桌面写入 `Documents/OpenMuse` 并安全处理重名，Android 由 Host 系统保存选择器获取授权；成功后打开抽取结果 | GenOffice 的默认目录支持用户配置，当前 OpenMuse 未提供同等 Host 设置；Android 系统选择器有平台原生外观 |
| 架构边界 | UI 发低频文件操作到 Electron 主进程 | 插件仅描述 UI/文件名策略；`ioffice` PDF 产品会话组合页面，Flutter 保存端口及 Android Host 授权写入，不将插件代码置于渲染/逐字编辑路径 | 需在后续 Host ABI 中提供可配置的桌面默认目录与状态通知 |

弹窗的源码几何逐项核对为：`styles.css` 顶部 96px、最窄 300px、圆角 16px、内边距 14px、标题 13px/600、输入高 28px；Flutter `PdfProductShell._showPageInputDialog` 对应值分别是 `insetPadding.top=96`、`minWidth=300`、`BorderRadius.circular(16)`、`padding=14`、`fontSize=13/fontWeight.w600`、`SizedBox(height:28)`。本轮桌面和 390px 手机截图展示上述布局在实际文档上的位置；浏览器与 Flutter 字体栅格、系统选择器外观未做像素同源差分。

本轮自动化截图、实际设备保存和构建摘要在 `pdf-product-evidence-0.1.8/` 与 `dist/quick-verify-all.json`；以下一节仍按真实目标端验收推进。整图像素级 1:1 需同一 PDF、字体、DPI、主题和 GenOffice 参照进程截图才能宣称。

Android arm64 Release APK 已在 `emulator-5554` 重新安装，人工从 OpenMuse 打开两页样本后保存[文档/Ribbon/底栏](../../../../Muse-Client/dist/pdf-product-evidence-0.1.8/android-release-document.png)、[抽取弹窗](../../../../Muse-Client/dist/pdf-product-evidence-0.1.8/android-release-extract-dialog.png)、[系统保存选择器与 GenOffice 同式文件名](../../../../Muse-Client/dist/pdf-product-evidence-0.1.8/android-release-save-picker.png)、[保存成功反馈](../../../../Muse-Client/dist/pdf-product-evidence-0.1.8/android-release-extract-saved.png)和[单页结果](../../../../Muse-Client/dist/pdf-product-evidence-0.1.8/android-release-extracted-one-page.png)。实际落盘的 `pdf-018-source-p1.pdf` 经独立 `pdfinfo` 检查为一页；[人工验证记录](../../../../Muse-Client/dist/pdf-product-evidence-0.1.8/manual-android-validation.json)包含步骤、截图和文件 SHA-256。[联合报告](../dist/quick-verify-all.json) 标记 `macos/android/visual` 全部通过。独立签名包、macOS ZIP 与 APK 内置的 `pdf.mcpb` SHA-256 都为 `a99eef3cb2bfd86cecf52586bcfdc4d14e98b0d704e710cdbd47880a9f347167`；macOS `.app` 严格签名、ZIP 完整性和 APK v2/v3 验签均通过。macOS Release 窗口仍受锁屏限制，未把自动截图当作 Release 窗口的人工目视验收。

## 第 8 轮：`0.1.9` 底栏缩放合同

| 检查点 | GenOffice 源码基准 | 本轮实现与视觉证据 | 剩余差异 |
| --- | --- | --- | --- |
| 整体壳 | `App.tsx` 七标签 Ribbon、文档列与底栏；仓内 [PDF 参照图](../../../../Muse-Client/dist/pdf-product-evidence-0.1.9/genoffice-reference.webp) | 同一 `0.1.9` 签名包打开真实两页 PDF 的 [1365×860 桌面截图](../../../../Muse-Client/dist/pdf-product-evidence-0.1.9/ribbon-home.png)、[390×844 手机截图](../../../../Muse-Client/dist/pdf-product-evidence-0.1.9/phone-home.png)、[转换菜单](../../../../Muse-Client/dist/pdf-product-evidence-0.1.9/ribbon-home-convert-menu.png)；已去除测试框架角标 | 参照图是 2400×1530、浅色英文、AI 面板展开且文档不同；只能比较结构，不能计算整图像素一致率 |
| 底栏几何 | `styles.css`：底栏 24px、缩放滑杆 110px、按钮 20px、百分比最窄 38px；只跨文档列 | Flutter 桌面底栏 24px，只跨文档列，滑杆 110px、按钮实际渲染宽度 20px、百分比 38px；手机按钮保留 48px 触控目标。底栏高度、滑杆宽度与文案由签名 `chrome.json` 描述，页面和缩放值来自唯一 PDF 会话 | Flutter Slider 与浏览器原生 range 的轨道、滑块及抗锯齿仍有可见差异；待同主题同系统字体对拍 |
| 缩放行为 | `view-config.ts`：10%–800%，18 个加减档位；`App.tsx` 滑杆 5% 步进 | 签名资源声明范围、步进、档位和文案；Flutter 加减/滑杆统一调用 `onZoom`，组件测试检查 100%→110%/90% 和范围 | `pdfrx` 页面矩阵渲染与 PDF.js 在极值缩放下需目标端性能及边界验证 |

本轮联合构建及真实文档渲染见 [报告](../dist/quick-verify-all.json)：`macos/android/visual` 均通过。macOS Release 应用经 `codesign --verify --deep --strict`，Android arm64 本地测试 APK 经 v2/v3 验签并安装至 `emulator-5554`；独立签名包与两个应用内嵌 `pdf.mcpb` 的 SHA-256 均为 `d0d89a0b427be35e911ba5165d0d9068d8670fcdf0351f194baec69758f80ae8`。上述桌面、手机宽度图来自 Host 自动 E2E。另在 Android Release 进程内从「添加内容→PDF 文档」打开两页样本，保存[61% 页面与底栏](../../../../Muse-Client/dist/pdf-product-evidence-0.1.9/android-release-document.png)，点击底栏放大后保存[67% 档位](../../../../Muse-Client/dist/pdf-product-evidence-0.1.9/android-release-zoom-67.png)；[设备操作与截图摘要](../../../../Muse-Client/dist/pdf-product-evidence-0.1.9/manual-android-validation.json)单独记录。macOS Release 的窗口级人工 PDF 打开仍未验收，桌面可见性以 Host E2E 为据。

下一轮仍需完成可配置桌面默认目录、会话状态反馈与同场景逐区像素对拍；发行候选门禁维持不变。

## 第 9 轮：`0.1.10` 文档侧栏宽度与缩略图栅格

| 检查点 | GenOffice 源码基准 | 本轮实现与视觉证据 | 剩余差异 |
| --- | --- | --- | --- |
| 整壳结构 | `App.tsx` 的七标签 Ribbon、文档侧栏、页面列与底栏；仓内 [PDF 参照图](../../../../Muse-Client/dist/pdf-product-evidence-0.1.10/genoffice-reference.webp) | 同一签名包打开真实两页 PDF 的 [桌面默认宽度](../../../../Muse-Client/dist/pdf-product-evidence-0.1.10/ribbon-home.png)、[桌面拉宽侧栏](../../../../Muse-Client/dist/pdf-product-evidence-0.1.10/sidebar-resized-desktop.png)、[390px 手机宽度](../../../../Muse-Client/dist/pdf-product-evidence-0.1.10/phone-home.png)；七标签和多级 [转换菜单](../../../../Muse-Client/dist/pdf-product-evidence-0.1.10/ribbon-home-convert-menu.png)继续可达 | 参照图与测试图的 PDF、语言、主题和视口不同，只能比较结构与源码尺寸，尚不能计算整图像素一致率 |
| 侧栏边界与缩略图 | `view-config.ts` 默认 150px、最小 120px、最大 `min(320px, round(窗口宽度 × 0.4))`，缩略图宽度为侧栏减 24px；`styles.css` 内边距 10px、页间距 3px + 10px，6px 拖拽条向左覆盖边框 3px | 签名 `chrome.json.sidebar` 声明相同尺寸合同、覆盖量和持久化键；Flutter 壳沿用产品会话的页面渲染，固定 1365×860 图中默认与拉宽后的页面列和缩略图均可见。组件测试覆盖上限、拖动结束重新栅格化、重建后恢复宽度；Host 测试检查拖拽条左缘与侧栏右缘相差 3px，以及拉宽后的非空缩略图 | 不同字体栅格和 PDF 内容仍无法在本轮做整图像素差分 |
| 状态与交互分层 | `App.tsx` 拖动时仅更新侧栏宽度，松开后重绘缩略图并写入偏好 | 插件资源描述壳合同；Flutter 仅管理交互和偏好，页面数据、页面栅格与编辑命令仍由 PDF 产品会话提供。缩略图不会在每个指针移动帧触发重新栅格化 | 大文档缩略图缓存与拖动帧率需性能语料验证；保存/只读状态仍待从会话推送 |

本轮固定视口截图由 Desktop Host E2E 从 `0.1.10` 签名包打开测试 PDF 后取得。参照图保留在证据目录，便于人工逐区查看；整图主题和内容条件不同，不能宣称已经达成逐像素 1:1。

最终 `ANDROID_SERIAL=emulator-5554 bash scripts/quick-verify.sh all` [联合报告](../dist/quick-verify-all.json) 的 `macos/android/visual` 均通过。macOS `.app` 严格代码签名校验和 ZIP 完整性检查通过，Android arm64 本地测试 APK 经 v2/v3 验签并安装；独立签名包、macOS `.app` 与 APK 内置 `pdf.mcpb` 的 SHA-256 一致，均为 `5f4834596a6c4ec13b4447a77336a7e63183756c85f6791a692f06bd5ad8b9a4`。Android Release 进程从「添加内容→PDF 文档」打开两页样本后的[页面、Ribbon 与底栏](../../../../Muse-Client/dist/pdf-product-evidence-0.1.10/android-release-document.png)，以及底栏入口打开的[两页缩略图](../../../../Muse-Client/dist/pdf-product-evidence-0.1.10/android-release-thumbnails.png)，均有独立的[设备操作记录与截图摘要](../../../../Muse-Client/dist/pdf-product-evidence-0.1.10/manual-android-validation.json)。macOS 发布窗口的人工文件选择器流程尚未在本轮执行，桌面实际文档的可见性以 Host E2E 截图为据。

## 第 10 轮：`0.1.11` AI dock 与中央编辑区重排

| 检查点 | GenOffice 源码基准 | 本轮实现与视觉证据 | 剩余差异 |
| --- | --- | --- | --- |
| 顶部 Ribbon 与 AI 入口 | `App.tsx` 的 AI 主按钮开合左侧 dock，活动态有底色；七个标签继续位于 35px 标签行 | 签名 `presentations.ai=panelToggle` 只触发壳状态，AI 总结/要点继续由能力门禁控制；[桌面展开](../../../../Muse-Client/dist/pdf-product-evidence-0.1.11/ai-dock-expanded-desktop.png)、[多级转换菜单](../../../../Muse-Client/dist/pdf-product-evidence-0.1.11/ribbon-home-convert-menu.png) | AI 命令的真实执行需独立 AI 插件和 Host 授权 |
| 左侧 dock | `styles.css` 收起 34px、展开默认 360px、180ms 动画；`AiPanel.tsx` 限宽 280–720px 与视口 60%，右边缘拖拽条 6px | 签名 `chrome.json.aiDock` 配置几何、文案和偏好键；[收起轨道](../../../../Muse-Client/dist/pdf-product-evidence-0.1.11/ribbon-home.png)、[360px 展开](../../../../Muse-Client/dist/pdf-product-evidence-0.1.11/ai-dock-expanded-desktop.png)、[440px 拉宽](../../../../Muse-Client/dist/pdf-product-evidence-0.1.11/ai-dock-resized-desktop.png)来自同一真实 PDF 会话；测试检查宽度、恢复和拖拽位移 | GenOffice 参照截图使用不同 PDF、语言、主题和视口，尚不能做整图像素差分 |
| 编辑区与底栏 | AI 面板占左列，缩略图和文档右移；24px 底栏只跨文档列 | 三张桌面图可见页面、缩略图及底栏随 dock 宽度重排，手机以[底部面板](../../../../Muse-Client/dist/pdf-product-evidence-0.1.11/ai-dock-phone-sheet.png)呈现相同插件声明 | 手机是 OpenMuse 的目标端适配，GenOffice 参照仅为桌面窗口 |
| 领域边界 | AI 面板内容由 AI 服务和聊天会话负责 | Flutter `PdfProductShell.assistantContent` 仅留视图槽；未连接 AI 插件时快捷按钮与输入不可发送并显示原因，PDF 渲染与编辑仍由 PDF 产品会话负责 | 接入真实 AI 插件后需保持聊天历史在收起/展开间不丢失 |

[本轮并列视觉对照](../../../../Muse-Client/dist/pdf-product-evidence-0.1.11/VISUAL-COMPARISON.md)保留 GenOffice 原图与本轮图片，按区域记录源码尺寸及剩余差异；参照图内容不同，不声明整壳已经逐像素 1:1。

最终运行 `ANDROID_SERIAL=emulator-5554 bash scripts/quick-verify.sh all`，其[联合报告](../dist/quick-verify-all.json)记录 `macos/android/visual` 全部通过。macOS Release `.app` 经 `codesign --verify --deep --strict` 校验，ZIP 无坏项；Android arm64 本地测试 APK 经 v2/v3 验签并安装。独立签名包、macOS `.app`、macOS ZIP 与 APK 内置 `pdf.mcpb` 的 SHA-256 均为 `de019c4da033d31cf37f09d288683a7702999920f42c3f444c33b924af7d908b`。Android Release 进程从 OpenMuse 入口打开真实 PDF 后保存[页面、Ribbon、底栏](../../../../Muse-Client/dist/pdf-product-evidence-0.1.11/android-release-document.png)，随后打开[AI 底部面板](../../../../Muse-Client/dist/pdf-product-evidence-0.1.11/android-release-ai-dock.png)；[设备操作记录](../../../../Muse-Client/dist/pdf-product-evidence-0.1.11/manual-android-validation.json)保存步骤与截图摘要。桌面实际文档可见性依据固定视口 Host E2E 截图；macOS Release 的人工文件选择器流程仍待目标机人工验收。

## 第 11 轮：`0.1.12` Ribbon 保存状态与会话事实

| 检查点 | GenOffice 源码基准 | 本轮实现与视觉证据 | 剩余差异 |
| --- | --- | --- | --- |
| 顶部标签行 | `App.tsx` 在 35px 标签行右侧显示未保存、保存中、已保存、失败及只读；`styles.css` 文案 12px、成功色 `#58b380`、失败色 `#e57373` | 签名 `chrome.json.ribbonState` 声明文案、字号与颜色；`PdfProductShell` 从 `PdfDocumentStatus` 展示状态，不从按钮点击推测是否写入；本轮真实 PDF 壳图与独立状态样本见视觉对照 | OpenMuse 当前命令为另存副本，不能把成功反馈说成源文件已保存 |
| 会话与操作分层 | GenOffice `dirty` 来自编辑状态，`saveState` 来自保存流程；保存中禁用保存按钮 | `PdfWorkspace` 从 `PdfProductBackend.isDirty` 取待保存事实，副本保存生命周期独立建模；保存中禁用重复点击，取消选择器回到原状态，失败显示错误说明，新文档切换不会继承旧副本反馈 | 加密文档只读状态已经有壳合同与组件测试；产品后端尚未向 Host 暴露完整只读原因 |
| 内容区与底栏 | Ribbon 状态不改变文档列与 24px 底栏 | 同一签名包 Host E2E 仍打开真实两页 PDF，并生成七标签、多级菜单、AI dock、页面与底栏截图 | 逐像素 1:1 仍需相同 PDF、字体、主题、DPI、视口与目标进程 |

本轮 `ribbon-state-unsaved-desktop.png` 与 `ribbon-state-saving-desktop.png` 是使用签名资源和注入会话事实绘制的组件状态样本，不能作为真实文件写入证据；真实 PDF 渲染与 Android Release 设备操作另行记录。

[本轮视觉对照](../../../../Muse-Client/dist/pdf-product-evidence-0.1.12/VISUAL-COMPARISON.md)并列 GenOffice 原图、真实 PDF 的 OpenMuse 桌面壳及 Ribbon 状态样本。Android arm64 Release APK 在 `emulator-5556` 从 OpenMuse 入口打开固定两页 PDF，记录[页面、Ribbon、底栏](../../../../Muse-Client/dist/pdf-product-evidence-0.1.12/android-release-document.png)、[系统保存选择器](../../../../Muse-Client/dist/pdf-product-evidence-0.1.12/android-release-save-picker.png)和[“副本已保存”反馈](../../../../Muse-Client/dist/pdf-product-evidence-0.1.12/android-release-copy-saved.png)；取回的[副本](../../../../Muse-Client/dist/pdf-product-evidence-0.1.12/pdf-012-copy.pdf)经 `pdfinfo` 验证为两页，SHA-256 与源文件同为 `52dfc4d2118d34a7b7598e18b96c1dc9b70fee84512ed0e3f28ccf28821e9a43`。[人工操作记录](../../../../Muse-Client/dist/pdf-product-evidence-0.1.12/manual-android-validation.json)保存设备文件名和截图摘要。

本轮第一次 `all` 命令完成 macOS 和视觉阶段后，原 `emulator-5554` 下线；第二次 `all` 命令在共享构建目录的 macOS 外层签名校验处停止。因此没有把任一单次 `all` 报告写成全绿。[分阶段交付报告](../../../../Muse-Client/dist/pdf-product-evidence-0.1.12/delivery-report.json)保存三个运行日志、独立核验和构建摘要。第一次生成的 0.1.12 macOS ZIP 完整性通过，独立解包后 `.app` 通过 `codesign --verify --deep --strict`；在 `emulator-5556` 单独执行的 Android 门禁通过、APK 经 v2/v3 验签并安装。独立签名包、macOS ZIP 与 APK 内的 `pdf.mcpb` SHA-256 均为 `2fea628778e9ce11b202df73c2ef856d49b2b8a9ec77db738c23ecd06008289c`。macOS Release 窗口的人工文件选择器流程仍待目标机验收。

## 第 12 轮：0.1.13 浅色整壳主题与双调色板

本轮按 GenOffice `packages/ui/src/tokens.css` 和 `apps/pdf/src/renderer/styles.css` 的明确色值修正默认主题。签名 `chrome.json.themes` 同时保存浅色和深色，默认浅色；Flutter `PdfChromeDefinition` 只解析并选择调色板，Ribbon、侧栏、文档画布、菜单、状态栏和保存反馈共用选择结果。主题不进入 PDF 文件领域模型。来源、整壳并列截图、菜单和手机截图集中在[本轮视觉对照](../../../../Muse-Client/dist/pdf-product-evidence-0.1.13/VISUAL-COMPARISON.md)。参照图与自动截图文档、语言、窗口尺寸及 AI 面板状态仍不同；对照文件明确列出已核对的色值和剩余视觉差异。

`ANDROID_SERIAL=emulator-5556 bash scripts/quick-verify.sh all` 的[联合报告](../dist/quick-verify-all.json)为 `passed: true`，macOS、Android 和视觉三个阶段均完成。macOS ZIP 完整性与构建出的 `.app` 严格代码签名校验通过；Android APK 的 v2/v3 签名通过，并已安装到模拟器。从 Release APK 的 OpenMuse 本地入口打开真实两页 PDF 的[设备截图](../../../../Muse-Client/dist/pdf-product-evidence-0.1.13/android-release-document.png)显示浅色 Ribbon、画布及底栏。独立签名插件、macOS ZIP 和 APK 内的 `pdf.mcpb` SHA-256 一致，均为 `7b90785e3abd6b7fbffbbd94ee0e10961e3b5226dd7709502cc06ceb0bd13b80`；详见[交付报告](../../../../Muse-Client/dist/pdf-product-evidence-0.1.13/delivery-report.json)。APK 使用本地测试证书供人工验证。

## 第 13 轮：0.1.14 多级 Ribbon 菜单几何

本轮对照 GenOffice `.rb-drop`、`.rb-menu`、`.thumb-menu` 修正菜单最小宽、条目高度、锚点偏移、圆角、边框和阴影。可签名的 `chrome.json.menuPresentation` 将 Ribbon、缩略图与色板三类弹层分开；Flutter 解释器固定视觉密度，并由 Host E2E 在真实两页 PDF 截图中断言命令菜单条目为 28px。上一轮与本轮菜单并列截图、整壳参考及剩余差异见[0.1.14 视觉对照](../../../../Muse-Client/dist/pdf-product-evidence-0.1.14/VISUAL-COMPARISON.md)。

初次联合构建因磁盘空间耗尽停在 macOS 外层打包；清理本任务早先使用的临时验签解包和不参与本轮 arm64 构建的旧 armv7 中间缓存后，`ANDROID_SERIAL=emulator-5556 bash scripts/quick-verify.sh all` 重跑成功。[联合报告](../dist/quick-verify-all.json)记录 `passed: true`，macOS、Android、视觉三阶段完成。macOS ZIP 完整性和构建应用严格代码签名通过，APK v2/v3 验签并安装。独立签名包、macOS ZIP 与 APK 内 `pdf.mcpb` SHA-256 均为 `7fdd35ed377035e35c52124de2e7d22b0b564f062c801eb44ab10337ab23b2c9`。Android Release 设备上打开固定两页 PDF 后，[内容与底栏](../../../../Muse-Client/dist/pdf-product-evidence-0.1.14/android-release-document.png)及[水平滚动后的转换菜单](../../../../Muse-Client/dist/pdf-product-evidence-0.1.14/android-release-convert-menu.png)均已留图；详见[交付报告](../../../../Muse-Client/dist/pdf-product-evidence-0.1.14/delivery-report.json)。APK 为本地测试签名，供人工验收。

## 第 14 轮：0.1.15 AI 初始状态与同物理视口对拍

GenOffice `packages/ui/src/ai-panel-prefs.ts` 将 `openInNewDocs` 与 `showAiSidebar` 默认设为 `true`；`ai-panel-prefs-store.ts` 在没有记忆值时返回展开，PDF `App.tsx` 读取该值并记住开合。`styles.css` 声明 360px 面板、34px 收起轨道及 180ms 宽度动画，并在收起时保留聊天组件。OpenMuse 的签名 `chrome.json.aiDock.initiallyOpen` 现为 `true`，Flutter 仍读取持久偏好覆盖默认值；面板收起时通过 `Offstage` 保留注入的 AI 视图，组件测试验证草稿在再次打开后仍存在。未连接 AI 插件时，发送与快捷命令保持禁用。

| GenOffice 仓内 2400×1530 参照 | OpenMuse 2400×1530 同物理尺寸截屏 |
| --- | --- |
| ![GenOffice PDF 壳](../../../../Muse-Client/dist/pdf-product-evidence-0.1.15/genoffice-reference.webp) | ![OpenMuse 0.1.15 PDF 壳](../../../../Muse-Client/dist/pdf-product-evidence-0.1.15/genoffice-viewport-desktop.png) |

[并列合成图](../../../../Muse-Client/dist/pdf-product-evidence-0.1.15/genoffice-openmuse-side-by-side.png)保留两张原图，左为 GenOffice、右为 OpenMuse；[本轮完整视觉对照](../../../../Muse-Client/dist/pdf-product-evidence-0.1.15/VISUAL-COMPARISON.md)还列出 0.1.14→0.1.15 默认状态的前后图。OpenMuse 截图由签名插件经 Desktop Host E2E 打开真实两页 PDF，在 2400×1530 物理像素与 1.5 DPR 下拍摄。1.5 DPR 是根据参照图控件物理尺寸选择的对拍条件，GenOffice 原图的实际 DPR 未由截图证明；其外层应用窗口、英文三页业务文档、已连接 AI 对话与 OpenMuse 的测试文档、中文、未连接 AI 并非同一场景，因此此图只作可见结构对照，不给出像素一致率。

| 区域 | 源码合同与本轮验证 | 剩余差异 |
| --- | --- | --- |
| 顶部多级 Ribbon | 七标签、命令组、二级转换菜单继续由签名资源驱动；桌面菜单与 Android Release 菜单均截屏，未接转换能力保持禁用 | 英中标签宽度和字体栅格不同；GenOffice 外层应用标签栏属于 Host |
| AI、缩略图与编辑区 | 360px AI 默认展开、150px 缩略图、文档列右移；Host 断言 AI 宽度及侧栏起点；收起/拉宽、页面渲染继续通过测试 | GenOffice 参照有真实 AI 对话和三页复杂 PDF，OpenMuse 无 AI 提供者且测试文档仅两页；复杂编辑覆盖层尚需内核语料 |
| 底部状态栏 | 24px 底栏仍仅跨文档列；签名 `statusBar.minSliderColumnWidth=380` 控制窄列隐藏 110px 滑杆，保留页码和缩放按钮，700px 窄窗测试无溢出 | 全量功能与高 DPI 字体仍需同条件目标进程验收 |

`ANDROID_SERIAL=emulator-5556 bash scripts/quick-verify.sh all` 的[联合报告](../dist/quick-verify-all.json)为 `passed: true`；随后从最终 Android Release 入口手动打开 PDF，留存[页面与底栏](../../../../Muse-Client/dist/pdf-product-evidence-0.1.15/android-release-document.png)、[AI 底部面板](../../../../Muse-Client/dist/pdf-product-evidence-0.1.15/android-release-ai-sheet.png)和[转换菜单](../../../../Muse-Client/dist/pdf-product-evidence-0.1.15/android-release-convert-menu.png)。macOS ZIP 完整性与严格代码签名、APK v2/v3 签名均通过，ZIP 和 APK 内置插件与独立 `.mcpb` 的 SHA-256 同为 `36325cb4e6f1f73ecc8e952d5b87203002f7f9566c3dff162da2f9cf5bba8f8b`。详见[交付报告](../../../../Muse-Client/dist/pdf-product-evidence-0.1.15/delivery-report.json)。APK 使用本地测试签名。

## 第 15 轮：0.1.16 中央页面视口

本轮按 GenOffice PDF `styles.css` 的 `.pdf-scroll { padding: 0 24px }`、`.pdf-row` 的 16px 上边/页间距，以及 `--pdf-shadow-page: 0 1px 4px rgb(0 0 0 / 18%)` 对齐页面画布。`view-config.ts` 的 `SCROLL_PAD=24`、`PAGE_GAP=16` 与此一致。签名 `chrome.json.pageViewport` 现在描述视口尺寸和阴影，Flutter PDF 表面负责解释，不将这些值写进 Host。旧签名包缺少该资源时沿用旧视口默认值。

| GenOffice 仓内 2400×1530 参照 | OpenMuse 本轮同物理尺寸截图 |
| --- | --- |
| ![GenOffice PDF 壳](../../../../Muse-Client/dist/pdf-product-evidence-0.1.16/genoffice-reference.webp) | ![OpenMuse 0.1.16 PDF 壳](../../../../Muse-Client/dist/pdf-product-evidence-0.1.16/genoffice-viewport-desktop.png) |

[0.1.15→0.1.16 前后并列图](../../../../Muse-Client/dist/pdf-product-evidence-0.1.16/page-viewport-before-after.png)使用同一真实两页 PDF 和 Desktop Host E2E；Host 断言首页面左边距 24px、两页间距 16px、阴影 `0 1px 4px / 18%`。本轮[完整视觉对照](../../../../Muse-Client/dist/pdf-product-evidence-0.1.16/VISUAL-COMPARISON.md)列出 Ribbon、中央内容区、侧栏与底栏的证据及差异。原版参照文档与测试 PDF、语言、AI 状态及已知 DPR 条件不同，整图像素级 1:1 仍待同条件对拍。

联合构建、Android Release 进程截图及安装包验签结果见[交付报告](../../../../Muse-Client/dist/pdf-product-evidence-0.1.16/delivery-report.json)。

## 第 16 轮：0.1.17 可配置的桌面生成文件目录

GenOffice `packages/electron-utils/src/default-save-dir.ts` 从用户设置读取 `defaultSaveDir`，目标目录不可用时退回文档目录；PDF `pdf-main.ts` 抽页使用该目录和 `generated-output.ts` 的防覆盖命名。本轮在 OpenMuse Host 工作区设置中加入生成文件默认目录，PDF 产品通过注入的读取端口消费该偏好。目录可用性与回退在写入当下判定；签名 `chrome.json.dialogs.extractRange.desktopDestination=generatedDirectory` 继续决定抽页目的地，Host 不持有 PDF 页面内容。

| GenOffice 仓内 2400×1530 参照 | OpenMuse 本轮同物理尺寸 PDF 壳 |
| --- | --- |
| ![GenOffice PDF 壳](../../../../Muse-Client/dist/pdf-product-evidence-0.1.17/genoffice-reference.webp) | ![OpenMuse 0.1.17 PDF 壳](../../../../Muse-Client/dist/pdf-product-evidence-0.1.17/genoffice-viewport-desktop.png) |

[完整视觉与行为对照](../../../../Muse-Client/dist/pdf-product-evidence-0.1.17/VISUAL-COMPARISON.md)另附[桌面设置入口](../../../../Muse-Client/dist/pdf-product-evidence-0.1.17/generated-output-settings-desktop.png)、七标签、抽页弹窗、转换菜单和底栏截图。真实两页 PDF 的 Host E2E 从页面 Ribbon 抽取第 1 页并在配置目录落盘；独立 `pdfinfo` 确认[结果 PDF](../../../../Muse-Client/dist/pdf-product-evidence-0.1.17/extracted-one-page.pdf)为一页。GenOffice 在新标签打开生成文件，OpenMuse 当前在工作区内打开结果，这一行为差异留待下一轮 Host 标签端口。文档内容、语言、DPR 和 AI 状态仍不同，尚不能计算整图像素一致率。

双端构建、安装包验签、Android Release 设备截图和产物摘要见[交付报告](../../../../Muse-Client/dist/pdf-product-evidence-0.1.17/delivery-report.json)。

## 第 17 轮：0.1.18 生成 PDF 的新标签导航

GenOffice `apps/pdf/src/main/pdf-main.ts` 在抽页文件持久化后调用 `openGeneratedPdf`，交由外层 Shell 打开新 PDF 标签；独立模式没有标签路由时显示生成文件位置。OpenMuse 的签名 `chrome.json.dialogs.extractRange.desktopOpenResult=newDocumentTab` 声明策略，`ioffice` 产品会话完成抽页后通过端口交付实际文件路径，Host 校验路径并创建工作区标签。真实两页 PDF 的 E2E 断言原标签与源页面数保留，生成文件成为活动标签，独立 `pdfinfo` 验证结果为一页。无 Host 标签端口的移动/独立表面保持原有结果打开流程。

| GenOffice 仓内参照 | OpenMuse 0.1.18 同物理尺寸壳 |
| --- | --- |
| ![GenOffice PDF 壳](../../../../Muse-Client/dist/pdf-product-evidence-0.1.18/genoffice-reference.webp) | ![OpenMuse PDF 壳](../../../../Muse-Client/dist/pdf-product-evidence-0.1.18/genoffice-viewport-desktop.png) |

[本轮完整视觉对照](../../../../Muse-Client/dist/pdf-product-evidence-0.1.18/VISUAL-COMPARISON.md)包含 GenOffice 并列图、七标签与菜单、桌面前后图、Android Release 打开真实 PDF 与转换菜单截图。`0.1.17` 和 `0.1.18` 的默认桌面整壳截图在相同视口与语料下 RGB 像素完全一致；本轮是行为对齐，没有引入外观变化。参照与实现的文档、语言和 AI 状态仍不同，完整逐像素 1:1 尚未完成。[联合门禁与交付报告](../../../../Muse-Client/dist/pdf-product-evidence-0.1.18/delivery-report.json)记录 macOS 和 Android 构建、签名及内嵌插件摘要。

## 第 18 轮：0.1.19 签名快捷键与翻页顶部锚点

对照 GenOffice `apps/pdf/src/renderer/App.tsx` 的 ⌘S、⌘Z/⇧⌘Z、⌘F、⌘±、⌘0 与 `keyNav.ts` 的左右翻页，本轮将快捷键到命令的绑定加入签名 `chrome.json.keyboardShortcuts`。Flutter 壳只解释按键，仍经产品命令可用性门禁和会话端口执行；文本输入中的撤销保留给原生编辑控件。右箭头切到末页时，PDFium 默认末页底部锚点曾让页面正文离开视口；产品会话现在显式按顶部锚点跳页，缩略图、页码和正文同步可见。

| GenOffice 2400×1530 参照 | OpenMuse 2400×1530 最终首页 |
| --- | --- |
| ![GenOffice PDF 壳](../../../../Muse-Client/dist/pdf-product-evidence-0.1.19/genoffice-reference.webp) | ![OpenMuse PDF 壳](../../../../Muse-Client/dist/pdf-product-evidence-0.1.19/genoffice-viewport-desktop.png) |

[本轮完整视觉对照](../../../../Muse-Client/dist/pdf-product-evidence-0.1.19/VISUAL-COMPARISON.md)同时列出[键盘进入第 2 页](../../../../Muse-Client/dist/pdf-product-evidence-0.1.19/keyboard-next-page-desktop.png)、[⌘F 搜索浮层](../../../../Muse-Client/dist/pdf-product-evidence-0.1.19/keyboard-search-desktop.png)、七标签、转换菜单和底栏证据。改动前后默认首页截图逐字节相同；最终两张键盘截图显示新的可见交互状态。原版参照仍是英文三页业务 PDF 且 AI 已连接，OpenMuse 使用中文壳与两页测试文档，因此不宣称整图像素级 1:1。

签名包验证、PDF 原生集成流程、最终 Host 截图测试、macOS Release 严格代码签名和 ZIP 完整性均通过。单次 `quick-verify macos` 的第一次运行遇到并行 Host 依赖更新，第二次完成测试和 Release 构建后因复制版本化 ZIP 时磁盘不足而停止；随后使用可再生构建缓存清理、APFS 克隆副本、最终源码重打包与复验完成分阶段交付。实际检查项、日志与 SHA-256 见[交付报告](../../../../Muse-Client/dist/pdf-product-evidence-0.1.19/delivery-report.json)；报告明确保留两次单次门禁的失败记录。`quick-verify.sh` 已改用 `--components pdf --package` 并以 APFS 克隆复制版本化 ZIP。

## 第 19 轮：0.1.20 签名视口导航与缩略图焦点

对照 GenOffice `apps/pdf/src/renderer/keyNav.ts` 和 `App.tsx`，将 PageDown/Space、PageUp、Home/End、上下行滚动及缩略图焦点上下翻页写入签名产品资源。`PdfKeyboardNavigation` 只解析产品策略，Flutter 壳按焦点路由动作，PDF 会话用 PDFium 视口坐标执行；按键步长为原版的 60 像素行距与视口高度减 40 像素。文本编辑焦点仍交由输入控件处理。

| GenOffice 2400×1530 参照 | OpenMuse 0.1.20 初始壳 | OpenMuse 0.1.20 PageDown |
| --- | --- | --- |
| ![GenOffice PDF 壳](../../../../Muse-Client/dist/pdf-product-evidence-0.1.20/genoffice-reference.webp) | ![OpenMuse 初始壳](../../../../Muse-Client/dist/pdf-product-evidence-0.1.20/genoffice-viewport-desktop.png) | ![OpenMuse PageDown](../../../../Muse-Client/dist/pdf-product-evidence-0.1.20/keyboard-page-down-desktop.png) |

[本轮完整视觉对照](../../../../Muse-Client/dist/pdf-product-evidence-0.1.20/VISUAL-COMPARISON.md)包含四图横排、前后截图、七标签 Ribbon 与菜单、文档区、底栏的证据和剩余差异。0.1.19 与 0.1.20 初始视口截图 SHA-256 完全相同，PageDown 后文档区出现第 1 页底部与第 2 页顶部，Host 测试直接验证视口移动及 Home 归位。签名插件验证、PDF Flutter 静态分析和测试、Host 真实 PDF 截图测试均通过。

## 第 20 轮：0.1.21 窄窗口编辑区保底

对照 GenOffice 的固定 Ribbon、AI 面板、缩略图、PDF 页面和状态栏区域，本轮修复 OpenMuse 在 800 像素窗口同时展开 AI 和缩略图时编辑区仅余约 207 像素的问题。签名 `chrome.json.responsiveLayout` 声明手机/紧凑断点与编辑区最小宽度，独立布局模型计算各列；用户主动打开 AI 时临时限制 AI 宽度并收起缩略图。窗口恢复后可重新呈现原有偏好。

| GenOffice 2400×1530 参照 | OpenMuse 800×600 修改前 | OpenMuse 800×600 修改后 |
| --- | --- | --- |
| ![GenOffice PDF 壳](../../../../Muse-Client/dist/pdf-product-evidence-0.1.21/genoffice-reference.webp) | ![旧窄窗口](../../../../Muse-Client/dist/pdf-product-evidence-0.1.21/baseline-tablet-ai-open.png) | ![新窄窗口](../../../../Muse-Client/dist/pdf-product-evidence-0.1.21/tablet-ai-open.png) |

[本轮完整视觉对照](../../../../Muse-Client/dist/pdf-product-evidence-0.1.21/VISUAL-COMPARISON.md)提供桌面原版参照、同视口窄窗口前后图、Ribbon/状态栏/手机回归证据。Host 实测 PDF 视口至少 399 像素；桌面 2400×1530 初始截图和手机首页截图分别与 0.1.20 逐字节相同。插件签名验证、PDF Flutter 分析及测试、Host 真实 PDF 截图测试均通过。GenOffice 纸张大小操作会改写 PDF 文件，当前产品内核未提供同等能力，仍保持入口禁用。

## 第 21 轮：0.1.22 视图 Ribbon 双页模式

对照 GenOffice `apps/pdf/src/renderer/App.tsx` 的单个双页切换按钮和 `spread.ts` 的同行配对、整行翻页，本轮将视图 Ribbon 原先两个禁用入口改为一个可执行的状态按钮。签名 `chrome.json.pageArrangement` 提供命令、单页/双页文案与图标；独立 `PdfArrangementGeometry` 计算页面行布局，产品会话负责切换、行宽适配及键盘步进。双页采用 `1+2、3+4…` 排列；单页保留原阅读器缩放策略，避免影响手机默认页面。

| 0.1.21 View Ribbon | 0.1.22 单页 | 0.1.22 双页 |
| --- | --- | --- |
| ![旧视图入口](../../../../Muse-Client/dist/pdf-product-evidence-0.1.22/baseline-ribbon-view.png) | ![新单页入口](../../../../Muse-Client/dist/pdf-product-evidence-0.1.22/ribbon-view.png) | ![双页状态](../../../../Muse-Client/dist/pdf-product-evidence-0.1.22/view-spread-desktop.png) |

[同视口三图合成](../../../../Muse-Client/dist/pdf-product-evidence-0.1.22/view-before-after.png)及[完整视觉对照](../../../../Muse-Client/dist/pdf-product-evidence-0.1.22/VISUAL-COMPARISON.md)记录了 GenOffice 源码合同、页面几何断言、切回单页截图、顶部 Ribbon/中央编辑区/底栏回归。2400×1530 默认桌面截图与上一轮逐字节一致；390×844 手机单页截图亦与上一轮逐字节一致。Flutter 分析与测试、Host 真实 PDF 截图 E2E、签名插件打包验签均通过。本轮用户只要求视觉证据，没有重新构建 macOS 或 APK；原版未提供双页截图，双页对照以源码行为为准。

## 下一轮验收顺序

1. 继续 `0.1.22`：补辅助功能、窗口切换和 160 页性能回归；如要开放页面参数弹窗，先实现并验证对应的产品内核操作。
2. 发行候选：使用相同 PDF、字体、主题、DPI 和 AI 面板状态运行 GenOffice 与 OpenMuse 的真实目标应用截图；以区域截图差异和控件行为台账签字。当前无法将不同文档、语言、主题的截图宣称为像素级 1:1。
