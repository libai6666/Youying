import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'browse.dart';
import 'catalog.dart';
import 'directory.dart';
import 'download_widgets.dart';
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
        builder: (_, child) => PhoneViewport(child: child!),
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

class PhoneViewport extends StatelessWidget {
  const PhoneViewport({super.key, required this.child});
  final Widget child;

  @override
  Widget build(BuildContext context) => ValueListenableBuilder<bool>(
      valueListenable: playerFullscreenViewport,
      builder: (context, fullscreen, _) =>
          LayoutBuilder(builder: (context, constraints) {
            final width = fullscreen
                ? constraints.maxWidth
                : constraints.maxWidth.clamp(0.0, 480.0);
            return ColoredBox(
              color: const Color(0xff242424),
              child: Center(
                  child: SizedBox(
                      width: width,
                      child: MediaQuery(
                          data: MediaQuery.of(context).copyWith(
                              size: Size(width, constraints.maxHeight)),
                          child: child))),
            );
          }));
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
  List<CatalogGroup> groups = [];
  String filter = '全部';
  int _generation = 0;
  String _sourceFingerprint = '';
  bool searching = false;
  String? status;
  final List<String> sourceResults = [];

  @override
  void initState() {
    super.initState();
    _sourceFingerprint = jsonEncode(
        widget.library.enabledSources.map((s) => s.toJson()).toList());
    widget.library.addListener(_sourcesChanged);
  }

  void _sourcesChanged() {
    final enabled = widget.library.enabledSources;
    final fingerprint = jsonEncode(enabled.map((s) => s.toJson()).toList());
    if (_sourceFingerprint == fingerprint) return;
    _sourceFingerprint = fingerprint;
    _generation++;
    setState(() {
      results
          .removeWhere((entry) => !enabled.any((s) => s.name == entry.source));
      groups = groupCatalog(results, query: query.text);
      searching = false;
      sourceResults.clear();
      status = '来源设置已变化，请重新搜索';
    });
  }

  @override
  void dispose() {
    _generation++;
    widget.library.removeListener(_sourcesChanged);
    if (widget.client == null) client.dispose();
    query.dispose();
    super.dispose();
  }

