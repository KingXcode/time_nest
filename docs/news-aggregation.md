# 中文科技资讯聚合

## 数据范围

官方公开 RSS：少数派 <https://sspai.com/feed>、IT之家 <https://www.ithome.com/rss/>、Solidot <https://www.solidot.org/index.rss>。
2026-10-28 实测分别提供 10、60、20 条。单次生成曾为 70 条（Solidot 超时），随后全源成功并合并旧快照得到 91 条（10 / 61 / 20）；数量随源变化，不能承诺固定条数。IT之家与 Solidot 未发送跨域响应头，因此不从浏览器直接请求，也不使用第三方代理。

`tool/fetch_news.py` 仅读取标题、原文链接、来源、发布日期，不抓取全文、图片或绕过登录/付费/反爬限制。每源最长 12 秒、最多 2 MB，三路并发；失败源沿用最多 7 天缓存并明确标示。按发布时间降序，缺失/不可信时间为空并排最后，不拿抓取时间冒充发布时间。相同规范 URL / 完全一致的规范标题去重；最多保留 300 条。RSS 本身不提供无限历史，加载更多只展开当前快照已有内容。

## 应用内阅读与内容许可

资讯详情在标题下直接提供「阅读原文」，再显示来源与原始发布时间。文章信息来自已经加载的快照，打开详情不会重复请求原文页。详情明确区分「全文」「摘要」和「未提供正文」，不会把截断文字或标题当作完整文章。

