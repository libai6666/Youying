import 'dart:convert';

import 'package:flutter/foundation.dart';

import 'catalog.dart';
import 'library.dart';

enum CatalogOrder { latest, popular, rating }

class CatalogFilters {
  const CatalogFilters(
      {this.genre = '',
      this.area = '',
      this.language = '',
      this.year = '',
      this.order = CatalogOrder.latest});
  final String genre;
  final String area;
  final String language;
  final String year;
  final CatalogOrder order;

  CatalogFilters copyWith(
          {String? genre,
          String? area,
          String? language,
          String? year,
          CatalogOrder? order}) =>
      CatalogFilters(
          genre: genre ?? this.genre,
          area: area ?? this.area,
          language: language ?? this.language,
          year: year ?? this.year,
          order: order ?? this.order);

  bool matches(MediaEntry entry) =>
      (genre.isEmpty || catalogGenres(entry).contains(genre)) &&
      (area.isEmpty || catalogTokens(entry.area, area: true).contains(area)) &&
      (language.isEmpty || catalogTokens(entry.language).contains(language)) &&
      (year.isEmpty || catalogYear(entry.year) == year);

  List<MediaEntry> apply(List<CatalogGroup> groups) {
    num? value(MediaEntry entry) => switch (order) {
          CatalogOrder.latest => entry.updatedAtMs,
          CatalogOrder.popular =>
            (entry.popularity ?? 0) > 0 ? entry.popularity : null,
          CatalogOrder.rating => entry.rating,
        };
    final matches = <MediaEntry>[];
    final values = <String, num?>{};
    for (final group in groups) {
      final eligible = group.entries.where(this.matches).toList();
      if (eligible.isEmpty) continue;
      final primary = CatalogGroup(eligible).primary;
      matches.add(primary);
      final known = eligible.map(value).whereType<num>().toList();
      values[primary.id] =
          known.isEmpty ? null : known.reduce((a, b) => a > b ? a : b);
    }
    final index = {for (var i = 0; i < matches.length; i++) matches[i].id: i};
    matches.sort((a, b) {
      final x = values[a.id], y = values[b.id];
      final compared = x == null
          ? (y == null ? 0 : 1)
          : y == null
              ? -1
              : y.compareTo(x);
      return compared == 0 ? index[a.id]!.compareTo(index[b.id]!) : compared;
    });
    return matches;
  }
}

String catalogYear(String value) =>
    RegExp(r'^\d{4}').firstMatch(value.trim())?.group(0) ?? '';

List<String> catalogTokens(String value, {bool area = false}) => value
    .split(RegExp(r'[,，、/|;；\s]+'))
    .where((s) => s.isNotEmpty)
    .map((s) => area
        ? switch (s) {
            '中国大陆' || '内地' || '大陆' => '大陆',
            '中国香港' || '香港' => '香港',
            '中国台湾' || '台湾' => '台湾',
            _ => s,
          }
        : switch (s) {
            '汉语普通话' || '普通话' || '国语' => '国语',
            _ => s,
          })
    .toList();

List<String> catalogGenres(MediaEntry entry) =>
    catalogTokens('${entry.genres},${entry.category}')
        .map((s) => s.replaceFirst(RegExp(r'片$'), ''))
        .toList();

List<String> catalogGenreOptions(String label) =>
    switch (directoryLabel(label)) {
      '电影' => [
          '喜剧',
          '爱情',
          '恐怖',
          '动作',
          '科幻',
          '剧情',
          '战争',
          '悬疑',
          '犯罪',
          '动画',
          '纪录'
        ],
      '电视剧' || '短剧' => [
          '古装',
          '爱情',
          '都市',
          '悬疑',
          '剧情',
          '家庭',
          '喜剧',
          '战争',
          '犯罪',
          '武侠'
        ],
      '动漫' || 'AI漫剧' => ['玄幻', '奇幻', '冒险', '动作', '搞笑', '恋爱', '校园', '热血', '动画'],
      '综艺' => ['真人秀', '音乐', '脱口秀', '喜剧', '舞蹈', '访谈', '生活'],
      _ => [],
    };

