import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'browse.dart';
import 'catalog.dart';
import 'library.dart';
import 'player.dart';
import 'source_presets.dart';

part 'home.dart';

void main() => runApp(const YouyingApp());

/// New user interface, not a reproduction of the original AOT widget tree.
class YouyingApp extends StatefulWidget {
  const YouyingApp({super.key});

  @override
  State<YouyingApp> createState() => _YouyingAppState();
}

class _YouyingAppState extends State<YouyingApp> {
  late final Future<Library> library = Library.open();

  @override
  Widget build(BuildContext context) => MaterialApp(
        title: '柚影',
        theme: youyingTheme(),
        home: FutureBuilder<Library>(
          future: library,
          builder: (context, snapshot) {
            if (snapshot.hasError) {
              return const Scaffold(body: Center(child: Text('无法读取本地数据')));
            }
            if (!snapshot.hasData) {
              return const Scaffold(
                  body: Center(child: CircularProgressIndicator()));
            }
            return HomePage(library: snapshot.requireData);
          },
        ),
      );
}

class SearchPage extends StatefulWidget {
  const SearchPage({super.key, required this.library, this.client});
  final Library library;
  final CatalogClient? client;

  @override
  State<SearchPage> createState() => _SearchPageState();
}

class _SearchPageState extends State<SearchPage> {
  final TextEditingController query = TextEditingController();
  late final CatalogClient client = widget.client ?? CatalogClient();
  List<MediaEntry> results = [];
  bool searching = false;
  String? status;
  final List<String> sourceResults = [];

  @override
  void dispose() {
    if (widget.client == null) client.dispose();
    query.dispose();
    super.dispose();
  }

  Future<void> _search() async {
    if (searching ||
        query.text.trim().isEmpty ||
        widget.library.enabledSources.isEmpty) {
      return;
    }
    setState(() {
      searching = true;
      results = [];
      sourceResults.clear();
      status = '正在搜索已启用的源…';
    });
    final searchQuery = query.text.trim();
    final all = <MediaEntry>[];
    var failed = 0;
    final sources = widget.library.enabledSources;
    for (final source in sources) {
      if (!widget.library.enabledSources.any((current) =>
          current.name == source.name && current.url == source.url)) {
        if (!mounted) return;
        setState(() => sourceResults.add('${source.name}：已停用或移除，跳过'));
        continue;
      }
      String summary;
      try {
        final found = await client.search(source, searchQuery);
        all.addAll(found);
        summary = '${source.name}：${found.length} 条';
      } catch (_) {
        failed++;
        summary = '${source.name}：请求失败或返回格式不兼容';
      }
      if (!mounted) return;
      setState(() {
        results = List.of(all);
        sourceResults.add(summary);
        status =
            '已完成 ${sourceResults.length}/${sources.length} 个源，找到 ${all.length} 条';
      });
    }
    setState(() {
      results = all;
      searching = false;
      status = failed > 0
          ? '找到 ${all.length} 条；$failed 个源未返回受支持的 JSON（或连接失败）。'
          : '找到 ${all.length} 条。来自已启用的第三方源，并非原应用服务。';
    });
  }