  Future<void> _search() async {
    if (query.text.trim().isEmpty || widget.library.enabledSources.isEmpty) {
      return;
    }
    final generation = ++_generation;
    setState(() {
      searching = true;
      results = [];
      groups = [];
      filter = '全部';
      sourceResults.clear();
      status = '正在搜索已启用的源…';
    });
    final searchQuery = query.text.trim();
    unawaited(
        _saveSearchHistory(() => widget.library.recordSearch(searchQuery)));
    final foundBySource = <String, List<MediaEntry>>{};
    var failed = 0;
    final sources = List.of(widget.library.enabledSources);
    var next = 0;
    Future<void> worker() async {
      while (mounted && generation == _generation && next < sources.length) {
        final source = sources[next++];
        String summary;
        try {
          final found = await client.search(source, searchQuery);
          foundBySource[source.name] = found;
          summary = '${source.name}：${found.length} 条';
        } catch (_) {
          failed++;
          summary = '${source.name}：请求失败或返回格式不兼容';
        }
        if (!mounted || generation != _generation) return;
        setState(() {
          results = [
            for (final source in sources) ...?foundBySource[source.name]
          ];
          groups = groupCatalog(results, query: searchQuery);
          sourceResults.add(summary);
          status =
              '已搜索 ${sourceResults.length}/${sources.length} 个来源 · ${groups.length} 部影片';
        });
      }
    }

    await Future.wait(
        List.generate(sources.length.clamp(0, 3), (_) => worker()));
    if (!mounted || generation != _generation) return;
    setState(() {
      searching = false;
      status = failed > 0
          ? '找到 ${groups.length} 部影片 · $failed 个来源暂不可用'
          : '找到 ${groups.length} 部影片';
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

  Future<void> _saveSearchHistory(Future<void> Function() action) async {
    try {
      await action();
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(const SnackBar(content: Text('搜索历史保存失败，请重试；不影响搜索')));
      }
    }
  }

  Future<void> _clearSearchHistory() async {
    final confirmed = await showDialog<bool>(
        context: context,
        builder: (context) => AlertDialog(
                title: const Text('清空搜索历史？'),
                content: const Text('仅删除搜索关键词，不影响观看记录和下载。'),
                actions: [
                  TextButton(
                      onPressed: () => Navigator.pop(context, false),
                      child: const Text('取消')),
                  TextButton(
                      onPressed: () => Navigator.pop(context, true),
                      child: const Text('清空')),
                ]));
    if (confirmed == true && mounted) {
      await _saveSearchHistory(widget.library.clearSearchHistory);
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
            labelText: '搜索影片、电视剧、动漫',
            border: const OutlineInputBorder(),
            suffixIcon: IconButton(
              tooltip: '搜索',
              icon: const Icon(Icons.search),
              onPressed: widget.library.enabledSources.isEmpty ? null : _search,
            ),
          ),
        ),
        const SizedBox(height: 12),
        AnimatedBuilder(
            animation: widget.library,
            builder: (context, _) {
              final history = widget.library.searchHistory;
              if (history.isEmpty) return const SizedBox.shrink();
              return Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(children: [
                      Expanded(
                          child: Text('搜索历史',
                              style: Theme.of(context).textTheme.titleSmall)),
                      TextButton.icon(
                          onPressed: _clearSearchHistory,
                          icon: const Icon(Icons.delete_outline, size: 18),
                          label: const Text('清空')),
                    ]),
                    Wrap(spacing: 8, runSpacing: 4, children: [
                      for (final keyword in history)
                        InputChip(
                            label: Text(keyword,
                                maxLines: 1, overflow: TextOverflow.ellipsis),
                            onPressed: () {
                              query.text = keyword;
                              unawaited(_search());
                            },
                            deleteButtonTooltipMessage: '删除搜索记录：$keyword',
                            onDeleted: () => _saveSearchHistory(
                                () => widget.library.removeSearch(keyword))),
                    ]),
                    const SizedBox(height: 12),
                  ]);
            }),
        Align(
            alignment: Alignment.centerRight,
            child: TextButton.icon(
              onPressed: _direct,
              icon: const Icon(Icons.play_circle_outline, size: 18),
              label: const Text('手动播放直链'),
            )),
        Text(status ?? '输入片名，搜索已启用的内容来源'),
        if (searching) const LinearProgressIndicator(),
        if (sourceResults.isNotEmpty)
          ExpansionTile(
              title: const Text('来源状态', style: TextStyle(fontSize: 12)),
              children: [
                for (final result in sourceResults)
                  ListTile(
                      dense: true,
                      title: Text(result, style: const TextStyle(fontSize: 12)))
              ]),
        SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Row(children: [
              for (final label in ['全部', '电影', '电视剧', '动漫', '综艺', '短剧', 'AI漫剧'])
                Padding(
                    padding: const EdgeInsets.only(right: 6),
                    child: ChoiceChip(
                        label: Text(label),
                        selected: filter == label,
                        onSelected: (_) => setState(() => filter = label)))
            ])),
        const SizedBox(height: 6),
        EntryList(
          entries: [
            for (final group in groups)
              if (filter == '全部' ||
                  catalogKind(group.primary.category) == filter)
                group.primary
          ],
          variants: {
            for (final group in groups) group.primary.id: group.entries
          },
          title: '搜索结果',
          empty: widget.library.enabledSources.isEmpty
              ? '没有启用的源，请在“设置”中启用或添加。'
              : (searching
                  ? '正在寻找匹配内容…'
                  : status == null
                      ? '输入关键词并点击搜索。'
                      : '暂无匹配内容，试试其他片名或分类。'),
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
      required this.empty,
      this.variants = const {}});
  final List<MediaEntry> entries;
  final Library library;
  final String title;
  final String empty;
  final Map<String, List<MediaEntry>> variants;

  @override
  Widget build(BuildContext context) => AnimatedBuilder(
      animation: library,
      builder: (_, __) => Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 12),
                child:
                    Text(title, style: Theme.of(context).textTheme.titleMedium),
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
                        tooltip: library.isFavorite(entry) ? '取消收藏' : '收藏',
                        icon: Icon(library.isFavorite(entry)
                            ? Icons.favorite
                            : Icons.favorite_border),
                        onPressed: () => library.toggleFavorite(entry),
                      ),
                      onTap: () => Navigator.push<void>(
                        context,
                        MaterialPageRoute(
                            builder: (_) => DetailPage(
                                entry: entry,
                                library: library,
                                variants: variants[entry.id] ?? const [])),
                      ),
                    )),
            ],
          ));
}

