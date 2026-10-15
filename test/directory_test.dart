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
  Completer<CatalogListing>? blocked;
  @override
  Future<List<CatalogCategory>> categories(SourceEndpoint source) async => [
        CatalogCategory(source.name == 'A' ? '1' : '90', '电影'),
        CatalogCategory(source.name == 'A' ? '6' : '91', '动作片',
            parentId: source.name == 'A' ? '1' : '90'),
        CatalogCategory(source.name == 'A' ? '7' : '92', '喜剧片',
            parentId: source.name == 'A' ? '1' : '90'),
      ];
  @override
  Future<CatalogListing> browse(SourceEndpoint source,
      {String? categoryId, int page = 1}) async {
    requested.add('${source.name}:$categoryId:$page');
    if (source.name == 'A' && blocked != null) return blocked!.future;
    if (source.name == 'B' && failB) throw const FormatException('failed');
    return CatalogListing([
      MediaEntry(
          id: '${source.name}:$categoryId:$page',
          title: '共同电影',
          source: source.name,
          year: '2026',
          category: '动作片'),
    ], page: page, pageCount: 2);
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
