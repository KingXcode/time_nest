import 'package:flutter/material.dart';

import 'dashboard_client.dart';
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
    if (widget.repos.length >= 4) {
      error = '最多关注 4 个仓库，请先移除一个。';
    } else if (repo.length > 140 ||
        !RegExp(r'^[A-Za-z0-9_.-]+/[A-Za-z0-9_.-]+$').hasMatch(repo)) {
      error = '请输入 owner/repo，例如 flutter/flutter。';
    } else if (widget.repos.any((r) => r.toLowerCase() == repo.toLowerCase())) {
      error = '这个仓库已经在列表中。';
    }
    setState(() => _error = error);
    if (error != null) return;
    widget.onReposChanged([...widget.repos, repo]);
    _repoController.clear();
  }

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      if (widget.repos.isEmpty)
        const Padding(
          padding: EdgeInsets.symmetric(vertical: 18),
          child: Text('添加你关注的 GitHub 仓库，查看最新发布。'),
        ),
      for (var i = 0; i < widget.repos.length; i++) ...[
        if (i > 0) const Divider(height: 32, color: Color(0xFF30363A)),
        _RepositoryRelease(
          key: ValueKey(widget.repos[i]),
          client: widget.client,
          repo: widget.repos[i],
          onRemove: () => widget.onReposChanged([
            for (final repo in widget.repos)
              if (repo != widget.repos[i]) repo,
          ]),
        ),
      ],
      const SizedBox(height: 20),
      if (widget.repos.length < 4) ...[
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
              constraints: const BoxConstraints(minWidth: 48, minHeight: 48),
            ),
          ),
        ),
        const SizedBox(height: 12),
      ],
      Text(
        '已关注 ${widget.repos.length}/4 · GitHub 匿名 API 通常限每个 IP 每小时 60 次请求。共享网络也会共享额度。',
        style: const TextStyle(
          color: Color(0xFFA8B5BB),
          fontSize: 12,
          height: 1.5,
        ),
      ),
    ],
  );
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
            constraints: const BoxConstraints(minWidth: 48, minHeight: 48),
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
                    style: TextButton.styleFrom(minimumSize: const Size(0, 48)),
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
                  fontSize: 28,
                  fontWeight: FontWeight.w600,
                  height: 1.3,
                ),
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
                maxLines: 4,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(color: Color(0xFFD4DCDD), height: 1.6),
              ),
              TextButton.icon(
                onPressed: () => client.openUrl(
                  url.isNotEmpty ? url : 'https://github.com/$repo/releases',
                ),
                icon: const Icon(Icons.open_in_new_rounded, size: 15),
                label: const Text('完整发布说明'),
                style: TextButton.styleFrom(minimumSize: const Size(0, 48)),
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