  Future<void> _direct() async {
    final submitted = await showDialog<({String primary, String secondary})>(
      context: context,
      builder: (_) => const _InputDialog(
        title: '直接播放你有权访问的媒体',
        primaryLabel: 'HTTPS 媒体地址（MP4 / HLS / DASH）',
        secondaryLabel: '请求头 JSON（可空，不保存）',
        confirm: '播放',
        help: '可选 Referer / User-Agent 等请求头只用于本次播放。',
      ),
    );
    if (!mounted || submitted == null) return;
    try {
      final url = submitted.primary;
      SourceEndpoint.parseHttps(url);
      final headers = parseHeaders(submitted.secondary);
      final entry = MediaEntry(
        id: 'manual:$url',
        title: '手动输入的媒体',
        source: '用户输入',
        lines: {
          '直链': [Episode(name: '播放', url: url)]
        },
      );
      await Navigator.push<void>(
        context,
        MaterialPageRoute(
            builder: (_) => PlayerPage(
                entry: entry, library: widget.library, headers: headers)),
      );
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('请输入有效的 HTTPS URL 和 JSON 格式请求头')),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) =>
      ListView(padding: const EdgeInsets.all(16), children: [
        TextField(
          controller: query,
          onSubmitted: (_) => _search(),
          textInputAction: TextInputAction.search,
          decoration: InputDecoration(
            labelText: '从已启用的源中搜索',
            border: const OutlineInputBorder(),
            suffixIcon: IconButton(
              tooltip: '搜索',
              icon: const Icon(Icons.search),
              onPressed: widget.library.enabledSources.isEmpty || searching
                  ? null
                  : _search,
            ),
          ),
        ),
        const SizedBox(height: 12),
        Align(
            alignment: Alignment.centerRight,
            child: TextButton.icon(
              onPressed: _direct,
              icon: const Icon(Icons.play_circle_outline, size: 18),
              label: const Text('手动播放直链'),
            )),
        Text(status ??
            '已启用 ${widget.library.enabledSources.length} 个源；输入关键词开始搜索，不会自动请求。'),
        for (final result in sourceResults) Text(result),
        if (searching) const LinearProgressIndicator(),
        const SizedBox(height: 6),
        EntryList(
          entries: results,
          title: '搜索结果',
          empty: widget.library.enabledSources.isEmpty
              ? '没有启用的源，请在“设置”中启用或添加。'
              : '输入关键词并点击搜索。',
          library: widget.library,
        ),
      ]);
}

class EntryList extends StatelessWidget {
  const EntryList(
      {super.key,
      required this.entries,
      required this.library,
      required this.title,
      required this.empty});
  final List<MediaEntry> entries;
  final Library library;
  final String title;
  final String empty;

  @override
  Widget build(BuildContext context) => Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 12),
            child: Text(title, style: Theme.of(context).textTheme.titleMedium),
          ),
          if (entries.isEmpty)
            Padding(
              padding: const EdgeInsets.all(16),
              child: Text(empty),
            ),
          for (final entry in entries)
            Padding(
                padding: const EdgeInsets.only(bottom: 12),
                child: _CatalogCard(
                  entry: entry,
                  trailing: IconButton(
                    tooltip:
                        library.favorites.containsKey(entry.id) ? '取消收藏' : '收藏',
                    icon: Icon(library.favorites.containsKey(entry.id)
                        ? Icons.favorite
                        : Icons.favorite_border),
                    onPressed: () => library.toggleFavorite(entry),
                  ),
                  onTap: () => Navigator.push<void>(
                    context,
                    MaterialPageRoute(
                        builder: (_) =>
                            DetailPage(entry: entry, library: library)),
                  ),
                )),
        ],
      );
}

class DetailPage extends StatefulWidget {
  const DetailPage(
      {super.key, required this.entry, required this.library, this.client});
  final MediaEntry entry;
  final Library library;

  final CatalogClient? client;

  @override
  State<DetailPage> createState() => _DetailPageState();
}

