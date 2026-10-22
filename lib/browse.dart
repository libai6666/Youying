import 'dart:convert';

import 'package:flutter/foundation.dart';

import 'catalog.dart';
import 'library.dart';

const browseTabs = ['首页', '综艺', 'AI短剧', '电影', '电视剧', '二次元动漫', '热门短剧', '电视直播'];
const rankingTabs = ['电视剧', '电影', '动漫', '综艺', '短剧'];

class BrowseFeed {
  CatalogListing? listing;
  bool loading = false;
  String? error;
}

class BrowseController extends ChangeNotifier {
  BrowseController(this.library, {CatalogClient? client})
      : client = client ?? CatalogClient(),
        _ownsClient = client == null {
    library.addListener(_sourcesChanged);
    _sourcesChanged();
  }

  final Library library;
  final CatalogClient client;
  final bool _ownsClient;
  SourceEndpoint? source;
  List<CatalogCategory> categories = [];
  final Map<String, BrowseFeed> feeds = {};
  String? categoryError;
  bool loadingCategories = false;
  String _fingerprint = '';
  int _generation = 0;
  bool _disposed = false;
  final Set<String> _requestedLabels = {'电视剧', '综艺', '动漫'};

  void _sourcesChanged() {
    final enabled = library.enabledSources;
    final fingerprint = jsonEncode(enabled.map((s) => s.toJson()).toList());
    if (_fingerprint == fingerprint) return;
    _fingerprint = fingerprint;
    if (source != null &&
        enabled.any((s) => s.name == source!.name && s.url == source!.url)) {
      return;
    }
    source = enabled.isEmpty ? null : enabled.first;
    refresh();
  }

  Future<void> selectSource(SourceEndpoint selected) async {
    if (!library.enabledSources
        .any((s) => s.name == selected.name && s.url == selected.url)) {
      return;
    }
    source = selected;
    await refresh();
  }

  CatalogCategory? categoryFor(String label) {
    final aliases = switch (label) {
      '电视剧' => ['电视剧', '连续剧'],
      '热门短剧' || '短剧' => ['短剧', '爽文短剧'],
      '二次元动漫' || '动漫' => ['动漫', '动画'],
      _ => [label],
    };
    for (final rootOnly in [true, false]) {
      for (final category in categories) {
        if ((!rootOnly || category.parentId == '0') &&
            aliases.contains(category.name)) {
          return category;
        }
      }
    }
    return null;
  }

  BrowseFeed? feedFor(String label) =>
      feeds[label == '首页' ? '' : categoryFor(label)?.id];

  Future<void> refresh() async {
    final generation = ++_generation;
    feeds.clear();
    categories = [];
    categoryError = null;
    final current = source;
    loadingCategories = current != null;
    notifyListeners();
    if (current == null) return;
    final latest = load('');
    try {
      final result = await client.categories(current);
      if (!_active(generation)) return;
      categories = result;
    } catch (_) {
      if (!_active(generation)) return;
      categoryError = '分类加载失败，请重试或切换源';
    } finally {
      if (_active(generation)) {
        loadingCategories = false;
        notifyListeners();
      }
    }
    await latest;
    if (!_active(generation)) return;
    await Future.wait([
      for (final label in _requestedLabels.toList())
        if (categoryFor(label) case final category?) load(category.id),
    ]);
  }

  Future<void> ensureLabel(String label) async {
    _requestedLabels.add(label);
    if (label == '首页') return load('');
    final category = categoryFor(label);
    if (category != null) await load(category.id);
  }

  Future<void> load(String id, {bool more = false, bool retry = false}) async {
    final current = source;
    if (current == null) return;
    final feed = feeds.putIfAbsent(id, BrowseFeed.new);
    if (feed.loading ||
        (!retry && !more && feed.listing != null) ||
        (more && feed.listing?.hasMore != true)) {
      return;
    }
    final generation = _generation;
    final old = feed.listing;
    final page = more ? old!.page + 1 : 1;
    feed.loading = true;
    feed.error = null;
    notifyListeners();
    try {
      final result = await client.browse(current, categoryId: id, page: page);
      if (!_active(generation)) return;
      final entries = more ? [...old!.entries] : <MediaEntry>[];
      final ids = entries.map((e) => e.id).toSet();
      for (final entry in result.entries) {
        if (ids.add(entry.id)) entries.add(entry);
      }
      feed.listing = CatalogListing(entries,
          page: result.page,
          pageCount: result.entries.isEmpty ? result.page : result.pageCount);
    } catch (_) {
      if (!_active(generation)) return;
      feed.error = '内容加载失败，请重试或切换源';
    } finally {
      if (_active(generation)) {
        feed.loading = false;
        notifyListeners();
      }
    }
  }

  bool _active(int generation) => !_disposed && generation == _generation;

  @override
  void dispose() {
    _disposed = true;
    _generation++;
    library.removeListener(_sourcesChanged);
    if (_ownsClient) client.dispose();
    super.dispose();
  }
}
