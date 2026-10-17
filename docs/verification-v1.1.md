# 此刻 1.1.0 · 功能与验证记录

检查日期：2026-10-17。本记录为发布前的代码与浏览器验收结果；线上发布状态以当前提交对应的 [GitHub Actions](https://github.com/KingXcode/time_nest/actions/workflows/deploy-pages.yml) 运行结果为准。

## 需求对应

| 要求 | 实现与直接验证 |
| --- | --- |
| 办公／床头／极简预设 | 设置模型、日期与色彩控制；模型测试验证规则与旧配置兼容，组件和 Chrome 通过点击三种预设验证保存 |
| 倒计时 | 5／15／25 分钟快捷选择、自定义 1～180 分钟、暂停继续、重置、提示音；组件验证输入与实际倒数，Chrome 验证暂停后刷新保持剩余时长 |
| 番茄钟 | 可配置专注／短休息／长休息，每 4 次专注后长休息、每日次数；测试覆盖阶段、跨日、刷新、后台恢复与不重复计数，Chrome 验证完成后手动开始休息 |
| 手动横屏／竖屏 | 全应用旋转，包含菜单、设置、触控与 MediaQuery；组件覆盖 320×568、736×320、1280×720，Chrome 实际点击旋转后的设置和方向按钮，并验证刷新保留方向 |
| 首次加载体验 | 下载时先提供基础时钟和真实阶段提示；15 秒慢网提示与重试；UI 就绪后开始离线下载；Chrome 延迟脚本响应验证加载时钟和缓存延后，缺失加载脚本仍能进入完整应用 |
| 离线资源进度与旧功能 | 资源完成数经真实 SW 消息验证；离线重开、手动更新、多标签旧版本、子路径、存储禁用继续运行均通过 Chrome 场景 |

## 本次结果

- 格式检查：18 个 Dart 文件，无需修改。
- Flutter 静态分析：无问题。
- Flutter 测试：94 项通过。
- Node 测试：46 项通过，包含声音能力、加载状态、SW 与存储等。
- 发布构建：成功，45 项完整预缓存资源。
- 真实浏览器：Chrome/155.0.8059.82，13 个场景通过，无未处理 JavaScript 异常，无外部字体或渲染器请求。
- 构建指纹（`/time_nest/` 发布路径）：`d57515474c5cbf88ff1894dea2c8594b9779e870ddf5c3d10c76f7862f0cfcc5`。
- 报告与截图：`build/verification/report.json`、`00-loading.png`、`07-manual-landscape.png`、`08-manual-portrait.png`、`09-countdown.png`、`10-focus-rest.png`、`11-short-landscape.png`。

## 使用与边界

轻点页面，左上角切换时钟／倒计时／番茄钟；右上角方向按钮切换自动／手动横屏／手动竖屏；展示设置中选择预设。计时设置可修改时长和提示音。

手动方向旋转页面，不修改操作系统方向锁定。前台提示音需要用户交互启用音频；系统挂起、锁屏或关闭浏览器时不保证准时响铃。页面恢复后根据结束时间恢复状态，结束后不会自动推进多个专注阶段。状态仅保存在当前站点的本地浏览器存储。

尚未进行真实 iPhone Safari／主屏幕模式和长时间功耗验证，不能用桌面 Chrome 结果代替这些设备验证。首次加载改进未声称下载体积缩减或具体提速百分比。

## 复现

```bash
fvm dart format --output=none --set-exit-if-changed lib test
fvm flutter analyze
fvm flutter test
node --test test_web/*.test.mjs
bash tool/build_web.sh
node tool/browser_smoke.mjs
```
