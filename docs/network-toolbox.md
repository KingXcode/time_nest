# 网络测速：设计与验证

## 功能与边界

「全球网测」App Store 页面作为功能分类参考，不复制其品牌、素材、原生界面或专有节点。该原生应用介绍宽带测速、体验评测、网络诊断及中国信通院自有测试节点；其介绍不是面向本站的节点使用许可，也不是公开服务 API。

此刻继续使用 Flutter Web + GitHub Pages 静态部署，无账号、无 API Key、无自建代理或后端。首页和每日看板提供独立网络测速入口，原时钟、天气、资讯、数字货币功能不变。

| 工具 | 实际实现 | 不应推断 |
| --- | --- | --- |
| 网速测试 | 访问 Cloudflare 官方公开测速端点，小流量单请求 HTTP 吞吐量、请求延迟与抖动参考 | 不是全球多节点测评、运营商线路认证、5G/千兆带宽认证或最大接入速率 |
| 延迟检测 | 测量当前站点托管节点的 10 次 HTTPS 请求，排除 1 次预热 | 不是 ICMP Ping、TCP 握手耗时、真实网络丢包率或所有网站的可达性 |
| DNS 查询 | Cloudflare 公共 DNS-over-HTTPS 的 A / AAAA / CNAME / MX / TXT / NS 记录 | 不是本地设备实际配置的 DNS，也不扫描内网 |
| 浏览器信息 | 浏览器在线标志、安全上下文和可用时的网络性能估计 | `onLine` 不证明互联网可达；`effectiveType=4g` 不等于正在使用 4G 蜂窝网络 |

浏览器不能可靠获取 Wi-Fi SSID、信号强度、运营商、局域网设备、原始 ICMP/TCP、Traceroute 或任意国家节点。不提供装作可用的入口、虚构评分或假数据。不调用参考 App 的未公开接口。

## 交互与隐私

- 页面打开、切换工具、读取浏览器信息均不启动网络测试。每种工具的说明旁有默认不勾选的确认选项，勾选后再点开始才执行；切换工具时重置确认。
- 测速和 DNS 请求直接发送给 Cloudflare，服务方会收到访客公网 IP 等常规连接信息；DNS 还会收到输入的域名与记录类型。测速上传仅使用本地生成的随机合成字节，不读取用户文件。
- 本站 HTTPS 延迟探针连接当前站点托管服务，通常为 GitHub Pages。独立于 Cloudflare 测速端点，不表示全网质量。
- 同一时间只运行一个操作。可取消，离开工具或转入后台会取消。每个请求最多 8 秒，整次操作最多 45 秒；不会后台恢复或自动重新测试。
- 网速/延迟最多保存 20 条指标记录，只存本次时间、工具、固定目标、完成状态和有效指标，不增加分析埋点。中断/失败记录不保存速度，明确标示未完成；支持手动清空。存储不可用时提示但不影响工具。
- 不持久化 IP 或查询域名；DNS 不进入历史，结果只保留在当前工具页内存。读取和清空历史不会请求网络。
- 固定来源与隐私/条款链接；不接受用户提供任意 URL、认证信息、内网地址或下载节点。DNS 域名经过 IDNA 与标签校验，拒绝 URL、路径、端口、IP 与常见本地域名。
- 所有网络请求使用 `credentials: omit`、`referrerPolicy: no-referrer`、`cache: no-store`，禁止重定向。403/429 等 HTTP 失败直接结束，不绕过、不切换代理或镜像；失败不回填为 0 或成功结果。

## 测量口径

### Cloudflare 小流量测试

