import 'package:flutter/material.dart';

import 'dashboard_client.dart';
import 'dashboard_preferences.dart';
import 'dashboard_widgets.dart';

const _releaseAccent = Color(0xFF67D8C2);

class ReleasesPanel extends StatefulWidget {
  const ReleasesPanel({
    super.key,
    required this.client,
    required this.repos,
    required this.onReposChanged,
  });

  final DashboardClient client;
  final List<String> repos;
  final ValueChanged<List<String>> onReposChanged;

  @override
  State<ReleasesPanel> createState() => _ReleasesPanelState();
}

class _ReleasesPanelState extends State<ReleasesPanel> {
  final _repoController = TextEditingController();
  String? _error;
  int _page = 0;
  static const _pageSize = 4;

  @override
  void didUpdateWidget(covariant ReleasesPanel oldWidget) {
    super.didUpdateWidget(oldWidget);
    _page = _page.clamp(
      0,
      ((widget.repos.length - 1) ~/ _pageSize).clamp(0, 100),
    );
  }

  void _addPopular() {
    final known = widget.repos.map((repo) => repo.toLowerCase()).toSet();
    final expanded = [
      ...widget.repos,
      ...defaultDashboardRepos.where(
        (repo) => !known.contains(repo.toLowerCase()),
      ),
    ].take(maxDashboardRepos).toList();
    widget.onReposChanged(expanded);
  }

  @override
  void dispose() {
    _repoController.dispose();
    super.dispose();
  }

  void _addRepo() {
    final repo = _repoController.text
        .trim()
        .replaceFirst(
          RegExp(r'^https?://github\.com/', caseSensitive: false),
          '',
        )
        .replaceFirst(RegExp(r'/$'), '')
        .replaceFirst(RegExp(r'\.git$'), '');
    String? error;
    if (widget.repos.length >= maxDashboardRepos) {
      error = '最多关注 $maxDashboardRepos 个仓库，请先移除一个。';
    } else if (repo.length > 140 ||
        !RegExp(r'^[A-Za-z0-9_.-]+/[A-Za-z0-9_.-]+$').hasMatch(repo)) {
      error = '请输入 owner/repo，例如 flutter/flutter。';
    } else if (widget.repos.any((r) => r.toLowerCase() == repo.toLowerCase())) {
      error = '这个仓库已经在列表中。';
    }
    setState(() => _error = error);
    if (error != null) return;
    setState(() => _page = widget.repos.length ~/ _pageSize);
    widget.onReposChanged([...widget.repos, repo]);
    _repoController.clear();
  }

