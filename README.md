# 此刻 · Time Nest

**横放手机，让时间安静一点。**

「此刻」是一款基于 Flutter Web 的极简桌面时钟，面向闲置手机的长时间横屏展示，首要目标设备为 iPhone 8 Plus。应用显示名为「此刻」，工程及仓库名称保持 `time_nest`。

在线使用：[打开此刻](https://kingxcode.github.io/time_nest/) · 源码：[KingXcode/time_nest](https://github.com/KingXcode/time_nest)

> 第一版功能已实现。自动化验证与实机验收是两回事：iPhone 的具体 iOS 版本、Safari / 主屏幕模式、电源管理和长时间发热仍需实测。详见 [第一版验收记录](<docs/verification-v1.md>)。

## 第一版功能

- 本地年月日、星期、时分秒与三位毫秒；12/24 小时制，12 小时制带 AM/PM。
- 时分、秒、毫秒三个字号层级，固定宽度、本地等宽数字字体；横竖屏与桌面窗口响应式布局。
- 点击屏幕显示操作入口，约 4 秒无操作隐藏；键盘聚焦操作区或设置打开时不隐藏，Escape 关闭设置。
- 本地保存设置，存储禁用、损坏或写入失败时仍能显示时间，并提示无法保存。
- 秒与毫秒开关、文字亮度、跨午夜夜间模式；关闭毫秒后降为秒/分钟边界调度。
- 常亮与全屏能力检测、真实状态提示及失败降级；不保证所有 iPhone 模式都支持。
- 主屏幕图标、安装指引和独立展示配置。
- 发布构建自动生成完整离线缓存；新版本必须经用户确认后才刷新。

不包含后端、账号、网络校时、天气、日程、原生安装包或后台常驻服务。

**三位毫秒只是显示格式，不代表每毫秒刷新或毫秒级计时准确度。系统时间错误时，页面也会错误。**

## 技术基线

| 项目 | 方案 |
| --- | --- |
| Flutter / Dart | 官方 stable **3.47.5 / 3.13.4** |
| SDK 管理 | FVM，[.fvmrc](<.fvmrc>) 固定版本 |
| 展示 | Flutter Web，JavaScript + 本地 CanvasKit；不依赖 WasmGC |
| 时间更新 | Flutter Ticker + 系统时间快照；无毫秒时用边界定时器 |
| 存储及浏览器能力 | localStorage、Wake Lock、Fullscreen，封装于独立桥接层 |
| 离线 | 构建时扫描资源并生成带 SHA-256 校验的 Service Worker |
| 验证 | Flutter 单元/组件测试、Node 浏览器能力模拟、真实 Chrome/CDP 冒烟 |

统一使用 `fvm flutter` / `fvm dart`，不修改全局 SDK，不使用鸿蒙分支。

## 开发运行

安装 Git、[FVM](https://fvm.app/documentation/getting-started/installation) 和 Chrome；已有项目可跳过克隆。

```bash
git clone https://github.com/KingXcode/time_nest.git
cd time_nest
fvm install
fvm flutter --version
fvm flutter pub get
fvm flutter run -d chrome
```

如编辑器没有自动识别 SDK，将 Flutter SDK 路径设为项目内的 `.fvm/flutter_sdk`。例如 VS Code 工作区设置：

```json
{"dart.flutterSdkPath": ".fvm/flutter_sdk"}
```

不需要为本项目安装 Android、iOS 或桌面原生工具链。Web 调试不启用发布版离线缓存，避免旧缓存干扰热重载。

### 手机布局预览

在可信局域网中运行：

```bash
fvm flutter run -d web-server --web-hostname=0.0.0.0 --web-port=8080
```

手机访问 `http://电脑局域网IP:8080`，结束后按 `Ctrl+C`。这个 HTTP 地址只能辅助检查布局；常亮、Service Worker 和安装体验请使用 HTTPS。电脑 localhost 的安全上下文例外不适用于手机访问电脑的 IP。

## 使用方式与默认规则

首次打开即可看时间，不需要先点按钮。可以关闭引导，也可以点“开始展示”明确请求常亮与浏览器支持的全屏。再次轻点页面可打开“展示设置”。

| 设置 | 默认值与行为 |
| --- | --- |
| 时制 | 24 小时；可切换 12 小时 + AM/PM |
| 秒 / 毫秒 | 均显示；隐藏秒时同时隐藏毫秒，但保留原毫秒偏好 |
| 文字亮度 | 100%，可调范围 15%～100%；不影响按钮可读性、不控制系统背光 |
| 夜间模式 | 默认关闭，预设 22:00～07:00，夜间亮度 25% |
| 夜间边界 | 包含开始、不含结束，支持跨午夜；起止相同不启用；取日常/夜间亮度较小值 |
| 常亮 | 默认关闭；偏好不等于锁已获取，界面显示实际状态 |

Safari 添加到主屏幕：分享菜单 → 添加到主屏幕 → 从图标重新打开。横放手机前请手动关闭系统方向锁定。

常亮不可用时，可以在设备策略允许的前提下，把系统“显示与亮度 → 自动锁定”设为“永不”；这是系统级设置，离开展示后建议恢复。长期展示注意散热和电池健康，异常发热或鼓包时停止充电使用。

## 发布构建与离线

需要 Node.js 22+。**请使用项目构建脚本，而不只运行 Flutter build**：脚本关闭 CDN 依赖与 Flutter 默认 SW，然后为实际产物生成完整预缓存清单。

```bash
bash tool/build_web.sh
```

部署 `build/web/` 的全部内容到 HTTPS 静态站点。使用子路径时：

```bash
bash tool/build_web.sh --base-href=/time_nest/
```

`--base-href` 必须与部署路径一致，并保留两侧 `/`。该脚本固定发布到 `build/web/`，不接受 `--output`、`--wasm`、debug/profile 或启用 CDN 的参数。

本机验证发布产物（不要直接双击 HTML）：

```bash
python3 -m http.server 8080 --bind 127.0.0.1 --directory build/web
```

打开 `http://127.0.0.1:8080`。子路径版本必须挂载在匹配的子路径，不能直接用上述根路径命令代替。

### 缓存和更新策略

- 首次联网加载并完整校验、缓存页面、脚本、图标、字体和本地 CanvasKit 后，设置中才显示“离线资源已就绪”。
- 之后可以离线重新打开。清理站点数据或系统回收存储可能使离线失效；不承诺永久离线。
- 设置中可主动“检查更新”。发现新版本后，点“更新并重新加载”才刷新，不在长期展示中突然刷新。
- 多标签页各自保留完整旧版本资源；一个标签确认后，其他标签仍可继续展示，并保留确认更新入口。
- 当前版本缓存缺失时，仅允许联网补齐与该版本哈希一致的资源，不混用新旧构建。旧版本已被替换且缓存丢失时，可能需要联网清除站点数据后重开。
- 部署应一次性发布完整构建目录，不要只替换脚本；建议入口、bootstrap 和 SW 使用可重新校验的缓存头（如 `Cache-Control: no-cache`）。资源安装时的内容哈希检查可发现部署中途新旧混用。

CanvasKit 的完整离线资源比普通 DOM 时钟大，首次缓存需等待；不能据桌面测试推断老设备内存、功耗或帧率。

### GitHub Pages 自动发布

[发布工作流](<.github/workflows/deploy-pages.yml>) 在推送 `main` 后自动执行，也可在 GitHub Actions 页面手动运行。它读取 `.fvmrc` 固定 Flutter 版本，执行格式检查、静态分析、Flutter 测试和 Node 测试，再构建 `/time_nest/` 子路径的完整离线资源并发布到 GitHub Pages。

仓库 Settings → Pages 的发布来源使用 **GitHub Actions**。工作流使用 GitHub 自动提供的短期凭据，无需在源码中填写个人 Token。构建和部署结果可在 [Actions](https://github.com/KingXcode/time_nest/actions/workflows/deploy-pages.yml) 查看；全部成功后访问上方在线地址。

CI 通过 `FLUTTER_BIN=flutter` 调用已经安装的固定版本 SDK；本地继续使用 `bash tool/build_web.sh` 和 FVM。首次访问需下载资源，显示“离线资源已就绪”后才具备离线打开条件。发布新版本后，已打开的页面仍需用户确认更新。

## 检查与测试

```bash
fvm dart format --output=none --set-exit-if-changed lib test
fvm flutter analyze
fvm flutter test
node --test test_web/*.test.mjs
```

发布构建后可运行真实 Chrome 冒烟验证：

```bash
node tool/browser_smoke.mjs
```

脚本默认使用 macOS 的 Google Chrome；其他环境设置 `CHROME_BIN`。脚本创建临时本地 HTTP 服务和隔离的 headless Chrome，执行后关闭二者。截图与报告放入 `build/verification/`，不修改系统浏览器配置；这不是 iOS Safari 实测。

## 代码入口

| 文件 | 职责 |
| --- | --- |
| [应用入口](<lib/main.dart>) | 品牌、中文本地化、暗色主题 |
| [时钟调度](<lib/clock/clock_controller.dart>) | 单一更新循环、系统时间读取、暂停恢复 |
| [时间格式](<lib/clock/clock_snapshot.dart>) | 从同一快照生成所有时间字段 |
| [设置模型](<lib/clock/clock_settings.dart>) | 默认值、校验、夜间区间及 JSON |
| [主页面](<lib/ui/clock_screen.dart>) / [时钟布局](<lib/ui/clock_face.dart>) | 响应式显示、工具栏和生命周期 |
| [设置面板](<lib/ui/settings_panel.dart>) | 设置交互、状态与更新提示 |
| [浏览器桥接](<web/platform.js>) | 本地存储、常亮、全屏、安装模式与 SW 注册 |
| [SW 模板](<web/sw.template.js>) / [生成器](<tool/generate_sw.mjs>) | 资源完整性、离线、版本隔离 |
| [发布脚本](<tool/build_web.sh>) | Flutter 构建与 SW 生成入口 |

字体已随项目提交，不需要在线下载字体即可运行。中文使用 Noto Sans SC 的重命名裁剪版 ShikeSans，数字使用 Roboto Mono 的裁剪版；许可见 [Noto OFL](<assets/fonts/OFL-NotoSansSC.txt>) 和 [Roboto Mono OFL](<assets/fonts/OFL-RobotoMono.txt>)。新增中文文案后，应使用 [资源生成脚本](<tool/prepare_assets.py>) 更新字体覆盖；仅此维护步骤需要 Python、Pillow、fonttools 及首次源字体下载。

## 文档与版本管理

- [最初设计文档](<desk-clock-design.md>)：保留原始需求；其中 Vite/DOM 方案已由 Flutter Web 取代。
- [第一版验收记录](<docs/verification-v1.md>)：已验证结果与待实机验收清单。
- 提交 [.fvmrc](<.fvmrc>)、[pubspec.yaml](<pubspec.yaml>) 和 [pubspec.lock](<pubspec.lock>)；不提交 SDK、缓存、构建产物或敏感凭据。
- 升级 Flutter 应更新固定版本并重新执行全部测试、构建和目标设备验收，不直接跟随浮动 stable 升级。