class DetailPage extends StatefulWidget {
  const DetailPage(
      {super.key,
      required this.entry,
      required this.library,
      this.client,
      this.variants = const []});
  final MediaEntry entry;
  final Library library;

  final CatalogClient? client;
  final List<MediaEntry> variants;

  @override
  State<DetailPage> createState() => _DetailPageState();
}

class _DetailPageState extends State<DetailPage> {
  late MediaEntry entry = widget.entry;
  MediaEntry? _playingEntry;
  MediaEntry? _sourceBeforeSwitch;
  late final CatalogClient client = widget.client ?? CatalogClient();
  Library get library => widget.library;
  bool loading = false;
  String? error;
  final Map<String, MediaEntry> _choices = {};
  int _generation = 0;
  bool findingSources = false;
  String? sourceStatus;
  Episode? _episode;
  List<Episode> _previousLine = [];
  int _position = 0;
  Episode? _initialEpisode;
  int? _initialPosition;

  @override
  void initState() {
    super.initState();
    _playingEntry = entry.playable ? entry : null;
    if (_playingEntry != null) _preparePlayback(entry);
    for (final candidate in [widget.entry, ...widget.variants]) {
      _choices[candidate.id] = candidate;
    }
    _load();
  }

  void _preparePlayback(MediaEntry next) {
    final episodes = next.lines.values.where((line) => line.isNotEmpty);
    _initialEpisode =
        _episode == null && library.lastWatchedEpisode(next) != null
            ? library.lastWatchedEpisode(next)
            : episodes.isEmpty
                ? null
                : Episode.onLine(episodes.first, _episode, _previousLine);
    final sameEpisode = _episode != null &&
        _initialEpisode != null &&
        (_initialEpisode!.name.trim() == _episode!.name.trim() ||
            (Episode.ordinal(_episode!.name) != null &&
                Episode.ordinal(_episode!.name) ==
                    Episode.ordinal(_initialEpisode!.name)));
    _initialPosition = _episode == null ? null : (sameEpisode ? _position : 0);
  }

  void _switchSource(MediaEntry next) {
    if (next.id == entry.id) return;
    _generation++;
    setState(() {
      _playingEntry ??= entry.playable ? entry : null;
      _sourceBeforeSwitch = entry;
      _preparePlayback(next);
      entry = next;
      loading = false;
      error = null;
    });
    _load();
  }

  Future<void> _findSources() async {
    if (findingSources) return;
    final identity = catalogIdentity(entry);
    final title = entry.title;
    setState(() {
      findingSources = true;
      sourceStatus = null;
    });
    final sources = List.of(library.enabledSources);
    var failed = 0;
    for (var start = 0; start < sources.length; start += 3) {
      await Future.wait(sources.skip(start).take(3).map((source) async {
        try {
          final found = await client.search(source, title);
          if (!mounted) return;
          for (final candidate in found) {
            if (catalogIdentity(candidate) == identity &&
                library.enabledSources.any((s) => s.name == candidate.source)) {
              _choices[candidate.id] = candidate;
            }
          }
        } catch (_) {
          failed++;
        }
      }));
      if (!mounted) return;
    }
    setState(() {
      findingSources = false;
      sourceStatus =
          '已找到 ${_choices.length} 个版本${failed > 0 ? '，$failed 个来源暂不可用' : ''}';
    });
  }

  Future<void> _pickSource() async {
    if (loading) return;
    final next = await showModalBottomSheet<MediaEntry>(
        context: context,
        builder: (sheet) => SafeArea(
                child: ListView(shrinkWrap: true, children: [
              for (final choice in _choices.values)
                ListTile(
                    title: Text(choice.source),
                    subtitle: Text(choice.title),
                    trailing: choice.id == entry.id
                        ? const Icon(Icons.check, color: _orange)
                        : null,
                    onTap: () => Navigator.pop(sheet, choice)),
              ListTile(
                  title: const Text('查找更多播放源'),
                  leading: const Icon(Icons.search),
                  onTap: () {
                    Navigator.pop(sheet);
                    _findSources();
                  }),
            ])));
    if (mounted && next != null) _switchSource(next);
  }

