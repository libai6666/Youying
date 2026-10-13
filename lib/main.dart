import 'dart:convert';

import 'package:flutter/material.dart';

import 'catalog.dart';
import 'library.dart';
import 'player.dart';

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
        theme: ThemeData(
          colorScheme: ColorScheme.fromSeed(seedColor: const Color(0xfff38b1c)),
          useMaterial3: true,
        ),
        home: FutureBuilder<Library>(
          future: library,
          builder: (context, snapshot) {
            if (snapshot.hasError) {
              return const Scaffold(body: Center(child: Text('无法读取本地数据')));
            }
            if (!snapshot.hasData) {
              return const Scaffold(body: Center(child: CircularProgressIndicator()));
            }
            return HomePage(library: snapshot.requireData);
          },
        ),
      );
}

class HomePage extends StatefulWidget {
  const HomePage({super.key, required this.library});
  final Library library;

  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> {
  int selected = 0;

  @override
  Widget build(BuildContext context) => AnimatedBuilder(
        animation: widget.library,
        builder: (context, _) => Scaffold(
          appBar: AppBar(title: Row(children: [
            Image.asset('assets/logo.png', width: 34, height: 34),
            const SizedBox(width: 10),
            const Expanded(child: Text('柚影')),
          ])),
          body: IndexedStack(index: selected, children: [
            SearchPage(library: widget.library),
            EntryList(
              title: '收藏',
              entries: widget.library.favorites.values.toList(),
              library: widget.library,
              empty: '暂时没有收藏。请先添加你信任的源，或播放手动输入的地址。',
            ),
            LibraryPage(library: widget.library),
            SettingsPage(library: widget.library),
          ]),
          bottomNavigationBar: NavigationBar(
            selectedIndex: selected,
            onDestinationSelected: (index) => setState(() => selected = index),
            destinations: const [
              NavigationDestination(icon: Icon(Icons.search), label: '搜索'),
              NavigationDestination(icon: Icon(Icons.favorite_border), label: '收藏'),
              NavigationDestination(icon: Icon(Icons.history), label: '历史/本地'),
              NavigationDestination(icon: Icon(Icons.tune), label: '设置'),
            ],
          ),
        ),
      );
}

class SearchPage extends StatefulWidget {
  const SearchPage({super.key, required this.library});
  final Library library;

  @override
  State<SearchPage> createState() => _SearchPageState();
}

class _SearchPageState extends State<SearchPage> {
  final TextEditingController query = TextEditingController();
  final CatalogClient client = CatalogClient();
  List<MediaEntry> results = [];
  bool searching = false;
  String status = '没有内置或确认的影视源；手动添加后才能搜索。';

  @override
  void dispose() {
    client.dispose();
    query.dispose();
    super.dispose();
  }

  Future<void> _search() async {
    if (searching || query.text.trim().isEmpty || widget.library.sources.isEmpty) return;
    setState(() {
      searching = true;
      results = [];
      status = '仅访问你手动添加的源…';
    });
    final all = <MediaEntry>[];
    var failed = 0;
    for (final source in List<SourceEndpoint>.of(widget.library.sources)) {
      try {
        all.addAll(await client.search(source, query.text));
      } catch (_) {
        failed++;
      }
      if (!mounted) return;
    }
    setState(() {
      results = all;
      searching = false;
      status = failed > 0
          ? '找到 ${all.length} 条；$failed 个源未返回受支持的 JSON（或连接失败）。'
          : '找到 ${all.length} 条。这些数据来自你手动配置的源，并非已恢复的原应用源。';
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
        lines: {'直链': [Episode(name: '播放', url: url)]},
      );
      await Navigator.push<void>(
        context,
        MaterialPageRoute(builder: (_) => PlayerPage(entry: entry,
          library: widget.library, headers: headers)),
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
  Widget build(BuildContext context) => ListView(padding: const EdgeInsets.all(16), children: [
        Card.filled(child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            const Text('恢复状态：部分', style: TextStyle(fontWeight: FontWeight.bold)),
            const SizedBox(height: 8),
            const Text('已恢复播放器参数与部分资源；影视源、服务端接口和原 Dart 业务逻辑未确认。本工程的界面及目录适配器是独立重写。'),
            TextButton.icon(
              onPressed: _direct,
              icon: const Icon(Icons.play_circle_outline),
              label: const Text('手动播放直链'),
            ),
          ]),
        )),
        const SizedBox(height: 14),
        TextField(
          controller: query,
          onSubmitted: (_) => _search(),
          textInputAction: TextInputAction.search,
          decoration: InputDecoration(
            labelText: '从手动配置的源中搜索',
            border: const OutlineInputBorder(),
            suffixIcon: IconButton(
              tooltip: '搜索',
              icon: const Icon(Icons.search),
              onPressed: widget.library.sources.isEmpty || searching ? null : _search,
            ),
          ),
        ),
        const SizedBox(height: 12),
        Text(status),
        if (searching) const LinearProgressIndicator(),
        const SizedBox(height: 6),
        EntryList(
          entries: results,
          title: '搜索结果',
          empty: widget.library.sources.isEmpty ? '请在“设置”中添加你信任的 HTTPS JSON 源。' : '输入关键词并点击搜索。',
          library: widget.library,
        ),
      ]);
}

class EntryList extends StatelessWidget {
  const EntryList({super.key, required this.entries, required this.library, required this.title, required this.empty});
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
          if (entries.isEmpty) Padding(
            padding: const EdgeInsets.all(16),
            child: Text(empty),
          ),
          for (final entry in entries)
            Card(child: ListTile(
              leading: CircleAvatar(child: Text(entry.title.characters.first)),
              title: Text(entry.title, maxLines: 2),
              subtitle: Text('${entry.source} · ${entry.playable ? "可选择线路" : "无可用播放地址"}'),
              trailing: IconButton(
                tooltip: library.favorites.containsKey(entry.id) ? '取消收藏' : '收藏',
                icon: Icon(library.favorites.containsKey(entry.id) ? Icons.favorite : Icons.favorite_border),
                onPressed: () => library.toggleFavorite(entry),
              ),
              onTap: () => Navigator.push<void>(
                context,
                MaterialPageRoute(builder: (_) => DetailPage(entry: entry, library: library)),
              ),
            )),
        ],
      );
}