class _DetailPageState extends State<DetailPage> {
  late MediaEntry entry = widget.entry;
  late final CatalogClient client = widget.client ?? CatalogClient();
  Library get library => widget.library;
  bool loading = false;
  String? error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final sources =
        library.enabledSources.where((source) => source.name == entry.source);
    if (entry.remoteId == null || sources.isEmpty || loading) return;
    setState(() {
      loading = true;
      error = null;
    });
    try {
      final full = await client.detail(sources.first, entry);
      if (mounted) setState(() => entry = full);
    } catch (_) {
      if (mounted) setState(() => error = '详情请求失败；已保留现有线路，可重试');
    } finally {
      if (mounted) setState(() => loading = false);
    }
  }

  @override
  void dispose() {
    if (widget.client == null) client.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Scaffold(
        appBar: AppBar(
            title:
                Text(entry.title, maxLines: 1, overflow: TextOverflow.ellipsis),
            actions: [
              AnimatedBuilder(
                  animation: library,
                  builder: (context, _) => IconButton(
                        tooltip: library.favorites.containsKey(entry.id)
                            ? '取消收藏'
                            : '收藏',
                        icon: Icon(
                            library.favorites.containsKey(entry.id)
                                ? Icons.star
                                : Icons.star_outline,
                            color: _orange),
                        onPressed: () => library.toggleFavorite(entry),
                      )),
            ]),
        body: ListView(padding: const EdgeInsets.all(16), children: [
          if (loading) const LinearProgressIndicator(),
          if (error != null) ...[
            Text(error!),
            TextButton(onPressed: _load, child: const Text('重试详情')),
          ],
          Text(entry.source, style: Theme.of(context).textTheme.labelMedium),
          const SizedBox(height: 12),
          Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
            SizedBox(
                width: 100,
                height: 146,
                child: ClipRRect(
                    borderRadius: BorderRadius.circular(8),
                    child: _Poster(entry: entry))),
            const SizedBox(width: 14),
            Expanded(
                child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                  Text(entry.title,
                      style: const TextStyle(
                          fontSize: 18, fontWeight: FontWeight.bold)),
                  const SizedBox(height: 12),
                  Text(
                      [entry.year, entry.category, entry.area]
                          .where((s) => s.isNotEmpty)
                          .join(' / '),
                      style: const TextStyle(color: _muted, fontSize: 12)),
                  const SizedBox(height: 12),
                  Text(entry.remarks,
                      style: const TextStyle(color: _orange, fontSize: 12)),
                ])),
          ]),
          const _SectionHeader(title: '剧情简介', inset: 0),
          Text(entry.description.isEmpty ? '暂无简介' : entry.description),
          const SizedBox(height: 12),
          if (!entry.playable) const Text('没有确认可播放的直链；可能需要未恢复的解析接口。'),
          for (final line in entry.lines.entries) ...[
            Text(line.key, style: Theme.of(context).textTheme.titleMedium),
            Wrap(spacing: 8, children: [
              for (final episode in line.value)
                OutlinedButton(
                  onPressed: () => Navigator.push<void>(
                    context,
                    MaterialPageRoute(
                        builder: (_) => PlayerPage(
                              entry: entry,
                              initial: episode,
                              library: library,
                            )),
                  ),
                  child: Text(episode.name),
                ),
            ]),
          ],
        ]),
      );
}

class LibraryPage extends StatelessWidget {
  const LibraryPage(
      {super.key, required this.library, this.showHistory = true});
  final Library library;
  final bool showHistory;

  @override
  Widget build(BuildContext context) =>
      ListView(padding: const EdgeInsets.all(16), children: [
        const Text('下载支持前台 MP4/WebM 和无加密的 HLS 点播；不支持直播、DRM 或原 APK 后台任务。'),
        const SizedBox(height: 12),
        if (showHistory)
          EntryList(
            entries: library.history.values.toList().reversed.toList(),
            library: library,
            title: '观看历史',
            empty: '尚无观看历史。',
          ),
        const Divider(),
        Text('已下载文件：${library.downloads.length}',
            style: Theme.of(context).textTheme.titleMedium),
        for (final entry in library.downloads.entries)
          ListTile(
            leading: const Icon(Icons.offline_pin),
            title: Text(_downloadTitle(entry.key)),
            subtitle: const Text('在相应的播放器页面点击“播放已下载文件”'),
          ),
      ]);

  String _downloadTitle(String key) {
    try {
      final parts = jsonDecode(key);
      if (parts is List && parts.length == 2 && parts[0] is String) {
        final entry = library.history[parts[0]];
        if (entry != null) {
          for (final episodes in entry.lines.values) {
            for (final episode in episodes) {
              if (episode.url == parts[1]) {
                return '${entry.title} · ${episode.name}';
              }
            }
          }
          return entry.title;
        }
      }
    } on FormatException {
      return '已保存文件';
    }
    return '已保存文件';
  }
}

class SettingsPage extends StatefulWidget {
  const SettingsPage({super.key, required this.library});
  final Library library;

  @override
  State<SettingsPage> createState() => _SettingsPageState();
}

class _SettingsPageState extends State<SettingsPage> {
  bool saving = false;