**当前三个中文来源均未启用正文或摘要转载。** 截至 2026-10-28，尚未确认适用于本公开站点的正文再发布许可；可取得 RSS 内容不代表获得转载授权。少数派 [协议](https://sspai.com/page/agreement) 的使用授权有个人用途限制，且 [官方说明](https://sspai.com/post/71637) 已将 RSS 从全文改为摘要；Solidot [条款](https://developers.solidot.org/terms) 要求内容复制/转载联系取得许可；IT之家暂未找到明确允许本用途的授权。因此当前界面提供原文链接与信息，不显示未经许可的片段，不承诺所有来源都能应用内读全文。HN 也不抓取外链正文。此处是本应用的保守内容策略，不是对其他使用场景的法律结论。

### 可扩展且默认拒绝的契约

继续使用 `schemaVersion: 1`，原字段不变，`stories[].content` 是可选附加字段。旧快照缺少该字段仍能读，旧版应用会忽略它。形状如下（仅示例，不表示已有许可）：

```json
{"kind":"unavailable","reason":"permission_required"}
{"kind":"excerpt","format":"plain_text","text":"自造测试摘要。","licenseUrl":"https://example.test/license"}
{"kind":"full","format":"plain_text","text":"自造测试正文。","licenseUrl":"https://example.test/license"}
```

不可用原因仅有 `permission_required`、`not_provided`、`invalid_content`、`too_large`。摘要最多 280 个字符，超出后以省略号明确截断；完整正文最多 24,000 个字符，超限就回到原文链接，**不会截断后继续标记全文**。生成器限制原始 HTML 64 KB、嵌套 64 层及 10,000 个开始标签；仅输出段落纯文本，去除脚本、样式、iframe、嵌入内容、隐藏元素和图片，不输出属性或可点击正文链接，不加载跟踪资源。XML 限制 2 MB、64 层、20,000 个元素，并拒绝 DTD/实体声明与空字节编码。整份快照最多 850 KB（UTF-8）；达到上限时优先放弃正文，不丢文章标题/链接，不更改正文标签以掩盖截断。

将来新增可复用内容时必须先确认授权适用于公开再发布、保留授权证据与所需署名，然后同步更新三处**代码内**策略：

1. `tool/fetch_news.py` 的 `REUSE_POLICIES[sourceId]`：`mode` 为 `excerpt` 或 `full`，`licenseUrl` 为固定 HTTPS 授权依据，`field` 为获准的 `description` 或 `{http://purl.org/rss/1.0/modules/content/}encoded`。`full` 不允许使用 `description`，还必须明确设置 `verifiedFullText: True`，确认该字段确实完整且授权覆盖它。
2. `web/dashboard.js` 的 `newsContentGrants[sourceId]`：同一个 `mode` 与 `licenseUrl`。当前表为空，任何从网络或缓存自行声称有授权的内容都会丢弃。
3. Dart 阅读器的 `NewsReusePermission` 源策略：同样限定模式与授权 URL；不得让 RSS/JSON 的 `license`、`licenseUrl` 或 `kind` 自行授予展示权。

授权依据必须允许页面现有的来源、原文链接和许可链接署名方式；若还要求作者等信息，先扩展并验证署名字段。全文字段必须是完整的转义/CDATA HTML；包含 XML 子节点时拒绝展示，避免 `findtext` 只取前半段而误标全文。开启授权必须伴随对应测试及来源说明更新。变更许可或撤回来源时，旧快照、网络响应、本地缓存都重新验证，未知字段被丢弃；缓存中的旧正文会尽力清理（存储禁用时不能保证写回，但仍不交给界面）。不新增文章抓取端点、第三方代理、秘钥或 GitHub 权限；不绕过登录、付费、验证码或访问限制。Python 的授权路径只用自造 fixture 测试，没有在生产策略加入测试授权。

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


## 资讯详情页提交前验收（2026-10-28）

基于已发布提交 `59319da9b2dd66383c879e435c22bd4564a905e5` 安全快进后实现；没有覆盖本地修改，没有调整现有移动端边界/设置覆盖层、小时工作流、权限或 SW 排除规则。

- 资讯列表和看板摘要点击标题均进入详情；标题紧接「阅读原文」，随后显示来源、绝对发布时间及原文域名。来源无授权/无正文/正文异常/超限状态明确区分，不虚构摘要。
- 详情使用当前快照，不发起额外正文请求；保留旧数据及来源失败提示。快速点击使用 Navigator 级锁，返回/系统 Back/Escape 保留列表滚动位置及已展开数量。
- 新增模型和组件用例覆盖恶意 URL、伪造许可、旧快照、纯文本/正文长度、原文打开失败、列表加载/错误/重试、原文按钮位置、概览入口、连续点击、返回、320px 窄屏/横屏/桌面及双倍字体。
- 真实三源生成成功：90 条，所有正文均为 `permission_required`。没有获取文章页面或转载来源正文。
- 新详情中文字形已核验被现有字体覆盖，无需提交字体或图标重新生成造成的无关二进制变化。
- Flutter 组件渲染截图已人工查看：`build/news-detail-previews/`（手机、320px 双倍字体、桌面）；可运行 `NEWS_DETAIL_SCREENSHOTS=1 flutter test test/news_detail_visual_test.dart` 复现。它们不是浏览器或 iPhone Safari 真机验证。
- cloud CUA 浏览器访问执行器的 `http://127.0.0.1:8880/time_nest/` 返回 `net::ERR_CONNECTION_REFUSED`，未完成真实浏览器渲染；没有放宽浏览器沙箱或重试此前失败的独立 Chromium 启动。预览服务已停止。
- 本地完整 Web 构建与 SW 生成通过。最初遇到旧 `build/web/time_nest -> .` 预览软链接；已移至 `/tmp/time-nest-old-build-symlink-20261028` 保留后重建，不改源文件。用户随后授权提交推送及部署，源码版本更新为 `2.7.0+18`；线上构建号继续加上发布工作流序号，不重置序号。

最终结果：`flutter analyze` 无问题；格式检查 101 文件无变化；`flutter test` 366/366；`node --test test_web/*.test.mjs` 263/263（含 Python 18 项）；独立审查无阻断问题。构建产物仍排除 `news.json` 的 SW 缓存。以上为此次提交前的本地验证；线上版本、Pages 部署及随后的数据专用刷新需以该提交的工作流结果核实。