class DetailPage extends StatelessWidget {
  const DetailPage({super.key, required this.entry, required this.library});
  final MediaEntry entry;
  final Library library;

  @override
  Widget build(BuildContext context) => Scaffold(
        appBar: AppBar(title: Text(entry.title)),
        body: ListView(padding: const EdgeInsets.all(16), children: [
          Text(entry.source, style: Theme.of(context).textTheme.labelMedium),
          const SizedBox(height: 12),
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
                    MaterialPageRoute(builder: (_) => PlayerPage(
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
  const LibraryPage({super.key, required this.library});
  final Library library;

  @override
  Widget build(BuildContext context) => ListView(padding: const EdgeInsets.all(16), children: [
        const Text('下载仅支持前台直链 MP4/WebM；不是 APK 原有的后台 curl_task 功能。'),
        const SizedBox(height: 12),
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
              if (episode.url == parts[1]) return '${entry.title} · ${episode.name}';
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
  Future<void> _addSource() async {
    final submitted = await showDialog<({String primary, String secondary})>(
      context: context,
      builder: (_) => const _InputDialog(
        title: '添加你信任的源',
        primaryLabel: '名称',
        secondaryLabel: 'HTTPS JSON 接口',
        confirm: '保存',
        help: '兼容常见 JSON 列表格式；并非原 APK 已证实的 API。只在你点击搜索后请求。',
      ),
    );
    if (submitted == null || !mounted) return;
    try {
      await widget.library.addSource(SourceEndpoint(
        name: submitted.primary, url: submitted.secondary));
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('名称不能为空，接口必须是有效的 HTTPS URL')),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) => ListView(padding: const EdgeInsets.all(16), children: [
        Text('源配置', style: Theme.of(context).textTheme.titleLarge),
        const Text('默认源数量：0。没有验证到原 APK 的影视源或解析接口；不会预置广告/统计地址。'),
        const SizedBox(height: 12),
        for (final source in widget.library.sources)
          Card(child: ListTile(
            title: Text(source.name),
            subtitle: const Text('用户手动配置；仅在点击搜索后请求'),
            trailing: IconButton(
              tooltip: '移除',
              icon: const Icon(Icons.delete_outline),
              onPressed: () => widget.library.removeSource(source),
            ),
          )),
        FilledButton.icon(
          onPressed: _addSource,
          icon: const Icon(Icons.add),
          label: const Text('添加源'),
        ),
        const SizedBox(height: 16),
        const Divider(),
        Text('恢复范围', style: Theme.of(context).textTheme.titleLarge),
        const SizedBox(height: 8),
        const Text('来自原 APK 的确认项：Flutter/Dart AOT 字符串与安卓 Media3 播放器接口。播放器 Android 实现、界面、收藏、历史、前台下载和 JSON 列表兼容器均为新写代码。'),
        const SizedBox(height: 8),
        const Text('不包含：未知服务端、完整原始 Dart、原本的解析/下载加密逻辑、广告与统计 SDK。'),
      ]);
}

class _InputDialog extends StatefulWidget {
  const _InputDialog({required this.title, required this.primaryLabel,
    required this.secondaryLabel, required this.confirm, required this.help});
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
      TextField(controller: primary, autocorrect: false, enableSuggestions: false,
        decoration: InputDecoration(labelText: widget.primaryLabel)),
      TextField(controller: secondary, autocorrect: false, enableSuggestions: false,
        minLines: 1, maxLines: 3,
        decoration: InputDecoration(labelText: widget.secondaryLabel)),
      const SizedBox(height: 12),
      Text(widget.help),
    ]),
    actions: [
      TextButton(onPressed: () => Navigator.pop(context), child: const Text('取消')),
      FilledButton(
        onPressed: () => Navigator.pop(context,
          (primary: primary.text.trim(), secondary: secondary.text.trim())),
        child: Text(widget.confirm),
      ),
    ],
  );
}