class DirectoryFeed {
  final List<MediaEntry> rawEntries = [];
  List<CatalogGroup> groups = [];
  bool loading = false;
  bool hasMore = false;
  bool loaded = false;
  final Map<String, String> issues = {};
  String? error;
  List<MediaEntry> get entries => groups.map((g) => g.primary).toList();
}

class _Partition {
  _Partition(this.source, this.categoryId);
  final SourceEndpoint source;
  final String categoryId;
  int page = 0;
  bool hasMore = true;
}

String directoryLabel(String label) => switch (label) {
      '二次元动漫' => '动漫',
      '热门短剧' => '短剧',
      _ => label,
    };

List<CatalogCategory> directoryCategories(
    List<CatalogCategory> categories, String label) {
  label = directoryLabel(label);
  final roots = categories.where((c) =>
      c.name == label ||
      (label == '电视剧' && c.name == '连续剧') ||
      (label == '短剧' && c.name == '爽文短剧') ||
      (label == '动漫' && c.name == '动画'));
  final included = <String, CatalogCategory>{};
  void include(CatalogCategory category) {
    if (included.containsKey(category.id)) return;
    included[category.id] = category;
    for (final child in categories.where((c) => c.parentId == category.id)) {
      include(child);
    }
  }

  if (roots.isEmpty) {
    for (final category in categories) {
      if (catalogKind(category.name) == label) include(category);
    }
  } else {
    for (final root in roots) {
      include(root);
    }
  }
  // CMS parent categories often contain no entries; leaf IDs are queried first.
  final parentIds = categories.map((c) => c.parentId).toSet();
  return [
    ...included.values.where((c) => !parentIds.contains(c.id)),
    ...included.values.where((c) => parentIds.contains(c.id)),
  ];
}

class DirectoryController extends ChangeNotifier {
  DirectoryController(this.library, {CatalogClient? client})
      : client = client ?? CatalogClient(),
        _ownsClient = client == null {
    library.addListener(_sourcesChanged);
    _sourcesChanged();
  }
  final Library library;
  final CatalogClient client;
  final bool _ownsClient;
  final Map<String, DirectoryFeed> feeds = {};
  final Map<String, List<CatalogCategory>> _categories = {};
  final Map<String, List<_Partition>> _queues = {};
  final Map<String, String> sourceIssues = {};
  final Set<String> _requested = {'电影', '电视剧', '综艺', '动漫'};
  bool loadingCategories = false;
  bool _disposed = false;
  int _generation = 0;
  String _fingerprint = '';
  List<SourceEndpoint> _sources = [];

  bool get hasSources => _sources.isNotEmpty;
  String? get categoryError =>
      !loadingCategories && hasSources && _categories.isEmpty
          ? '内容目录暂时不可用，请重试或检查源设置'
          : null;

  void _sourcesChanged() {
    final fingerprint =
        jsonEncode(library.enabledSources.map((s) => s.toJson()).toList());
    if (fingerprint == _fingerprint) return;
    _fingerprint = fingerprint;
    refresh();
  }

  bool _active(int generation) => !_disposed && generation == _generation;

  Future<void> _parallel<T>(
      List<T> work, Future<void> Function(T) action) async {
    var next = 0;
    final generation = _generation;
    Future<void> worker() async {
      while (_active(generation) && next < work.length) {
        final item = work[next++];
        await action(item);
      }
    }

    await Future.wait(List.generate(work.length.clamp(0, 3), (_) => worker()));
  }

  Future<void> refresh() async {
    final generation = ++_generation;
    _sources = List.of(library.enabledSources);
    _categories.clear();
    _queues.clear();
    sourceIssues.clear();
    feeds.clear();
    loadingCategories = hasSources;
    notifyListeners();
    await _parallel(_sources, (source) async {
      try {
        final result = await client.categories(source);
        if (!_active(generation)) return;
        _categories[source.url] = result;
      } catch (_) {
        if (_active(generation)) sourceIssues[source.name] = '分类请求失败';
      }
    });
    if (!_active(generation)) return;
    loadingCategories = false;
    notifyListeners();
    // Labels are loaded sequentially to bound network concurrency on phones.
    for (final label in _requested.toList()) {
      if (!_active(generation)) return;
      await loadLabel(label);
    }
  }

