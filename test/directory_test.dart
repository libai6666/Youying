import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:shared_preferences_platform_interface/shared_preferences_async_platform_interface.dart';
import 'package:youying/catalog.dart';
import 'package:youying/directory.dart';
import 'package:youying/library.dart';

final class _NoStorage extends SharedPreferencesAsyncPlatform {
  @override
  dynamic noSuchMethod(Invocation invocation) => throw StateError('No writes');
}

class _Catalog extends CatalogClient {
  final requested = <String>[];
  bool failB = false;
  bool failA = false;
  bool failCategories = false;
  bool noCategories = false;
  int pageCount = 2;
  String revision = '';
  List<MediaEntry> Function(SourceEndpoint)? records;
  bool empty = false;
  Completer<void>? categoriesGate;
  Completer<CatalogListing>? blocked;
  @override
  Future<List<CatalogCategory>> categories(SourceEndpoint source) async {
    if (categoriesGate != null) await categoriesGate!.future;
    if (failCategories) throw const FormatException('categories failed');
    if (noCategories) return [];
    return [
      CatalogCategory(source.name == 'A' ? '1' : '90', '电影'),
      CatalogCategory(source.name == 'A' ? '6' : '91', '动作片',
          parentId: source.name == 'A' ? '1' : '90'),
      CatalogCategory(source.name == 'A' ? '7' : '92', '喜剧片',
          parentId: source.name == 'A' ? '1' : '90'),
    ];
  }

  @override
  Future<CatalogListing> browse(SourceEndpoint source,
      {String? categoryId, int page = 1}) async {
    requested.add('${source.name}:$categoryId:$page');
    if (source.name == 'A' && blocked != null) return blocked!.future;
    if (source.name == 'A' && failA) throw const FormatException('failed');
    if (source.name == 'B' && failB) throw const FormatException('failed');
    if (empty) return const CatalogListing([]);
    if (records != null) return CatalogListing(records!(source));
    return CatalogListing([
      MediaEntry(
          id: '${source.name}:$categoryId:$page$revision',
          title: '共同电影$revision',
          source: source.name,
          year: '2026',
          category: '动作片'),
    ], page: page, pageCount: pageCount);
  }
}