来源为 [Cloudflare 官方 Speedtest 组件](https://github.com/cloudflare/speedtest)，使用其公开文档中的 `https://speed.cloudflare.com/__down?bytes=N` 与 `https://speed.cloudflare.com/__up`。

1. 1 次零字节预热，不计入延迟结果。
2. 5 次零字节请求。延迟为完整请求耗时平均值；抖动为相邻成功样本耗时差的绝对值平均值，失败样本不会被跨过当作相邻样本。
3. 下载 256 KiB、1 MiB、4 MiB，实际从响应流计数字节并与请求长度匹配。
4. 上传 256 KiB、1 MiB 的随机合成字节，收到成功 HTTP 响应且完整读取其小型响应后才计入结果。
5. 吞吐量为有效测量的实际字节总数 × 8 / 对应完整请求耗时总和，换算成十进制 Mbps。单次少于 20 毫秒的样本不用于吞吐量，避免短样本制造极高值。

测试请求体积为 6.5 MiB，响应补充数据后仍小于 7 MiB，协议开销另计。包含连接/服务器延迟，单连接、小流量和固定节点都会影响结果，尤其不适合作为高速宽带的上限。失败或取消可能仍产生已经传输的流量；页面统计只包含成功完成的传输，不是运营商计费流量。

### 本站 HTTPS 延迟

专用 `network-probe.txt` 必须返回固定小型内容。请求带唯一参数与 `no-store`；Service Worker 不接管此路径，离线缓存清单也排除该文件，避免缓存命中被显示为网络速度。1 次预热 + 10 次采样。结果可展示成功数和请求失败情况，但不称为网络丢包。

### DNS

使用 [Cloudflare JSON DoH 文档](https://developers.cloudflare.com/1.1.1.1/encryption/dns-over-https/make-api-requests/dns-json/) 中的 `https://cloudflare-dns.com/dns-query`，请求头 `Accept: application/dns-json`。校验响应状态、问题字段、记录数、大小、TTL 及记录结构；截断响应不当作完整结果。NXDOMAIN 与无匹配记录和传输失败区分。AD 标记只表示该解析器声明完成 DNSSEC 校验，不代表网站安全。

## 验证边界

当前代码检查：Dart 格式检查通过、静态分析无问题，240 项 Flutter 测试与 211 项 Node 测试通过。发布构建成功，48 个离线资源哈希全部核验通过；网络探针不进入离线缓存。独立代码复核无剩余问题。另用 Flutter 渲染真实桌面/手机界面进行像素检查，覆盖默认未启动状态；不将夹具或截图称为真实网速实测。

- 自动化使用可控响应测试字节计数、计时/计算、固定目标、取消、超时、后台停止、恶意输入、DNS 错误、空值以及缓存旁路。固定样本是测试夹具，不进入产品。
- 2026-10-20 研究环境的 Cloudflare DNS 请求返回 HTTP 200，允许跨域，取得真实 `example.com` A 记录。
- 同日研究环境的 Cloudflare 测速零字节请求返回 HTTP 403；dot 云浏览器直接打开同一官方零字节 URL 被浏览器报告 `net::ERR_BLOCKED_BY_CLIENT`。未绕过限制，无法据此判断用户网络中的可用性，亦未完成真实端到端吞吐量或上传验收。
- 本地 Chromium 完整自动化浏览器测试受既有执行环境限制，不作为已通过项目。响应式布局与中断流程由 Flutter 组件测试覆盖；iPhone Safari 与主屏幕模式仍需实机验收。
- 发布和 GitHub Pages 部署需另行授权。本次开发不代表已上线。

## 来源

- [全球网测 App Store 介绍](https://apps.apple.com/cn/app/id1668623776)
- [Cloudflare Speedtest 开源组件](https://github.com/cloudflare/speedtest)
- [Cloudflare 网站条款](https://www.cloudflare.com/website-terms/)
- [Cloudflare 隐私政策](https://www.cloudflare.com/privacypolicy/)
- [Cloudflare DNS JSON API](https://developers.cloudflare.com/1.1.1.1/encryption/dns-over-https/make-api-requests/dns-json/)
- [Network Information API 规范](https://wicg.github.io/netinfo/)
