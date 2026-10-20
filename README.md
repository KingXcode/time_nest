# 此刻 · Time Nest

**横放手机，让时间安静一点。**

「此刻」是一款基于 Flutter Web 的极简桌面时钟，面向闲置手机的长时间横屏展示，首要目标设备为 iPhone 8 Plus。应用显示名为「此刻」，工程及仓库名称保持 `time_nest`。

在线使用：[打开此刻](https://kingxcode.github.io/time_nest/) · 源码：[KingXcode/time_nest](https://github.com/KingXcode/time_nest)

> 第一版功能已实现。自动化验证与实机验收是两回事：iPhone 的具体 iOS 版本、Safari / 主屏幕模式、电源管理和长时间发热仍需实测。详见 [第一版验收记录](<docs/verification-v1.md>)。

## 当前功能

- 本地年月日、星期、时分秒与一位秒小数（0.1 秒，如 `12:34:56.7`）；12/24 小时制，12 小时制带 AM/PM。
- 办公／床头／极简展示预设，日期开关和暖色文字；选择预设后仍可调整设置。
- 独立的倒计时与番茄钟：快捷／自定义时长、暂停继续、刷新恢复、前台完成提示音、今日专注次数。
- 手动横屏／竖屏与自动方向，旋转完整应用（包括设置与菜单），不依赖系统自动旋转。
- 首次下载期间先显示基础时钟，按真实阶段提示加载状态；完整界面就绪后再准备离线缓存，并显示资源完成数。
- 时分、秒、毫秒三个字号层级，固定宽度、本地等宽数字字体；横竖屏与桌面窗口响应式布局。
- 点击屏幕显示操作入口，约 4 秒无操作隐藏；键盘聚焦操作区或设置打开时不隐藏，Escape 关闭设置。
- 展示设置可在主页面展开／收起：竖屏位于时钟下方，横屏位于右侧；设置独立滚动，修改时可实时查看效果。
- 本地保存设置，存储禁用、损坏或写入失败时仍能显示时间，并提示无法保存。
- 秒与毫秒开关、文字亮度、跨午夜夜间模式；关闭毫秒后降为秒/分钟边界调度。
- 常亮与全屏能力检测、真实状态提示及失败降级；不保证所有 iPhone 模式都支持。
- 主屏幕图标、安装指引和独立展示配置。
- 发布构建自动生成完整离线缓存；自动检查新版，主页面提示“立即更新”，点击后加载并保留设置和计时。
- 每日看板首页仅作入口：普通天气、GitHub 项目更新、中文科技资讯、A 股行情、数字货币行情各有独立页面；支持收藏、排序和本地保存。

不包含后端、账号、网络校时、私人日程、原生安装包或后台常驻服务。

**秒后小数只显示一位，截取毫秒的百位，不四舍五入；显示格式不代表计时精度。系统时间错误时，页面也会错误。**

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

本机 BaoStock 个人研究版的独立构建、回环服务及数据边界，见 [本机行情运行说明](docs/local-market-research.md)。该模式不用于公开部署。

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

首次打开即可看时间，不需要先点按钮。可以关闭引导，也可以点“开始展示”明确请求常亮与浏览器支持的全屏。再次轻点页面可展开“展示设置”：竖屏显示在下方，横屏显示在右侧，时钟与计时仍可同时使用。再次点击设置按钮、面板关闭按钮或按 Escape 可收起；“开始展示”也会收起设置。

| 设置 | 默认值与行为 |
| --- | --- |
| 时制 | 24 小时；可切换 12 小时 + AM/PM |
| 秒 / 毫秒 | 均显示；隐藏秒时同时隐藏毫秒，但保留原毫秒偏好 |
| 文字亮度 | 100%，可调范围 15%～100%；不影响按钮可读性、不控制系统背光 |
| 夜间模式 | 默认关闭，预设 22:00～07:00，夜间亮度 25% |
| 夜间边界 | 包含开始、不含结束，支持跨午夜；起止相同不启用；取日常/夜间亮度较小值 |
| 常亮 | 默认关闭；偏好不等于锁已获取，界面显示实际状态 |

Safari 添加到主屏幕：分享菜单 → 添加到主屏幕 → 从图标重新打开。

### 展示预设与方向

轻点页面 → 展示设置，选择以下预设；时制、常亮偏好、页面方向和夜间起止时间不会被预设覆盖。

| 预设 | 显示规则 |
| --- | --- |
| 办公 | 日期＋时分秒、关闭毫秒、中性文字、正常亮度 |
| 床头 | 日期＋时分、暖色文字、日常文字亮度 65%、启用夜间模式且夜间文字亮度 20% |
| 极简 | 只显示时分、中性文字、正常亮度 |

轻点页面 → 右上角方向按钮 → 自动方向／手动横屏／手动竖屏。手动模式在视口方向不匹配时旋转整页 90°，设置、菜单和触控位置一起旋转；不修改操作系统方向锁定。选择后保存在当前浏览器。自动模式跟随浏览器可用尺寸。

### 倒计时与番茄钟

轻点页面 → 左上角模式菜单 → 倒计时／番茄钟。返回时钟不会取消正在进行的计时，两种计时互不覆盖。

- 倒计时提供 5／15／25 分钟快捷选择；计时设置中支持 1～180 分钟自定义。
- 番茄钟默认专注 25 分钟、短休息 5 分钟、每完成 4 次专注后长休息 15 分钟；专注可设为 1～180 分钟，休息可设为 1～60 分钟。
- 支持开始、暂停、继续和重置。进行中／暂停时修改时长需先重置。主动重置不计入专注次数。
- 专注或休息结束后保留完成画面，手动开始下一阶段；不会在后台自动循环或累计虚假的专注次数。
- 状态保存于 `shike.timer.v1`，运行中记录结束时间，暂停时记录剩余时间；刷新和返回前台后按系统时间恢复，不靠回调次数累加。今日次数按本地日期及专注实际结束时间统计。
- 完成提示音可关闭。声音需要用户开始计时等操作来启用；浏览器关闭、锁屏或后台挂起时不保证准时提醒，不能作为系统闹钟使用。
- 状态只保存在当前站点、当前浏览器中，不跨设备同步；存储禁用时仍可计时，但刷新恢复不保证有效。设备系统时间改变会影响基于结束时间的剩余时长。

常亮不可用时，可以在设备策略允许的前提下，把系统“显示与亮度 → 自动锁定”设为“永不”；这是系统级设置，离开展示后建议恢复。长期展示注意散热和电池健康，异常发热或鼓包时停止充电使用。

### A 股行情（免费官方嵌入）

所选指数还可查看 TradingView 官方日线技术评级，并附中文含义与局限说明。科创50 评级当前无数据，会明确提示；评级不等于整个市场好坏，未标注日期时不视为今日分析。

A 股行情是独立页面，只在进入时加载 TradingView 官方 Advanced Chart。支持上证指数、深证成指、沪深300、创业板指、科创50、中证全指，及日线/周线/月线。指数和周期选择保存在本机。页面以收盘趋势观察为主，不保证实时；实际日期、延迟、市场状态以图表自身标记为准。指数不能代表所有个股，不提供买卖建议或自制市场强弱分数。

- 无 API key、无付费订阅、无行情后端，也不读取/抓取/导出组件数据。
- 完整保留 TradingView 署名和来源链接；可重新加载或打开官方来源。
- 组件运行在 TradingView 跨域 iframe 内，第三方代码不在本应用源下执行，不能读取本应用设置；固定白名单限制品种与周期，CSP 只允许固定哈希的本地启动代码及指定图表域名。
- 按 TradingView 官方 FAQ，组件会接收页面 URL、组件类型、显示品种和访问 IP，组件不设置 Cookie。外部服务仍需联网，离线时只有本应用页面可用，不缓存行情。
- [TradingView 组件文档](https://www.tradingview.com/widget-docs/widgets/charts/advanced-chart/) · [亚洲数据覆盖](https://www.tradingview.com/widget-docs/markets/asia-pacific/) · [数据限制](https://www.tradingview.com/widget-docs/faq/data/) · [隐私说明](https://www.tradingview.com/widget-docs/faq/general/)

### 每日看板

点时钟右上角“每日看板”进入，也可从模式菜单进入。入口在操作栏隐藏时仍可见。时钟、倒计时和番茄钟继续运行，返回不会重置计时。

- 首页采用紧凑数据总览：顶部五个小尺寸导航，直接显示所选城市天气、6 个币种报价快照、最多 10 条资讯和前 4 个关注项目的发布摘要。首页只按需请求这些摘要，不启动轮询、WebSocket 或 TradingView 图表；展开详情后才加载 K 线与实时连接。无城市时不请求天气。
- 点星标收藏卡片，可只看收藏；“调整顺序”支持拖动和上下按钮。城市、仓库、新闻类型、指数、数字货币交易对、周期、收藏及顺序保存于本浏览器，刷新后恢复。
- 首页大屏按内容分栏，小屏与放大字体时自动顺排；按钮约 32px，导航不再占用大卡片。资讯和项目详情在宽屏下双列，行情报价更紧凑；K 线主图与副图高度保持不变。每个详情页独立滚动，返回后保留城市、关注仓库、新闻频道及行情选择。加载、无数据、失败、重试、旧缓存和数据时间均有独立状态。
- 无账号、无需 API Key、没有自建后端。请求直接从浏览器发往下表来源；来源服务会收到常规网络信息及请求参数（选定城市坐标、公开仓库名等）。不会自动请求设备位置，也不会将偏好同步到服务器。
- 天气、项目更新和资讯在首次进入页面、参数改变或手动刷新时按需请求；数字货币行情在页面前台接收实时推送，可手动暂停，后台及离开页面后关闭连接；推送中断时尝试快照补齐。缓存仅用于避免重复调用和断网降级，不能当作实时保证；数据源在部分地区可能不可达。

| 模块 | 数据及边界 |
| --- | --- |
| 天气 | [Open-Meteo](https://open-meteo.com/en/docs)：先手动搜索城市，展示气温、体感、天气状况、降雨概率、风速与逐小时预报。气温为当地当前小时的模型预报，不是传感器实时观测；缺少气温的旧缓存会明确显示体感温度。免费托管 API **仅限非商用**，有调用配额及服务限制；商用前需替换方案或购买服务。 |
| 项目更新 | [GitHub Releases](https://docs.github.com/en/rest/releases/releases)：默认关注 24 个热门 AI、开发工具、前端与移动端项目，最多 50 个。每页 4 个，翻页按需请求并缓存 1 小时；每个仓库仅取最新一条 Release。无 Release 的项目明确显示无正式发布。Release 可能包含预发布或子组件，不等同当前稳定版；Flutter 的 Release 可能滞后，可查看版本标签。匿名共享 IP 限额通常 60 次/小时，显示限流提示，无个人 Token。 |
| 科技资讯 | 默认 [少数派官方 RSS](https://sspai.com/feed)：中文科技、数码与效率生活文章，仅展示原始标题、文章链接与发布时间，不转载正文或图片。直接从浏览器读取，缓存 10 分钟，失败时标示旧缓存；并非实时快讯。也可切换 [Hacker News 官方 API](https://github.com/HackerNews/API) 的英文热门、最新、Show HN。 |

默认项目为人工精选，不是实时 GitHub 星标排行榜：Flutter、Ollama、Dify、VS Code、Open WebUI、n8n、Transformers、LangChain、llama.cpp、ComfyUI、React、Vue、Next.js、Svelte、Vite、Tailwind CSS、TypeScript、Node.js、Deno、Bun、Rust、uv、Kubernetes、React Native。可逐个取消、添加自己的仓库，或点“补齐热门项目”。

升级时，旧版仅有 flutter/flutter 的默认列表会扩充；已有自定义或空列表保留。新版记住取消关注，不会在刷新后自动加回。新闻旧默认热门频道切为中文，已主动选择最新或 Show HN 的偏好保留。

汇率换算、出门时段推荐与节假日拼假已移除，旧汇率和节假日 API 不再调用；历史货币、金额及假期偏好会忽略，排序和收藏中的已移除入口会自动过滤。旧八类工具及其文件/图片桥接、二维码依赖和专属测试已移除。旧浏览器中若已有常用颜色偏好，该历史键不再读写；无需清除整个站点数据，时钟设置仍保留。

### 数字货币行情（币安公开现货数据）

每日看板 → 数字货币行情。支持 BTC、ETH、BNB、SOL、XRP、DOGE 六个 USDT 现货交易对；展示最新成交价、滚动 24 小时涨跌幅、最高价、最低价、成交量和成交额。报价来源为币安交易所，不能代表数字货币全市场市值；USDT 不是美元。

- 直接使用币安官方 `https://data-api.binance.vision`，无需账号、API Key 或自建代理。`/api/v3/ticker/24hr` 一次获取六个交易对，`/api/v3/klines` 首次获取所选交易对最近 500 根 K 线用于指标预热，默认展示最近 120 根。左右拖动主图或任一副图可浏览历史；接近已加载数据的左端时，按最早开盘时间减 1 毫秒作为 `endTime`，每次再加载最多 500 根，直到数据源返回最早记录。
- 支持 15 分钟、1 小时、4 小时、日线和周线。Flutter 绘制蜡烛图，左上角或右上角显示所选 K 线的开高低收、基础币成交量和 USDT 成交额；鼠标/触屏拖动同步平移主副图，悬停、点击及滑杆同步定位单根 K 线。绿色上涨、红色下跌；UTC 分周期，时间显示 UTC+8，未收盘 K 线持续变化。
- 交易对、周期、主副图指标选择及角落位置保存在本浏览器；从旧版升级时自动补充入口，不恢复已移除的汇率功能，不覆盖原有收藏、排序或 A 股偏好。
- 使用官方市场数据专用 `wss://data-stream.binance.vision/stream`：六个 `<symbol>@ticker`（约 1 秒）与所选 `<symbol>@kline_<interval>`（约 2 秒）。浏览器处理协议层 ping/pong；应用检查选中交易对的推送是否停滞，断线按 1–30 秒退避重连，并在连接满 23 小时 50 分前轮换。
- 历史快照与增量推送合并：同一根更新、新周期追加，过期/重复帧忽略，切换品种关闭旧连接。断线恢复、跨周期或发现缺口时重新补齐历史，补齐前暂停技术建议；历史快照不得覆盖更新的推送值。没有实时连接时仍尝试快照，失败后延长间隔，最多 5 分钟。
- 历史加载按时间连续拼接，不重复插入；补齐前后保持当前视图，实时推送与最新快照不丢弃已加载历史。可用“更早 / 较新”逐屏翻看、“加载更多历史”手动分页和“回到最新”恢复跟随；加载失败保留原图并可重试，切换交易对/周期丢弃旧请求。长时间离线导致新旧快照不连续时，重新从最新数据开始加载，不拼接虚假缺口。
- 页面后台、离开或手动暂停时关闭推送、停止定时请求；回到前台重新订阅并补齐。状态明确区分连接中、实时、重连、暂停，不能把旧缓存标成实时。
- 数据缓存 15 秒，失败时最多使用 10 分钟内的旧缓存，并保留原获取时间及旧数据提示；不生成模拟价格。接口限流时遵守 `Retry-After`，地区或网络不可用时显示错误和官方来源入口。
- 浏览器会向币安发送常规网络信息及所选交易对、周期。不包含交易、钱包、账户或下单功能。

官方文档：[WebSocket 推送](https://github.com/binance/binance-spot-api-docs/blob/master/web-socket-streams.md)、[公开行情域名](https://developers.binance.com/en/docs/products/spot/faqs/market_data_only)、[报价与 K 线接口](https://developers.binance.com/en/docs/catalog/core-trading-spot-trading/api/rest-api/market)、[请求频率限制](https://developers.binance.com/en/docs/products/spot/rest-api)。

发布构建后运行 `node tool/crypto_smoke.mjs` 可验证真实 Chrome 中的币安快照与 WebSocket 推送、鼠标/触屏平移和历史分页、交易对与周期切换、8+8 指标恢复及截图；它依赖当前网络可访问币安，不代替 iPhone Safari 真机验收。

### 图表指标与技术参考

共 36 种指标，主图最多同时叠加 8 种，独立副图最多同时显示 8 个。主图价格绘图区固定 320 像素，每个副图另占 150 像素；增加副图只延长页面，不缩短主图。主图顶部的信息、图例会按屏幕宽度换行，不遮挡蜡烛图。勾选达到上限后仍可取消已有指标。

- 主图 12 种：MA、EMA、WMA、BOLL、Donchian、Keltner、VWMA、HMA、DEMA、TEMA、BBI、ENV。
- 副图 24 种：VOL、AMOUNT、MACD、RSI、KDJ、STOCH、Stoch RSI、WR、CCI、ATR、NATR、DMI/ADX、OBV、CMF、MFI、ROC、MOM、TRIX、AO、BIAS、DPO、BBW、PPO、TSI。
- 参数和公式见每个指标选项的提示及 [计算源码](lib/dashboard/crypto_indicators.dart)。EMA 用 SMA 作种子，Wilder 平滑 α=1/N；标准差采用总体标准差。MACD 柱为 DIF−DEA，不乘 2。ATR 首根 TR 使用高低差；DMI 从第二根开始平滑。OBV 以当前加载窗口为基准。均线族作为一个可选叠加项，可包含多条线。
- 预热不足保留空值；零成交量的 VWMA 显示不可用；平盘 RSI/MFI 为 50。按原时间索引绘制，计算不引用未来数据；部分递归指标可能与使用更长历史或不同种子的平台有细微差异。
- 下方「技术指标 · 买入参考」展示最新已收盘 K 线上的 EMA、MACD、RSI、DMI/ADX、CMF、STOCH 数值、方向和逐项规则。固定使用最近 500 根计算评分，补充更早历史不改变当前参考。每项 +1/0/−1，合计≥3为偏多买入观察，≤−3为暂缓买入，其余观望；图上选择不会改变这六项评分。少于 60 根已收盘 K 线、未实时同步、暂停、错误或历史补齐中不提供建议。
- 这套规则没有收益回测，不是个人投资方案，也不保证收益；不包含交易、下单、持仓或账户信息。ATR/收盘价显示当前周期的波动参考。

独立验证：`test/fixtures/crypto_talib.json` 来自 TA-Lib Python 0.8.1 的合成行情参考值，22 条曲线在 3 个时点做数值比对；其他测试覆盖无未来数据、平盘/零量、连接恢复、快照竞态、320px/2倍字体及8+8数量和高度。TA-Lib 仅用于生成测试参考，不是产品运行依赖。公式参考：[RSI](https://www.tradingview.com/support/solutions/43000502338-relative-strength-index-rsi/)、[ATR](https://www.tradingview.com/support/solutions/43000501823-average-true-range-atr/)。本项目评分规则独立定义，不宣称与 TradingView 技术评级一致。

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

**本节仅适用于 Web，包括 iOS / Android 浏览器及添加到主屏幕的 PWA。原生 iOS / Android 客户端需要单独适配更新；当前不实现，后续接入和发布前必须检查 [各平台应用更新约定](<docs/platform-updates.md>)。**

- 完整界面就绪后才开始离线资源下载，避免与启动过程竞争网络；设置显示已缓存资源数（不是字节进度）。首次联网加载并完整校验、缓存页面、脚本、图标、字体和本地 CanvasKit 后，设置中才显示“离线资源已就绪”。
- 之后可以离线重新打开。清理站点数据或系统回收存储可能使离线失效；不承诺永久离线。
- 打开页面时自动检查更新；保持前台时每 5 分钟检查一次，返回前台或恢复网络时也会检查（这些恢复事件最多每分钟检查一次）。后台或断网时暂停定时检查，检查失败不打断当前展示。
- 新版资源完整下载后，主页面持续显示“新版本已就绪”和“立即更新”，不随工具栏隐藏。点击后检查并加载最新版本，保留设置和计时；失败可重试。没有点击时继续展示当前版本。
- 设置中仍可主动“检查更新”，并点“更新并重新加载”确认。
- 设置中的“刷新页面”会先检查服务器更新，等待新版资源完整下载、启用后重新加载；没有新版本时刷新当前页面。操作期间显示“正在刷新…”，失败或超时保留当前页面并提示重试；不会清除已保存的设置和计时。
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
| [计时状态](<lib/clock/timer_controller.dart>) / [计时界面](<lib/ui/timer_face.dart>) | 倒计时、番茄钟、状态恢复与统计 |
| [页面方向](<lib/ui/orientation_frame.dart>) / [启动时钟](<web/loading.js>) | 手动方向和首次加载体验 |
| [设置模型](<lib/clock/clock_settings.dart>) | 默认值、校验、夜间区间及 JSON |
| [主页面](<lib/ui/clock_screen.dart>) / [时钟布局](<lib/ui/clock_face.dart>) | 响应式显示、工具栏和生命周期 |
| [设置面板](<lib/ui/settings_panel.dart>) | 设置交互、状态与更新提示 |
| [浏览器桥接](<web/platform.js>) | 本地存储、常亮、全屏、安装模式与 SW 注册 |
| [SW 模板](<web/sw.template.js>) / [生成器](<tool/generate_sw.mjs>) | 资源完整性、离线、版本隔离 |
| [每日看板](<lib/dashboard/dashboard_screen.dart>) / [数据桥接](<web/dashboard.js>) | 五个独立功能页、偏好、缓存、错误与来源 |
| [发布脚本](<tool/build_web.sh>) | Flutter 构建与 SW 生成入口 |

字体已随项目提交，不需要在线下载字体即可运行。中文使用 Noto Sans SC 的重命名裁剪版 ShikeSans，数字使用 Roboto Mono 的裁剪版；许可见 [Noto OFL](<assets/fonts/OFL-NotoSansSC.txt>) 和 [Roboto Mono OFL](<assets/fonts/OFL-RobotoMono.txt>)。新增中文文案后，应使用 [资源生成脚本](<tool/prepare_assets.py>) 更新字体覆盖；仅此维护步骤需要 Python、Pillow、fonttools 及首次源字体下载。

## 文档与版本管理

以下验收记录保留对应版本的历史功能与验证结果，当前功能以本文上方说明为准。

- [2.3 A 股行情验收](<docs/verification-v2.3.md>)：六个官方嵌入指数、日周月线、隔离、手机窄宽与回归。
- [2.2 独立功能页与普通天气验收](<docs/verification-v2.2.md>)：首页零模块请求、独立页面、普通天气和移除拼假。
- [2.1 热门项目与中文资讯验收](<docs/verification-v2.1.md>)：24 个默认项目与少数派官方 RSS。
- [2.0 每日看板验收记录](<docs/verification-v2.md>)：五个 API 模块、布局、缓存及已知验证边界。

- [各平台应用更新约定](<docs/platform-updates.md>)：Web 现状、iOS App Store / Android APK 更新待办，以及新增客户端的发布前检查清单。
- [1.1 功能验收记录](<docs/verification-v1.1.md>)：展示预设、计时、手动方向与首次加载验证。

- [最初设计文档](<desk-clock-design.md>)：保留原始需求；其中 Vite/DOM 方案已由 Flutter Web 取代。
- [第一版验收记录](<docs/verification-v1.md>)：已验证结果与待实机验收清单。
- 提交 [.fvmrc](<.fvmrc>)、[pubspec.yaml](<pubspec.yaml>) 和 [pubspec.lock](<pubspec.lock>)；不提交 SDK、缓存、构建产物或敏感凭据。
- 升级 Flutter 应更新固定版本并重新执行全部测试、构建和目标设备验收，不直接跟随浮动 stable 升级。