  @override
  Widget build(BuildContext context) {
    final start = _page * _pageSize;
    final visible = widget.repos.skip(start).take(_pageSize).toList();
    final pages = (widget.repos.length / _pageSize).ceil();
    final followed = widget.repos.map((repo) => repo.toLowerCase()).toSet();
    final hasMissingPopular = defaultDashboardRepos.any(
      (repo) => !followed.contains(repo.toLowerCase()),
    );
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          '已关注 ${widget.repos.length} 个项目',
          style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w600),
        ),
        const SizedBox(height: 8),
        const Text(
          '精选热门 AI、开发工具、前端与移动端项目。每页 4 个，翻页时按需加载，结果缓存 1 小时。',
          style: TextStyle(color: Color(0xFFA8B5BB), fontSize: 12, height: 1.5),
        ),
        if (pages > 1) ...[
          const SizedBox(height: 10),
          Wrap(
            spacing: 6,
            runSpacing: 4,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              TextButton.icon(
                onPressed: _page > 0 ? () => setState(() => _page--) : null,
                icon: const Icon(Icons.chevron_left_rounded),
                label: const Text('上一页'),
              ),
              DropdownButton<int>(
                value: _page,
                items: [
                  for (var i = 0; i < pages; i++)
                    DropdownMenuItem(
                      value: i,
                      child: Text(
                        '${i + 1} / $pages',
                        semanticsLabel: '第 ${i + 1} 页，共 $pages 页',
                      ),
                    ),
                ],
                onChanged: (page) {
                  if (page != null) setState(() => _page = page);
                },
              ),
              TextButton.icon(
                onPressed: _page + 1 < pages
                    ? () => setState(() => _page++)
                    : null,
                icon: const Icon(Icons.chevron_right_rounded),
                label: const Text('下一页'),
              ),
            ],
          ),
          Text(
            '正在显示第 ${start + 1}–${start + visible.length} 个，共 ${widget.repos.length} 个',
            style: const TextStyle(color: Color(0xFFA8B5BB), fontSize: 12),
          ),
        ],
        if (widget.repos.isEmpty)
          const Padding(
            padding: EdgeInsets.symmetric(vertical: 18),
            child: Text('添加你关注的 GitHub 仓库，查看最新发布。'),
          ),
        DashboardColumns(
          children: [
            for (var i = 0; i < visible.length; i++)
              Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  border: Border.all(color: dashboardBorder),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: _RepositoryRelease(
                  key: ValueKey(visible[i]),
                  client: widget.client,
                  repo: visible[i],
                  onRemove: () => widget.onReposChanged([
                    for (final repo in widget.repos)
                      if (repo != visible[i]) repo,
                  ]),
                ),
              ),
          ],
        ),
        const SizedBox(height: 12),
        const Text(
          'Release 是仓库发布记录，可能包含预发布或子组件，不一定是软件当前稳定版。',
          style: TextStyle(color: Color(0xFFA8B5BB), fontSize: 12, height: 1.5),
        ),
        const SizedBox(height: 20),
        if (widget.repos.length < maxDashboardRepos) ...[
          TextField(
            controller: _repoController,
            maxLength: 180,
            autocorrect: false,
            enableSuggestions: false,
            textInputAction: TextInputAction.done,
            onSubmitted: (_) => _addRepo(),
            onChanged: (_) {
              if (_error != null) setState(() => _error = null);
            },
            decoration: InputDecoration(
              labelText: '关注仓库',
              hintText: 'owner/repo',
              helperText: '支持仓库名称或 GitHub 仓库链接',
              helperMaxLines: 2,
              errorText: _error,
              errorMaxLines: 2,
              counterText: '',
              border: const OutlineInputBorder(),
              suffixIcon: IconButton(
                tooltip: '添加仓库',
                onPressed: _addRepo,
                icon: const Icon(Icons.add_rounded, color: _releaseAccent),
                constraints: const BoxConstraints(minWidth: 32, minHeight: 32),
              ),
            ),
          ),
          if (hasMissingPopular)
            Align(
              alignment: Alignment.centerLeft,
              child: TextButton.icon(
                onPressed: _addPopular,
                icon: const Icon(Icons.playlist_add_rounded),
                label: const Text('补齐热门项目'),
              ),
            ),
          const SizedBox(height: 12),
        ],
        const Text(
          '最多关注 $maxDashboardRepos 个。GitHub 匿名 API 通常限每个 IP 每小时 60 次请求；共享网络共用额度。',
          style: TextStyle(color: Color(0xFFA8B5BB), fontSize: 12, height: 1.5),
        ),
      ],
    );
  }
}

class _RepositoryRelease extends StatelessWidget {
  const _RepositoryRelease({
    super.key,
    required this.client,
    required this.repo,
    required this.onRemove,
  });