  Future<void> _showDescription() => showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      builder: (sheet) => FractionallySizedBox(
          heightFactor: 0.7,
          child: SafeArea(
              child: SingleChildScrollView(
                  padding: const EdgeInsets.all(20),
                  child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(entry.title,
                            style: Theme.of(sheet).textTheme.titleLarge),
                        const SizedBox(height: 12),
                        Text([
                          entry.year,
                          entry.area,
                          entry.category,
                          entry.remarks
                        ].where((value) => value.isNotEmpty).join(' · ')),
                        for (final (label, value) in [
                          ('演员', entry.actors),
                          ('导演', entry.director),
                          ('语言', entry.language),
                          ('时长', entry.duration)
                        ])
                          if (value.isNotEmpty) Text('$label：$value'),
                        const SizedBox(height: 16),
                        Text(entry.description.isEmpty
                            ? '暂无简介'
                            : entry.description),
                      ])))));

  Future<void> _load() async {
    final sources =
        library.enabledSources.where((source) => source.name == entry.source);
    if (entry.remoteId == null || sources.isEmpty || loading) return;
    final generation = ++_generation;
    final requested = entry;
    setState(() {
      loading = true;
      error = null;
    });
    try {
      final full = await client.detail(sources.first, requested);
      if (mounted && generation == _generation) {
        setState(() {
          _preparePlayback(full);
          entry = full;
          if (full.playable) _playingEntry = full;
          _sourceBeforeSwitch = null;
          _choices[full.id] = full;
        });
      }
    } catch (_) {
      if (mounted && generation == _generation) {
        setState(() {
          if (_sourceBeforeSwitch != null) entry = _sourceBeforeSwitch!;
          _sourceBeforeSwitch = null;
          error = '详情请求失败；已保留现有线路，可重试';
        });
      }
    } finally {
      if (mounted && generation == _generation) setState(() => loading = false);
    }
  }

  @override
  void dispose() {
    _generation++;
    if (widget.client == null) client.dispose();
    super.dispose();
  }

  Widget _pendingPlayback() => ClipRRect(
      borderRadius: BorderRadius.circular(12),
      child: AspectRatio(
          aspectRatio: 16 / 9,
          child: ColoredBox(
              color: Colors.black,
              child: Center(
                  child: Padding(
                      padding: const EdgeInsets.all(12),
                      child: Column(mainAxisSize: MainAxisSize.min, children: [
                        if (loading) ...[
                          const SizedBox(
                              width: 24,
                              height: 24,
                              child: CircularProgressIndicator(
                                  strokeWidth: 2, color: Colors.white)),
                          const SizedBox(height: 12),
                        ],
                        Text(
                            loading
                                ? '正在加载播放资源…'
                                : error != null
                                    ? '播放资源加载失败，请重试或换源'
                                    : '当前来源暂无可播放视频，请换源',
                            textAlign: TextAlign.center,
                            style: const TextStyle(
                                color: Colors.white70, fontSize: 12)),
                        if (!loading)
                          Wrap(
                              alignment: WrapAlignment.center,
                              spacing: 12,
                              children: [
                                if (entry.remoteId != null &&
                                    library.enabledSources.any((source) =>
                                        source.name == entry.source))
                                  TextButton(
                                      onPressed: _load,
                                      child: const Text('重试详情')),
                                TextButton(
                                    onPressed: _pickSource,
                                    child: const Text('换源')),
                              ]),
                      ]))))));

  @override
  Widget build(BuildContext context) {
    final playingEntry = _playingEntry ?? (entry.playable ? entry : null);
    return Scaffold(
      appBar: AppBar(
          title:
              Text(entry.title, maxLines: 1, overflow: TextOverflow.ellipsis),
          actions: [
            AnimatedBuilder(
                animation: library,
                builder: (context, _) => IconButton(
                      tooltip: library.isFavorite(entry) ? '取消收藏' : '收藏',
                      icon: Icon(
                          library.isFavorite(entry)
                              ? Icons.star
                              : Icons.star_outline,
                          color: _orange),
                      onPressed: () => library.toggleFavorite(entry),
                    )),
          ]),
      body: ListView(padding: const EdgeInsets.all(16), children: [
        KeyedSubtree(
            key: const ValueKey('detail-video'),
            child: playingEntry == null
                ? _pendingPlayback()
                : PlayerPage(
                    key: const ValueKey('detail-player'),
                    entry: playingEntry,
                    library: library,
                    embedded: true,
                    onChooseSource: loading ? null : _pickSource,
                    onShowDetails: _showDescription,
                    initial: _initialEpisode,
                    initialPositionMs: _initialPosition,
                    onPlaybackChanged: (episode, position) {
                      _episode = episode;
                      _position = position;
                      _previousLine = playingEntry.lines.values.firstWhere(
                          (line) => line.any((e) => e.url == episode.url),
                          orElse: () => []);
                    })),
        if (error != null && playingEntry != null) ...[
          Text(error!),
          TextButton(onPressed: _load, child: const Text('重试详情')),
        ],
        if (playingEntry != null || !loading) ...[
          const _SectionHeader(title: '播放来源', inset: 0),
          Wrap(spacing: 6, runSpacing: 6, children: [
            for (final candidate in _choices.values)
              ChoiceChip(
                  label: Text(candidate.source),
                  selected: candidate.id == entry.id,
                  onSelected: (_) => _switchSource(candidate)),
            ActionChip(
                label: Text(findingSources ? '正在匹配…' : '查找更多播放源'),
                onPressed: findingSources ? null : _findSources),
          ]),
          if (sourceStatus != null)
            Text(sourceStatus!,
                style: const TextStyle(fontSize: 12, color: _muted)),
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
          const SizedBox(height: 12),
          if (entry.actors.isNotEmpty) Text('主演：${entry.actors}'),
          if (entry.director.isNotEmpty) Text('导演：${entry.director}'),
          if (entry.language.isNotEmpty) Text('语言：${entry.language}'),
          if (entry.duration.isNotEmpty) Text('时长：${entry.duration}'),
          const _SectionHeader(title: '剧情简介', inset: 0),
          Text(entry.description.isEmpty ? '暂无简介' : entry.description),
          const SizedBox(height: 12),
        ],
      ]),
    );
  }
}