void main() {
  setUp(() => SharedPreferencesAsyncPlatform.instance = _NoStorage());
  const a = SourceEndpoint(name: 'A', url: 'https://a.example/api');
  const b = SourceEndpoint(name: 'B', url: 'https://b.example/api');
  late Library library;
  late _Catalog client;
  late DirectoryController directory;
  setUp(() {
    library = Library(SharedPreferencesAsync())..sources = [a, b];
    client = _Catalog();
    directory = DirectoryController(library, client: client);
  });
  tearDown(() {
    directory.dispose();
    client.dispose();
  });

  test('refresh retains cards through category and content requests', () async {
    await directory.refresh();
    final feed = directory.feedFor('电影')!;
    final previous = feed.entries.single.id;
    client.categoriesGate = Completer<void>();
    client.blocked = Completer<CatalogListing>();
    final pending = directory.refresh();
    expect(directory.feedFor('电影'), same(feed));
    expect(feed.entries.single.id, previous);
    expect(directory.supports('电影'), isTrue);
    client.categoriesGate!.complete();
    await Future<void>.delayed(Duration.zero);
    expect(feed.loading, isTrue);
    expect(feed.entries.single.id, previous);
    client.blocked!.complete(const CatalogListing([
      MediaEntry(
          id: 'new', title: '新电影', source: 'A', year: '2026', category: '动作片'),
    ]));
    await pending;
    expect(feed.loading, isFalse);
    expect(feed.rawEntries.map((e) => e.id), contains('new'));
    expect(feed.rawEntries.map((e) => e.id), isNot(contains(previous)));
  });

  test('failed refresh preserves all cards and successful retry replaces them',
      () async {
    await directory.refresh();
    final feed = directory.feedFor('电影')!;
    final previous = feed.rawEntries.map((e) => e.id).toList();
    client.failA = client.failB = true;
    client.revision = '-new';
    await directory.refresh();
    expect(feed.rawEntries.map((e) => e.id), previous);
    expect(feed.error, isNotNull);
    expect(feed.issues, hasLength(2));
    client.failA = client.failB = false;
    await directory.loadLabel('电影', retry: true);
    expect(feed.rawEntries.map((e) => e.id), ['A:6:1-new', 'B:91:1-new']);
    expect(feed.issues, isEmpty);
    expect(feed.error, isNull);
  });

  test('partial refresh replaces successful source but retains failed source',
      () async {
    await directory.refresh();
    final feed = directory.feedFor('电影')!;
    client.failB = true;
    client.revision = '-new';
    await directory.refresh();
    expect(feed.rawEntries.map((e) => e.id), ['A:6:1-new', 'B:91:1']);
    expect(feed.error, isNull);
    expect(feed.issues, hasLength(1));
  });

  test('category failure reuses the last directory without hiding cards',
      () async {
    await directory.refresh();
    final feed = directory.feedFor('电影')!;
    final previous = feed.entries.single.id;
    client.failCategories = true;
    await directory.refresh();
    expect(directory.supports('电影'), isTrue);
    expect(directory.feedFor('电影'), same(feed));
    expect(feed.entries.single.id, previous);
    expect(directory.sourceIssues, hasLength(2));
    expect(directory.categoryError, isNull);
  });

  test('authoritative empty refresh clears old cards, not on request start',
      () async {
    await directory.refresh();
    final feed = directory.feedFor('电影')!;
    client.empty = true;
    final pending = directory.refresh();
    expect(feed.entries, isNotEmpty);
    await pending;
    expect(feed.entries, isEmpty);
    expect(feed.error, isNull);
    expect(feed.hasMore, isTrue); // Other leaf categories are still available.
  });

  test('loaded pages survive revalidation until the new last page is known',
      () async {
    await directory.refresh();
    while (!client.requested.contains('A:6:2')) {
      await directory.loadLabel('电影', more: true);
    }
    final feed = directory.feedFor('电影')!;
    await directory.refresh();
    expect(feed.rawEntries.map((e) => e.id), contains('A:6:2'));
    client.pageCount = 1;
    await directory.refresh();
    expect(feed.rawEntries.map((e) => e.id), isNot(contains('A:6:2')));
  });

  test('removed categories discard their cached pages', () async {
    await directory.refresh();
    client.noCategories = true;
    await directory.refresh();
    expect(directory.supports('电影'), isFalse);
    expect(directory.feedFor('电影')!.rawEntries, isEmpty);
  });

  test('an older same-source refresh cannot replace the newer snapshot',
      () async {
    await directory.refresh();
    final feed = directory.feedFor('电影')!;
    final blocked = client.blocked = Completer<CatalogListing>();
    final old = directory.refresh();
    await Future<void>.delayed(Duration.zero);
    client.blocked = null;
    client.revision = '-latest';
    await directory.refresh();
    blocked.complete(const CatalogListing([
      MediaEntry(id: 'stale', title: '过期响应', source: 'A'),
    ]));
    await old;
    expect(directory.feedFor('电影'), same(feed));
    expect(feed.rawEntries.map((e) => e.id), ['A:6:1-latest', 'B:91:1-latest']);
    expect(feed.loading, isFalse);
  });

  test('directory uses leaf IDs from each source and groups matching work',
      () async {
    await directory.refresh();
    expect(client.requested, containsAll(['A:6:1', 'B:91:1']));
    expect(client.requested, isNot(contains('A:1:1')));
    final feed = directory.feedFor('电影')!;
    expect(feed.entries, hasLength(1));
    expect(directory.variantsFor(feed.entries.single), hasLength(2));
    expect(feed.hasMore, isTrue);
    await directory.loadLabel('电影', more: true);
    expect(client.requested, containsAll(['A:7:1', 'B:92:1']));
  });

  test('a grouped edition retains every original source version in details',
      () async {
    client.records = (source) => [
          for (final edition in source.name == 'A' ? ['国语', '粤语'] : [''])
            MediaEntry(
                id: '${source.name}:$edition',
                title: '祥赌必赢$edition',
                source: source.name,
                year: source.name == 'A' ? '2026' : '2025',
                category: '喜剧片',
                director: '罗耀辉',
                actors: '蔡卓妍,张继聪,邱士缙'),
        ];
    await directory.refresh();
    final feed = directory.feedFor('电影')!;
    expect(feed.entries, hasLength(1));
    expect(directory.variantsFor(feed.entries.single).map((e) => e.id),
        ['A:国语', 'A:粤语', 'B:']);
  });

  test(
      'one failed source does not empty the directory; retry keeps previous work',
      () async {
    client.failB = true;
    await directory.refresh();
    final feed = directory.feedFor('电影')!;
    expect(feed.entries, hasLength(1));
    expect(feed.error, isNull);
    expect(feed.issues, isNotEmpty);
    client.failB = false;
    await directory.loadLabel('电影', retry: true);
    expect(client.requested.where((r) => r == 'B:91:1').length, greaterThan(1));
    expect(feed.issues, isEmpty);
    expect(directory.variantsFor(feed.entries.single).map((e) => e.source),
        contains('B'));
  });

  test('adding or disabling a source invalidates the aggregate immediately',
      () async {
    await directory.refresh();
    library.sources = [a.withEnabled(false), b];
    library.notifyListeners();
    expect(directory.feeds, isEmpty);
    await directory.refresh();
    expect(directory.feedFor('电影')!.rawEntries.every((e) => e.source == 'B'),
        isTrue);
  });

  test('late responses cannot restore removed sources', () async {
    client.blocked = Completer<CatalogListing>();
    final old = directory.refresh();
    await Future<void>.delayed(Duration.zero);
    library.sources = [b];
    library.notifyListeners();
    await directory.refresh();
    client.blocked!.complete(const CatalogListing(
        [MediaEntry(id: 'stale', title: 'stale', source: 'A')]));
    await old;
    expect(directory.feedFor('电影')!.rawEntries.any((e) => e.source == 'A'),
        isFalse);
  });

  test('all disabled sources make no requests and have no fabricated feeds',
      () async {
    library.sources = [];
    library.notifyListeners();
    await directory.refresh();
    expect(directory.hasSources, isFalse);
    expect(directory.feeds, isEmpty);
  });

  test('exhausting pagination does not remove supported categories or results',
      () async {
    await directory.refresh();
    final feed = directory.feedFor('电影')!;
    while (feed.hasMore) {
      await directory.loadLabel('电影', more: true);
    }
    expect(directory.supports('电影'), isTrue);
    expect(feed.entries, isNotEmpty);
    expect(directory.supports('AI漫剧'), isFalse);
  });

  test(
      'a supported but empty category remains distinct from an unsupported category',
      () async {
    client.empty = true;
    await directory.refresh();
    final feed = directory.feedFor('电影')!;
    while (feed.hasMore) {
      await directory.loadLabel('电影', more: true);
    }
    expect(directory.supports('电影'), isTrue);
    expect(feed.entries, isEmpty);
    expect(directory.supports('电视直播'), isFalse);
  });

  test('category trees handle cycles and missing aggregate parents', () {
    final cyclic = directoryCategories(const [
      CatalogCategory('1', '电影', parentId: '2'),
      CatalogCategory('2', '动作片', parentId: '1'),
    ], '电影');
    expect(cyclic, hasLength(2));
    expect(
        directoryCategories(const [CatalogCategory('9', '国产剧')], '电视剧')
            .single
            .id,
        '9');
  });

  test(
      'combined facets use actual metadata and normalize area and language aliases',
      () {
    const entry = MediaEntry(
        id: 'A:1',
        title: '影片',
        source: 'A',
        category: '动作片',
        genres: '冒险,科幻',
        area: '中国大陆/中国香港',
        language: '汉语普通话,粤语',
        year: '2026年');
    const filter =
        CatalogFilters(genre: '动作', area: '大陆', language: '国语', year: '2026');
    expect(filter.matches(entry), isTrue);
    expect(filter.copyWith(genre: '冒险').matches(entry), isTrue);
    expect(filter.copyWith(area: '美国').matches(entry), isFalse);
    expect(filter.copyWith(language: '英语').matches(entry), isFalse);
    expect(filter.copyWith(year: '2025').matches(entry), isFalse);
    expect(
        filter.matches(const MediaEntry(id: 'empty', title: '未知', source: 'A')),
        isFalse);
  });

  test('genre normalization preserves comedy and musical drama suffixes', () {
    const series = MediaEntry(
        id: 'tv-comedy',
        title: '喜剧电视剧',
        source: 'A',
        category: '国产剧',
        genres: '喜剧,音乐剧',
        year: '2026');
    const movie = MediaEntry(
        id: 'movie-comedy',
        title: '喜剧电影',
        source: 'A',
        category: '喜剧片',
        year: '2026');
    expect(catalogGenres(series), containsAll(['喜剧', '音乐剧']));
    expect(
        const CatalogFilters(genre: '喜剧').apply(groupCatalog([series, movie])),
        [series, movie]);
    expect(const CatalogFilters(genre: '音乐剧').matches(series), isTrue);
  });

  test(
      'filtering considers matching variants without changing unfiltered groups',
      () {
    final groups = [
      CatalogGroup([
        const MediaEntry(id: 'A:1', title: '影片', source: 'A'),
        const MediaEntry(
            id: 'B:1', title: '影片', source: 'B', genres: '动作', area: '美国'),
      ])
    ];
    final filtered =
        const CatalogFilters(genre: '动作', area: '美国').apply(groups);
    expect(filtered.single.source, 'B');
    expect(groups.single.entries, hasLength(2));
    expect(const CatalogFilters().apply(groups).single.source, 'A');
  });

  test(
      'sorts use available metrics across variants and preserve stable ties and unknowns',
      () {
    final groups = [
      CatalogGroup([
        const MediaEntry(
            id: 'old',
            title: '旧',
            source: 'A',
            popularity: 2,
            rating: 8,
            updatedAtMs: 100)
      ]),
      CatalogGroup([
        const MediaEntry(
            id: 'new',
            title: '新',
            source: 'A',
            popularity: 9,
            rating: 6,
            updatedAtMs: 200)
      ]),
      CatalogGroup([const MediaEntry(id: 'unknown', title: '未知', source: 'A')]),
      CatalogGroup([
        const MediaEntry(id: 'variant', title: '多版本', source: 'A'),
        const MediaEntry(
            id: 'variantB',
            title: '多版本',
            source: 'B',
            popularity: 20,
            rating: 9,
            updatedAtMs: 300)
      ]),
      CatalogGroup([
        const MediaEntry(
            id: 'unknown2', title: '未知2', source: 'A', popularity: 0)
      ]),
    ];
    expect(const CatalogFilters().apply(groups).map((e) => e.id),
        ['variant', 'new', 'old', 'unknown', 'unknown2']);
    expect(
        const CatalogFilters(order: CatalogOrder.popular)
            .apply(groups)
            .map((e) => e.id),
        ['variant', 'new', 'old', 'unknown', 'unknown2']);
    expect(
        const CatalogFilters(order: CatalogOrder.rating)
            .apply(groups)
            .map((e) => e.id),
        ['variant', 'old', 'new', 'unknown', 'unknown2']);
    expect(groups.first.primary.id, 'old');
  });

  test(
      'filter remains applied when additional pages arrive without hiding homepage entries',
      () async {
    await directory.refresh();
    const filters = CatalogFilters(genre: '喜剧');
    expect(filters.apply(directory.feedFor('电影')!.groups), isEmpty);
    final original = directory.feedFor('电影')!.entries.length;
    await directory.loadLabel('电影', more: true);
    expect(filters.apply(directory.feedFor('电影')!.groups), isEmpty);
    expect(directory.feedFor('电影')!.entries.length,
        greaterThanOrEqualTo(original));
    expect(directory.variantsFor(directory.feedFor('电影')!.entries.first).length,
        greaterThanOrEqualTo(2));
  });

  test('search grouping retains remakes, seasons and unknown-year records', () {
    MediaEntry entry(String id, String title, String year, String category) =>
        MediaEntry(
            id: id, title: title, source: id, year: year, category: category);
    final groups = groupCatalog([
      entry('1', '某剧 第二季', '2026', '国产剧'),
      entry('2', '某剧', '2026', '国产剧'),
      entry('3', '某剧', '2026', '电视剧'),
      entry('4', '某剧', '2020', '国产剧'),
      entry('5', '某剧', '', '国产剧'),
      entry('6', '某剧', '', '国产剧'),
      entry('7', '某剧', '2026', '剧情片'),
    ], query: '某剧');
    expect(groups, hasLength(6));
    expect(groups.first.entries.map((e) => e.id), ['2', '3']);
    expect(groups.last.primary.title, '某剧 第二季');
  });
}