  final DashboardClient client;
  final String repo;
  final VoidCallback onRemove;

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      Row(
        children: [
          const Icon(Icons.code_rounded, size: 19, color: _releaseAccent),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              repo,
              style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 15),
            ),
          ),
          IconButton(
            tooltip: '移除 $repo',
            onPressed: onRemove,
            icon: const Icon(Icons.close_rounded, size: 18),
            constraints: const BoxConstraints(minWidth: 32, minHeight: 32),
          ),
        ],
      ),
      ApiSection(
        client: client,
        module: 'releases',
        args: {'repo': repo},
        sourceLabel: 'GitHub Releases',
        sourceUrl: 'https://docs.github.com/en/rest/releases/releases',
        builder: (context, result) {
          final raw = result.data['releases'];
          final releases = raw is List
              ? raw.whereType<Map>().toList()
              : <Map>[];
          if (result.data['noReleases'] == true || releases.isEmpty) {
            return Padding(
              padding: const EdgeInsets.symmetric(vertical: 12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text('此仓库尚无 Release。', style: TextStyle(fontSize: 16)),
                  const SizedBox(height: 4),
                  const Text(
                    '仓库标签和提交记录可能仍有更新。',
                    style: TextStyle(color: Color(0xFFA8B5BB), height: 1.5),
                  ),
                  TextButton.icon(
                    onPressed: () => client.openUrl('https://github.com/$repo'),
                    icon: const Icon(Icons.open_in_new_rounded, size: 15),
                    label: const Text('查看仓库'),
                    style: TextButton.styleFrom(minimumSize: const Size(0, 32)),
                  ),
                ],
              ),
            );
          }
          final release = releases.first;
          final tag = _releaseText(release['tag']);
          final name = _releaseText(release['name']);
          final body = _releaseExcerpt(_releaseText(release['body']));
          final date = DateTime.tryParse(_releaseText(release['publishedAt']));
          final url = _releaseText(release['url']);
          return Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                tag.isNotEmpty ? tag : (name.isNotEmpty ? name : '最新发布'),
                style: const TextStyle(
                  color: _releaseAccent,
                  fontSize: 20,
                  fontWeight: FontWeight.w600,
                  height: 1.3,
                ),
              ),
              if (release['prerelease'] == true)
                const Text(
                  '预发布版本',
                  style: TextStyle(color: Color(0xFFE9C48B), fontSize: 12),
                ),
              if (repo.toLowerCase() == 'flutter/flutter')
                TextButton(
                  onPressed: () =>
                      client.openUrl('https://github.com/flutter/flutter/tags'),
                  child: const Text('Flutter 的 Release 记录可能滞后，查看版本标签'),
                ),
              if (name.isNotEmpty && name != tag) ...[
                const SizedBox(height: 4),
                Text(name, style: const TextStyle(fontSize: 15, height: 1.4)),
              ],
              const SizedBox(height: 8),
              Text(
                date == null
                    ? '发布日期未提供'
                    : '发布于 ${_releaseDate(date.toLocal())}',
                style: const TextStyle(color: Color(0xFFA8B5BB), fontSize: 12),
              ),
              const SizedBox(height: 12),
              Text(
                body.isEmpty ? '该版本未提供发布说明。' : body,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(color: Color(0xFFD4DCDD), height: 1.6),
              ),
              TextButton.icon(
                onPressed: () => client.openUrl(
                  url.isNotEmpty ? url : 'https://github.com/$repo/releases',
                ),
                icon: const Icon(Icons.open_in_new_rounded, size: 15),
                label: const Text('完整发布说明'),
                style: TextButton.styleFrom(minimumSize: const Size(0, 32)),
              ),
            ],
          );
        },
      ),
    ],
  );
}

String _releaseText(Object? value) => value is String ? value : '';

String _releaseDate(DateTime date) =>
    '${date.year}-${date.month.toString().padLeft(2, '0')}-${date.day.toString().padLeft(2, '0')}';

String _releaseExcerpt(String body) {
  final plain = body
      .replaceAll(RegExp(r'<!--[\s\S]*?-->'), '')
      .replaceAll(RegExp(r'```[\s\S]*?```'), '')
      .replaceAll(RegExp(r'!\[[^\]]*\]\([^)]*\)'), '')
      .replaceAllMapped(RegExp(r'\[([^\]]+)\]\([^)]*\)'), (m) => m[1]!)
      .replaceAll(RegExp(r'[#*_`~>]'), '')
      .replaceAll(RegExp(r'\s+'), ' ')
      .trim();
  return plain.length <= 360 ? plain : '${plain.substring(0, 360)}…';
}
