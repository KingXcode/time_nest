# 主屏幕 PWA 底部空白修复

## 当前 2.5.3 的后续调整（2026-10-28）

下文 2026-10-20 的修复与测试计数是历史记录，并非本次版本结果。用户后续选择全页内容延伸到底部：当前宿主仅扣顶部和左右安全区，**不扣底部**。例如 CSS 390 × 844、顶部 47 / 底部 34，宿主尺寸现在是 390 × **797**，而不是下文历史实现的 763。

底部 34 CSS px 通过 `shikeViewport` → `BrowserViewportInsets` 注入 Flutter MediaQuery，供滚动内容尾部和底部按钮避让；不重复添加顶部/左右。注入先于手动旋转。键盘压缩宿主时 inset 清零；收起后恢复。首页常亮提示及其占位已移除，设置采用覆盖层。

19 项 viewport JS 测试、2 项 Dart 桥测试及静态分析通过；`tool/browser_smoke.mjs` 已更新为顶部 47 / 高度 797、横屏全高 390，并检查桥的 34 / 0 / 21 inset，但该浏览器脚本仍未运行。真实 iPhone/PWA 验收仍待完成：重点检查滚动视口到底、最后一行与按钮可避开 Home 指示条、键盘恢复及横竖屏，不能把单元测试当作设备验收。

## 历史修复记录（2026-10-20）


2026-10-20，本地 `main`，Flutter 3.47.5 / Dart 3.13.4。

## 现象与代码证据

- 用户提供的主屏幕运行截图为 942 × 2048。应用内容在 y=1823 结束，下方连续 225 像素为页面背景色 `#08090B`，不是列表正常留白。仅凭截图无法取得设备上的实际 viewport 数值。
- 原实现无论运行模式，都把 `visualViewport.height` 作为 Flutter host 的高度来源，再在 CSS 中减去上下安全区。WebKit [254868](https://bugs.webkit.org/show_bug.cgi?id=254868) 记录：安装到主屏幕且使用 `viewport-fit=cover` 时，部分 viewport 数值已经扣除了安全区。[210009](https://bugs.webkit.org/show_bug.cgi?id=210009) 也记录了 `innerHeight` 的相关问题，所以不能只换成 `innerHeight`。
- 可以确定的代码缺陷是重复扣除安全区。例如 CSS 全屏 390 × 844、上下安全区 47 / 34、visual viewport 高度 763 时，旧 host 高度只有 682，修复后为 763。这个机制与截图症状一致，但不据此宣称已确认某个 iOS 版本的系统缺陷。
- [Flutter 嵌入文档](https://docs.flutter.dev/platform-integration/web/embedding-flutter-web) 规定 host 的尺寸约束渲染视图。固定 SDK 的 `CustomElementDimensionsProvider` 使用 host 的 `clientWidth/clientHeight`，因此修正在网页宿主层，不改看板卡片或列表高度。

## 修复

- 主屏幕模式通过隐藏的 `100vw × 100vh` CSS 测量元素取得完整布局尺寸，只扣一次安全区；兼容 `display-mode: standalone` 和 `navigator.standalone`。
- 不使用 `screen.height`，不硬编码 iPhone 型号、iOS 版本或底部补偿像素。
- 只有可编辑控件聚焦且视觉视口确实小于安全内容高度时，才按键盘遮挡收缩纵向区域。键盘收起后即使输入框仍聚焦，也恢复完整高度；横屏左右安全区不会再次扣除。
- 保留普通浏览器标签页原有尺寸计算、缩放保护、旋转/恢复后的有限重测及后台暂停。独立观察测量元素的内容尺寸，覆盖安全区晚于首帧变化的情况。
- CSS 直接使用最终安全矩形，不再次扣除 inset；保留 `overflow: clip`，不回退已有 iframe 聚焦防滚动修复。

## 验证

- 176 项 Node 测试通过，其中 15 项 viewport 测试覆盖主屏幕重复安全区、普通标签页、键盘弹出/收起、焦点保留、快速失焦再聚焦、只读/硬件键盘场景、横屏键盘、三次后台恢复、缩放、旧接口回退、零尺寸保护和延迟安全区。
- Dart 格式检查通过，70 个文件无需改动；`flutter analyze --no-pub` 无问题；239 项 Flutter 测试通过。本次未修改 Dart 代码。
- JavaScript 语法检查及 `git diff --check` 通过。
- 发布构建与 49 个资源的离线缓存生成通过。现有 `dart:html` 的 WASM dry-run 警告不影响项目选择的 JavaScript / CanvasKit 构建。
- `tool/browser_smoke.mjs` 新增真实 DOM / Flutter host 边界断言，注入明确标记的主屏幕视觉视口与安全区数据；其运行仍受当前环境限制，不能记为通过。Chromium 无法在 shell 沙箱中创建本地 profile socket，受支持的提升执行路径也在环境初始化时失败；独立云浏览器无法访问此 checkout 的本地 HTTP 服务。

## 尚需真机验收

本次没有运行 iPhone Safari。以下必须在发布后用实际 iPhone 验证，模拟测试不代替验收：

1. 从主屏幕图标冷启动，打开每日看板并滚到底部，除系统安全区外无多余黑带。
2. 竖屏 / 横屏切换后仍完整显示，刘海与手势区域不遮挡操作。
3. 打开搜索或设置输入框，弹出键盘，再用系统键盘的关闭操作收起，输入框仍聚焦时也恢复高度；重复一次。
4. 切后台再恢复、锁屏再打开、重新启动主屏幕应用，尺寸正常。
5. 普通 Safari 地址栏展开 / 收起及双指缩放无新增回归。

本记录区分本地验证与真机验收；线上发布结果以对应提交的 GitHub Pages 工作流为准。
