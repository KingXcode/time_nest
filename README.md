# Time Nest

基于 Flutter Web 的极简桌面时钟项目，计划将闲置手机作为长期横屏展示的桌面时钟，首要目标设备为 iPhone 8 Plus。

> **当前阶段：工程初始化。** 已创建仅启用 Web 的 Flutter 工程，并通过 FVM 固定 SDK 版本。当前页面仍是 Flutter 默认计数器示例，尚未实现时钟业务功能，也未完成目标设备实机验收。

## 技术栈

| 项目 | 版本或方案 |
| --- | --- |
| Flutter | **3.47.5**，官方 stable 版本 |
| Dart | **3.13.4**，随 Flutter SDK 提供 |
| SDK 管理 | FVM，项目配置见 [.fvmrc](<.fvmrc>) |
| 第一版平台 | Web |
| 测试 | Flutter Test；Safari 兼容性需实机验收 |

不使用鸿蒙定制 SDK，不依赖系统全局 Flutter 版本。项目命令统一使用 `fvm flutter` 和 `fvm dart`。

## 功能目标与范围

### 核心展示目标

- 显示本地年月日、星期，以及 `HH:mm:ss.SSS` 格式的时间。
- 时分、秒、毫秒采用三个字号层级，数字等宽、布局稳定。
- 横屏优先，兼容竖屏和桌面浏览器窗口。
- 使用设备系统时间；页面恢复可见时立即校准，不累加固定时间间隔。

### 后续计划（尚未实现）

- 本地设置、文字亮度调节和夜间模式。
- 根据浏览器能力尝试屏幕常亮，并提供失败状态和降级说明。
- 主屏幕安装引导、离线缓存和版本更新提示。

上述增强功能的具体范围与默认行为仍需在开发时确认。第一版不包含账号、后端、天气、日程或原生平台工程。

> 三位毫秒是显示格式，不代表每毫秒刷新一次，也不保证毫秒级计时准确度。系统时间错误时，时钟显示也会错误。

## 快速开始

### 1. 准备环境

