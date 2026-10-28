# 中文科技资讯聚合

## 数据范围

官方公开 RSS：少数派 <https://sspai.com/feed>、IT之家 <https://www.ithome.com/rss/>、Solidot <https://www.solidot.org/index.rss>。
2026-10-28 实测分别提供 10、60、20 条。单次生成曾为 70 条（Solidot 超时），随后全源成功并合并旧快照得到 91 条（10 / 61 / 20）；数量随源变化，不能承诺固定条数。IT之家与 Solidot 未发送跨域响应头，因此不从浏览器直接请求，也不使用第三方代理。

`tool/fetch_news.py` 仅读取标题、原文链接、来源、发布日期，不抓取全文、图片或绕过登录/付费/反爬限制。每源最长 12 秒、最多 2 MB，三路并发；失败源沿用最多 7 天缓存并明确标示。按发布时间降序，缺失/不可信时间为空并排最后，不拿抓取时间冒充发布时间。相同规范 URL / 完全一致的规范标题去重；最多保留 300 条。RSS 本身不提供无限历史，加载更多只展开当前快照已有内容。

## 构建及本地验证

Pages 应用发布在上传前执行 `python3 tool/fetch_news.py build/web/news.json`。所有源失败且无有效缓存时构建失败，避免发布空列表。离线应用构建不依赖网络；本地查看资讯前自行生成：

```sh
python3 tool/fetch_news.py build/web/news.json --previous build/web/news.json
python3 -m unittest discover -s test_python -v
node --test test_web/*.test.mjs
flutter test
```

开发服务器从 `web/` 服务时，可生成 `web/news.json`（不提交快照）。原生 WebView 使用既有 Pages base URL 读取同源快照。

## 数据专用刷新

用户于 2026-10-28 批准发布与每小时刷新。`.github/workflows/refresh-news.yml` 支持 `workflow_dispatch` 和 `23 * * * *` 每小时调度；GitHub 调度可能延迟，不保证准点更新。成功的 main 应用部署也会触发一次数据刷新，用于部署后验证；严格检查来源工作流、仓库、分支、SHA 和成功状态，不监听自身工作流，避免递归。

流程锁与应用发布统一为 `github-pages`，`queue: max` 避免新的数据刷新取消等待中的应用发布。只选择当前 main SHA、main 分支、成功完成的应用部署或数据刷新 artifact，优先最新且未过期者；数据刷新延续同一应用字节，故不依赖原始应用 artifact 永久保存。不接受 PR / 旧 SHA，上传前再次比对 main SHA。无合格 artifact 就停止，绝不回退旧应用。归档严格检查路径、大小和文件类型；只替换 `news.json`，保留 JS、version.json、SW 原字节。工作流本身不重建 Flutter、不修改版本、不推送 commit。

应用 artifact 保留 7 天，数据刷新 artifact 默认保留 1 天。每次成功数据刷新产生同一应用的新 artifact，正常小时运行可持续延续，不会在原始应用 artifact 过期后停止。若长期停跑、删除 artifact 导致当前应用全部 artifact 过期，明确失败并要求重新运行应用发布；不会静默回退旧版。

快照不列入 SW 资源清单；网络请求使用 `no-store`，不会因资讯更新触发应用更新。浏览器本地缓存是 10 分钟请求节流/断网备用，不等于源已刷新；UI 单独显示快照生成时间，超过 3 小时提示陈旧，部分失败按源提示。

官方工作流约束参考：
- <https://github.com/actions/upload-pages-artifact>（artifact 格式及 retention-days）
- <https://cli.github.com/manual/gh_run_list>（成功分支 / SHA 查询）
- <https://docs.github.com/en/actions/how-tos/write-workflows/choose-when-workflows-run/control-workflow-concurrency>（共享并发锁、queue: max）

## 本地验收（2026-10-28）

- `flutter test`：354 项通过；后续快照时间展示增补后资讯组件 3 项再次通过。
- `flutter analyze`：无问题；`dart format --output=none --set-exit-if-changed lib test`：通过。
- `node --test test_web/*.test.mjs`：258 项通过，其中调用 Python 的 10 项聚合/归档测试。
- 发布 Web 编译成功；真实生成快照 91 条（2026-10-28T14:33:05Z，三源均成功）。
- 独立代码审查已修复损坏缓存启动崩溃、未知发布日期无限续留、同源 429 退避问题；refresh job 最长 5 分钟。
- 浏览器视觉未完成：Chromium 未生成 DevToolsActivePort，45 秒启动超时，未进入页面；不等同于 iOS/macOS 真机验证。未因该环境问题继续重复尝试。
- 发布前本地验收已完成；上线后需验证 Pages 的 news.json、数据专用刷新和应用字节不变。
