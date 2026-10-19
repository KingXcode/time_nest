# 本机 BaoStock 个人研究版

本功能仅用于运行者本机的个人研究，不构成投资建议。默认构建保持现有公开页面；只有显式设置 `LOCAL_MARKET_RESEARCH=true` 才替换为 Flutter 原生收盘线图。该配置不代表获得公开展示或再分发数据的许可，不用于 GitHub Pages 部署。

## 运行

使用 `.fvmrc` 固定的 Flutter 3.47.5，及任务目录中已验证的 Python venv（BaoStock 0.9.4）。不修改全局 SDK 或 Python，不需要账号、API Key 或 VIP 节点。

```bash
fvm flutter pub get --offline
bash tool/build_web.sh --dart-define=LOCAL_MARKET_RESEARCH=true

# 将两个绝对路径替换为自己的任务 venv 和仓库外缓存目录。
/absolute/task/venv/bin/python tool/local_market.py \
  --cache-dir /absolute/task/market-cache \
  --port 8787
```

打开 `http://127.0.0.1:8787`，进入「每日看板 → A股行情」。服务在当前终端前台运行，按 `Ctrl+C` 关闭；不创建开机任务或常驻守护服务。被执行沙箱阻止联网时使用环境正常的联网授权流程，不修改 DNS、代理或防火墙。

应用文件和 `/api/market-history` 使用同一来源。服务固定绑定 IPv4 回环 `127.0.0.1`，校验 Host、Origin 与浏览器跨站请求信息，不输出允许跨域的 CORS 头。浏览器适配器也拒绝非 localhost 页面。不提供任意 URL 转发，不开放局域网或公网端口。

## 数据和状态

- 固定三个指数：上证 `sh.000001`、沪深300 `sh.000300`、深证成指 `sz.399001`。其他旧选择必须由用户重新选择，不静默替换为不同指数。
- 第一次请求或允许的刷新会通过一个匿名 BaoStock 连接，串行获取三个指数；每次批量结束尝试 logout 并关闭套接字。仅使用默认公共域名 `public-api.baostock.com:10030`，不切换节点。
- 查询上海时区的昨天及之前共 30 个自然日，字段为 `date,code,open,high,low,close,volume,amount`。前端仅消费日期与收盘点位；点击曲线或拖动日期滑杆不会再次访问 BaoStock。
- 保留来源返回的真实日期和原获取时间。数据时效默认「未核实」，不会根据 HTTP 成功或工作日猜测已经更新到最新交易日；不展示今日尚未收盘的数据。
- 缓存默认有效 15 分钟，手动刷新最短间隔 60 秒。跨线程/进程文件锁串行化同一缓存目录的请求；服务本身也使用单线程 HTTPServer。运行一个服务实例并共用同一缓存目录。
- 取数失败可保留最多 7 天的旧缓存，明确标记过期，不改写原获取时间。首次失败或缓存损坏/超期时返回错误，前端保留已有图表并提示失败，或显示无数据状态。
- 套接字超时 15 秒；每次登录/查询的总时限 20 秒；登出时限 8 秒；子进程总时限 95 秒。浏览器请求与组件也设有稍大的有界超时。
- 原始缓存只能写在 Git 仓库外，缓存目录位于任何 Git 仓库中都会被拒绝。接口响应设置 `Cache-Control: no-store`，不纳入应用 Service Worker 资源缓存。

## 验证

```bash
/absolute/task/venv/bin/python -m unittest discover -s test_local -v
fvm flutter analyze --no-pub
fvm flutter test --no-pub
node --test test_web/*.test.mjs
```

测试中的行情全部为明确标记的合成数据。真实行情和浏览器验证输出保存在任务目录的仓库外位置，不提交到 GitHub。当前完成范围为本机浏览器；手机访问 localhost 会指向手机自己，尚未启用手机访问，也未据窄屏自动测试宣称通过 iPhone Safari 实机验收。