安装 Git、[FVM](https://fvm.app/documentation/getting-started/installation) 和用于本地调试的 Chrome。Dart 随项目 Flutter SDK 提供，无需单独安装或升级。

```bash
git --version
fvm --version
```

### 2. 获取项目

远程仓库位于内网，需要具备对应网络访问条件和仓库权限。已有本地工程时，跳过克隆步骤，直接进入项目根目录。

```bash
git clone http://192.168.12.175/git/niesiyang/time_nest.git
cd time_nest
```

### 3. 安装指定 SDK 和依赖

```bash
# 根据 .fvmrc 安装项目指定版本
fvm install

# 确认使用 Flutter 3.47.5 / Dart 3.13.4
fvm flutter --version

# 获取项目依赖
fvm flutter pub get
```

如需显式重新关联本地 SDK：

```bash
fvm use 3.47.5
```

无需执行 `fvm global`，也不要直接运行 `flutter upgrade` 改变项目 SDK 基线。

### 4. 启动调试

```bash
fvm flutter run -d chrome
```

当前启动后显示默认计数器示例，而不是成品时钟。

查看可用设备或检查开发环境：

```bash
fvm flutter devices
fvm flutter doctor
```

本项目仅启用 Web，不必为此安装 Android、iOS 或桌面原生开发工具链；应重点检查 Flutter 和 Web 调试所需环境。

### 编辑器 SDK 配置

如编辑器未自动识别 FVM，可将 Flutter SDK 路径设为项目内的 `.fvm/flutter_sdk`。例如 VS Code 的工作区配置项为：

```json
{
  "dart.flutterSdkPath": ".fvm/flutter_sdk"
}
```

避免使用某位开发者机器上的绝对 SDK 路径作为共享配置。

## 手机布局预览

手机与电脑接入同一可信局域网后，可启动网络调试服务：

```bash
fvm flutter run -d web-server --web-hostname=0.0.0.0 --web-port=8080
```

在手机浏览器中打开 `http://电脑的局域网IP:8080`。若无法连接，检查防火墙、端口占用和网络隔离设置。调试结束后按 `Ctrl+C` 停止服务。

> 该 HTTP 方式主要用于布局预览。Service Worker、屏幕常亮等能力需要安全上下文，必须在 HTTPS 环境下进一步验证；电脑上的 localhost 例外不适用于手机访问电脑的局域网地址。

## 代码检查与测试

在项目根目录执行：

```bash
# 检查格式，不自动修改文件
fvm dart format --output=none --set-exit-if-changed lib test

# 静态分析
fvm flutter analyze

# 自动化测试
fvm flutter test
```

需要自动格式化时：

```bash
fvm dart format lib test
```

当前 [组件测试](<test/widget_test.dart>) 仅覆盖默认计数器示例。后续需增加时间格式、日期边界、生命周期、设置及浏览器能力降级测试。模板测试通过不能代替时钟功能或实机验收。

## Web 构建与部署

生成发布版本：

```bash
fvm flutter build web --release
```

构建产物位于 `build/web/`，需将该目录作为完整静态站点部署到支持 HTTPS 的服务，不建议直接双击构建后的 HTML 文件运行。

若部署地址使用 `/time_nest/` 子路径：

```bash
fvm flutter build web --release --base-href=/time_nest/
```

`--base-href` 必须与实际部署路径一致，并保留开头和结尾的 `/`。

构建成功不代表已经具备离线访问、完善的主屏幕安装体验或屏幕常亮能力。当前 [Web Manifest](<web/manifest.json>) 仍是模板配置，图标、配色与方向配置需要随产品开发调整。

## 工程文件

| 文件 | 用途 |
| --- | --- |
| [应用入口](<lib/main.dart>) | 当前为默认 Flutter 计数器示例 |
| [组件测试](<test/widget_test.dart>) | 默认示例的交互测试 |
| [Web 入口](<web/index.html>) | 浏览器页面入口 |
| [Web Manifest](<web/manifest.json>) | Web 应用名称、图标和显示配置 |
| [依赖配置](<pubspec.yaml>) | 项目信息、Dart 约束与依赖 |
| [依赖锁定](<pubspec.lock>) | 应用依赖的解析版本 |
| [分析规则](<analysis_options.yaml>) | Dart 静态分析配置 |
| [FVM 配置](<.fvmrc>) | 固定项目 Flutter 版本 |
| [设计文档](<desk-clock-design.md>) | 产品需求、交互与验收参考 |

## 目标设备与已知限制

- 首要目标设备为 iPhone 8 Plus，实际 iOS 小版本需要记录并验证。
- Safari 普通页面与添加到主屏幕后的运行模式需要分别测试。
- 不保证所有浏览器都支持全屏、方向锁定或屏幕常亮。
- 页面进入后台后可能暂停更新，时钟实现需处理恢复时的时间校准。
- 网页中的“文字亮度”不等于系统屏幕背光亮度。
- 长期展示的耗电、发热与稳定性需要实机观察，不预先承诺性能结果。
- 自动化测试和桌面浏览器调试不能代替真实 iPhone Safari 验收。

## 版本管理约定

需要提交源码、测试、必要的工程配置与文档，并保留 [.fvmrc](<.fvmrc>)、[pubspec.yaml](<pubspec.yaml>) 和应用的 [pubspec.lock](<pubspec.lock>)。

[.gitignore](<.gitignore>) 已排除 `.fvm/`、`.dart_tool/`、`.pub-cache/`、`build/` 和 `.DS_Store`。不要将本地 SDK、缓存、构建产物、密码、令牌或私钥提交到仓库。

升级 Flutter 时，应明确选择版本、更新 FVM 配置，并完成依赖解析、静态分析、测试、Web 构建和目标设备回归，不跟随浮动的 `stable` 自动升级。

## 设计文档说明

[桌面时钟设计文档](<desk-clock-design.md>) 保留了项目启动时的设计稿，其中“尚未创建工程”以及 Vite + TypeScript、DOM/CSS 等技术方案已不代表当前工程现状。

当前已确认采用 **Flutter Web + FVM 固定 Flutter 3.47.5**。原文涉及旧技术栈、目录结构与实现方式的内容需要后续同步修订；产品展示目标、浏览器能力边界和实机验收要求仍可作为参考，不应将设计稿中的规划当作已实现功能。