  Future<void> _change(Future<void> Function() action) async {
    if (saving) return;
    setState(() => saving = true);
    try {
      await action();
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('源配置保存失败，请检查输入并重试')),
        );
      }
    } finally {
      if (mounted) setState(() => saving = false);
    }
  }

  Future<void> _addSource() async {
    final submitted = await showDialog<({String primary, String secondary})>(
      context: context,
      builder: (_) => const _InputDialog(
        title: '添加你信任的源',
        primaryLabel: '名称',
        secondaryLabel: 'HTTPS JSON 接口',
        confirm: '保存',
        help: '兼容 HTTPS JSON 点播接口；启用后用于首页分类、列表、搜索和详情。',
      ),
    );
    if (submitted == null || !mounted) return;
    await _change(() => widget.library.addSource(
        SourceEndpoint(name: submitted.primary, url: submitted.secondary)));
  }

  @override
  Widget build(BuildContext context) => AnimatedBuilder(
      animation: widget.library,
      builder: (context, _) =>
          ListView(padding: const EdgeInsets.all(16), children: [
            Text('源配置', style: Theme.of(context).textTheme.titleLarge),
            Text(
                '共 ${widget.library.sources.length} 个源，已启用 ${widget.library.enabledSources.length} 个。'),
            const Text(
                '公开源由 GitHub 配置收录，不等于内容授权或长期可用。升级补充新源并清理退役预设；保留自定义接口和启停状态，删除后不会自动恢复。'),
            const SelectableText(sourcePresetRepository),
            const Text('停用后不再发起该源的搜索/详情请求；不取消已开始的请求或播放。'),
            const SizedBox(height: 12),
            for (final source in widget.library.sources)
              Card(
                  child: ListTile(
                title: Text(source.name),
                subtitle: Text(
                    '${source.url}\n${presetFor(source) == null ? '用户手动配置；未验证' : '$sourcePresetCheckedOn 历史抽查：${presetFor(source)!.observation}'}'),
                isThreeLine: true,
                trailing: Row(mainAxisSize: MainAxisSize.min, children: [
                  Semantics(
                    label: '${source.name}参与搜索',
                    child: Switch(
                      value: source.enabled,
                      onChanged: saving
                          ? null
                          : (value) => _change(() =>
                              widget.library.setSourceEnabled(source, value)),
                    ),
                  ),
                  IconButton(
                    tooltip: '移除${source.name}',
                    icon: const Icon(Icons.delete_outline),
                    onPressed: saving
                        ? null
                        : () =>
                            _change(() => widget.library.removeSource(source)),
                  ),
                ]),
              )),
            FilledButton.icon(
              onPressed: saving ? null : _addSource,
              icon: const Icon(Icons.add),
              label: const Text('添加源'),
            ),
            const SizedBox(height: 16),
            const Divider(),
            Text('恢复范围', style: Theme.of(context).textTheme.titleLarge),
            const SizedBox(height: 8),
            const Text(
                '来自原 APK 的确认项：Flutter/Dart AOT 字符串与安卓 Media3 播放器接口。播放器 Android 实现、界面、收藏、历史、前台下载和 JSON 列表兼容器均为新写代码。'),
            const SizedBox(height: 8),
            const Text('不包含：未知服务端、完整原始 Dart、原本的解析/下载加密逻辑、广告与统计 SDK。'),
          ]));
}

class _InputDialog extends StatefulWidget {
  const _InputDialog(
      {required this.title,
      required this.primaryLabel,
      required this.secondaryLabel,
      required this.confirm,
      required this.help});
  final String title;
  final String primaryLabel;
  final String secondaryLabel;
  final String confirm;
  final String help;

  @override
  State<_InputDialog> createState() => _InputDialogState();
}

class _InputDialogState extends State<_InputDialog> {
  final primary = TextEditingController();
  final secondary = TextEditingController();

  @override
  void dispose() {
    primary.dispose();
    secondary.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
        scrollable: true,
        title: Text(widget.title),
        content: Column(mainAxisSize: MainAxisSize.min, children: [
          TextField(
              controller: primary,
              autocorrect: false,
              enableSuggestions: false,
              decoration: InputDecoration(labelText: widget.primaryLabel)),
          TextField(
              controller: secondary,
              autocorrect: false,
              enableSuggestions: false,
              minLines: 1,
              maxLines: 3,
              decoration: InputDecoration(labelText: widget.secondaryLabel)),
          const SizedBox(height: 12),
          Text(widget.help),
        ]),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(context), child: const Text('取消')),
          FilledButton(
            onPressed: () => Navigator.pop(context, (
              primary: primary.text.trim(),
              secondary: secondary.text.trim()
            )),
            child: Text(widget.confirm),
          ),
        ],
      );
}