class LibraryPage extends StatelessWidget {
  const LibraryPage(
      {super.key, required this.library, this.showHistory = true});
  final Library library;
  final bool showHistory;

  @override
  Widget build(BuildContext context) => DownloadsView(library: library);
}

class SettingsPage extends StatefulWidget {
  const SettingsPage({super.key, required this.library});
  final Library library;

  @override
  State<SettingsPage> createState() => _SettingsPageState();
}

class _SettingsPageState extends State<SettingsPage> {
  bool saving = false;

  Future<void> _change(Future<void> Function() action,
      {String errorMessage = '源配置保存失败，请检查输入并重试'}) async {
    if (saving) return;
    setState(() => saving = true);
    try {
      await action();
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(errorMessage)),
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
            Text('播放设置', style: Theme.of(context).textTheme.titleLarge),
            SwitchListTile(
                contentPadding: EdgeInsets.zero,
                title: const Text('自动续播下一集'),
                subtitle: const Text('播放结束后等待 3 秒，继续播放当前线路的下一集'),
                value: widget.library.autoPlayNext,
                onChanged: saving
                    ? null
                    : (value) => _change(
                        () => widget.library.setAutoPlayNext(value),
                        errorMessage: '自动续播设置保存失败，请重试')),
            const SizedBox(height: 16),
            Text('下载设置', style: Theme.of(context).textTheme.titleLarge),
            ListTile(
                contentPadding: EdgeInsets.zero,
                title: const Text('下载并发数'),
                subtitle: const Text('默认 3 个，最多 10 个；按剧集任务计数'),
                trailing: DropdownButton<int>(
                  key: ValueKey(widget.library.offline.parallelism),
                  value: widget.library.offline.parallelism,
                  items: [
                    for (var count = 1; count <= 10; count++)
                      DropdownMenuItem(value: count, child: Text('$count 个'))
                  ],
                  onChanged: saving
                      ? null
                      : (value) {
                          if (value != null) {
                            _change(
                                () => widget.library.offline
                                    .setParallelism(value),
                                errorMessage: '下载并发数保存失败，请重试');
                          }
                        },
                )),
            const Text(
                '支持来源允许保存的普通文件与 AES-128 HLS 点播。DRM 需平台授权离线许可；直播暂不支持。任务与缓存保存在应用私有目录，暂停与重启后可继续。'),
            const SizedBox(height: 16),
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
                '来自原 APK 的确认项：Flutter/Dart AOT 字符串与安卓 Media3 播放器接口。播放器 Android 实现、界面、收藏、历史、Media3 离线下载和 JSON 列表兼容器均为新写代码。'),
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