  List<_Partition> _partitions(String label) => _queues.putIfAbsent(label, () {
        final perSource = [
          for (final source in _sources)
            directoryCategories(_categories[source.url] ?? [], label)
                .map((c) => _Partition(source, c.id))
                .toList()
        ];
        return [
          for (var index = 0;
              perSource.any((items) => index < items.length);
              index++)
            for (final items in perSource)
              if (index < items.length) items[index],
        ];
      });

  bool supports(String label) =>
      !loadingCategories &&
      _sources.any((source) => directoryCategories(
              _categories[source.url] ?? [], directoryLabel(label))
          .isNotEmpty);
  DirectoryFeed? feedFor(String label) => feeds[directoryLabel(label)];

  Future<void> ensureLabel(String label) async {
    label = directoryLabel(label);
    if (label == '首页') return;
    _requested.add(label);
    if (!loadingCategories) await loadLabel(label);
  }

  Future<void> loadLabel(String label,
      {bool more = false, bool retry = false}) async {
    label = directoryLabel(label);
    if (loadingCategories || !hasSources || _disposed) return;
    final feed = feeds.putIfAbsent(label, DirectoryFeed.new);
    if (feed.loading ||
        (feed.loaded && !more && !retry) ||
        (more && !feed.hasMore && !retry)) {
      return;
    }
    final generation = _generation;
    final queue = _partitions(label);
    if (retry) {
      final failed = queue
          .where((p) =>
              feed.issues.containsKey('${p.source.name}:${p.categoryId}'))
          .toList();
      queue.removeWhere(failed.contains);
      queue.insertAll(0, failed);
    }
    final batch = queue.take(_sources.length).toList();
    if (batch.isEmpty) {
      if (retry && sourceIssues.isNotEmpty) {
        await refresh();
        return;
      }
      feed.loaded = true;
      feed.hasMore = false;
      feed.error = sourceIssues.isEmpty ? null : '分类目录暂不可用，请刷新或查看来源状态';
      notifyListeners();
      return;
    }
    queue.removeRange(0, batch.length);
    feed.loading = true;
    feed.error = null;
    notifyListeners();
    final results = <_Partition, CatalogListing>{};
    final failed = <_Partition>{};
    await _parallel(batch, (partition) async {
      try {
        results[partition] = await client.browse(partition.source,
            categoryId: partition.categoryId, page: partition.page + 1);
      } catch (_) {
        failed.add(partition);
      }
    });
    if (!_active(generation)) return;
    final ids = feed.rawEntries.map((entry) => entry.id).toSet();
    for (final partition in batch) {
      final key = '${partition.source.name}:${partition.categoryId}';
      final listing = results[partition];
      if (listing == null) {
        feed.issues[key] = '内容请求失败，可重试';
      } else {
        partition.page = listing.page;
        partition.hasMore = listing.hasMore;
        feed.issues.remove(key);
        for (final entry in listing.entries) {
          if (ids.add(entry.id)) feed.rawEntries.add(entry);
        }
      }
      if (partition.hasMore) queue.add(partition);
    }
    feed.groups = groupCatalog(feed.rawEntries);
    feed.loaded = true;
    feed.hasMore = queue.isNotEmpty;
    feed.error = failed.length == batch.length ? '本批内容加载失败，请重试' : null;
    feed.loading = false;
    notifyListeners();
  }

  List<MediaEntry> variantsFor(MediaEntry entry) {
    final identity = catalogIdentity(entry);
    final matches = <String, MediaEntry>{entry.id: entry};
    for (final feed in feeds.values) {
      for (final candidate in feed.rawEntries) {
        if (catalogIdentity(candidate) == identity) {
          matches[candidate.id] = candidate;
        }
      }
    }
    return matches.values.toList();
  }

  @override
  void dispose() {
    _disposed = true;
    _generation++;
    library.removeListener(_sourcesChanged);
    if (_ownsClient) client.dispose();
    super.dispose();
  }
}
