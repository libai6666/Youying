import 'dart:async';
import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:shared_preferences_platform_interface/shared_preferences_async_platform_interface.dart';
import 'package:youying/browse.dart';
import 'package:youying/catalog.dart';
import 'package:youying/library.dart';

final class _NoStorage extends SharedPreferencesAsyncPlatform {
  @override
  dynamic noSuchMethod(Invocation invocation) =>
      throw StateError('Unexpected storage');
}

class _FakeCatalog extends CatalogClient {
  final List<String> requested = [];
  Completer<CatalogListing>? blocked;
  bool fail = false;
  @override
  Future<List<CatalogCategory>> categories(SourceEndpoint source) async => [
        const CatalogCategory('10', '连续剧'),
        const CatalogCategory('20', '电影'),
        const CatalogCategory('30', '爽文短剧'),
        const CatalogCategory('40', '动漫'),
      ];
  @override
  Future<CatalogListing> browse(SourceEndpoint source,
      {String? categoryId, int page = 1}) async {
    requested.add('${source.name}:$categoryId:$page');
    if (source.name == 'old' && blocked != null) return blocked!.future;
    if (fail) throw const FormatException('failed');
    return CatalogListing([
      MediaEntry(id: '${source.name}:1', title: 'One', source: source.name),
      if (page > 1)
        MediaEntry(id: '${source.name}:2', title: 'Two', source: source.name),
    ], page: page, pageCount: 2);
  }
}

void main() {
  setUp(() => SharedPreferencesAsyncPlatform.instance = _NoStorage());
  const source = SourceEndpoint(
      name: 'test',
      url: 'https://example.com/api?wd=old&t=old&pg=9&ids=1&token=test');

  test(
      'catalog categories and paging use explicit parameters and preserve nonrouting query',
      () async {
    final requests = <Uri>[];
    final client = CatalogClient(client: MockClient((request) async {
      requests.add(request.url);
      expect(request.followRedirects, false);
      return http.Response(
          jsonEncode({
            'class': [
              {'type_id': 10, 'type_name': '连续剧', 'type_pid': 0}
            ],
            'list': [
              {
                'vod_id': 1,
                'vod_name': 'Title',
                'vod_content': '<p>Hello&nbsp;world</p>',
                'type_id': 10,
                'type_name': '连续剧',
                'vod_year': 2026,
                'vod_area': '中国大陆',
                'vod_actor': '甲,乙',
                'vod_remarks': '更新至2集'
              }
            ],
            'pagecount': '5',
          }),
          200,
          headers: {'content-type': 'application/json; charset=utf-8'});
    }));
    addTearDown(client.dispose);
    final categories = await client.categories(source);
    expect(categories.single.name, '连续剧');
    expect(categories.single.parentId, '0');
    final page = await client.browse(source, categoryId: '10', page: 2);
    expect(requests[0].queryParameters,
        {'ac': 'list', 'pg': '1', 'token': 'test'});
    expect(requests[1].queryParameters,
        {'ac': 'videolist', 'pg': '2', 't': '10', 'token': 'test'});
    expect(page.hasMore, true);
    final entry = MediaEntry.fromJson(page.entries.single.toJson());
    expect(entry.description, 'Hello world');
    expect(entry.year, '2026');
    expect(entry.categoryId, '10');
    expect(entry.actors, '甲,乙');
    expect(entry.remarks, '更新至2集');
    await expectLater(client.browse(source, page: 0), throwsFormatException);
    await expectLater(
        client.categories(source.withEnabled(false)), throwsFormatException);
    expect(requests.length, 2);
  });

  test(
      'malformed categories are ignored and pagination never invents more pages',
      () {
    expect(
        CatalogCategory.parse({
          'class': [
            null,
            {'type_name': 'bad'},
            {'type_id': 1, 'type_name': 'movie'},
            {'type_id': 1, 'type_name': 'duplicate'}
          ]
        }).length,
        1);
    expect(
        CatalogListing.parse({'list': [], 'pagecount': 999}, 'source', 1)
            .hasMore,
        false);
    expect(
        CatalogListing.parse({
          'list': [
            {'vod_name': 'one'}
          ]
        }, 'source', 1)
            .hasMore,
        false);
    expect(
        MediaEntry.fromJson({'id': 'old', 'title': 'Saved', 'source': 'manual'})
            .remarks,
        '');
  });

  test('controller aliases categories and merges pages without duplicated IDs',
      () async {
    final library = Library(SharedPreferencesAsync())..sources = [source];
    final client = _FakeCatalog();
    final controller = BrowseController(library, client: client);
    addTearDown(controller.dispose);
    addTearDown(client.dispose);
    await controller.refresh();
    expect(controller.categoryFor('电视剧')?.id, '10');
    expect(controller.categoryFor('热门短剧')?.id, '30');
    expect(controller.categoryFor('AI漫剧'), isNull);
    await controller.ensureLabel('电影');
    await controller.load('20', more: true);
    expect(controller.feeds['20']!.listing!.entries.length, 2);
    expect(controller.feeds['20']!.listing!.hasMore, false);
    final count = client.requested.length;
    await controller.load('20', more: true);
    expect(client.requested.length, count);
  });

  test('late results from previous source cannot replace the current source',
      () async {
    const old = SourceEndpoint(name: 'old', url: 'https://old.example/api');
    const next = SourceEndpoint(name: 'new', url: 'https://new.example/api');
    final library = Library(SharedPreferencesAsync())..sources = [old, next];
    final client = _FakeCatalog()..blocked = Completer<CatalogListing>();
    final controller = BrowseController(library, client: client);
    addTearDown(controller.dispose);
    addTearDown(client.dispose);
    await controller.selectSource(next);
    client.blocked!.complete(const CatalogListing(
        [MediaEntry(id: 'old', title: 'Stale', source: 'old')]));
    await Future<void>.delayed(Duration.zero);
    expect(controller.feeds['']!.listing!.entries.single.source, 'new');
    expect(controller.source, next);
  });

  test(
      'source removal clears cached content and stale results; no source makes no requests',
      () async {
    final library = Library(SharedPreferencesAsync());
    final client = _FakeCatalog();
    final controller = BrowseController(library, client: client);
    addTearDown(controller.dispose);
    addTearDown(client.dispose);
    expect(client.requested, isEmpty);
    library.sources = [source];
    library.notifyListeners();
    await controller.refresh();
    expect(controller.feeds, isNotEmpty);
    library.sources = [source.withEnabled(false)];
    library.notifyListeners();
    expect(controller.source, isNull);
    expect(controller.feeds, isEmpty);
  });

  test('feed errors can retry while retaining previously loaded pages',
      () async {
    final library = Library(SharedPreferencesAsync())..sources = [source];
    final client = _FakeCatalog();
    final controller = BrowseController(library, client: client);
    addTearDown(controller.dispose);
    addTearDown(client.dispose);
    await controller.refresh();
    client.fail = true;
    await controller.load('', more: true);
    expect(controller.feeds['']!.error, isNotNull);
    expect(controller.feeds['']!.listing!.page, 1);
    client.fail = false;
    await controller.load('', more: true);
    expect(controller.feeds['']!.listing!.page, 2);
    expect(controller.feeds['']!.error, isNull);
  });

  test('disposing controller ignores outstanding fetch completions', () async {
    final library = Library(SharedPreferencesAsync())
      ..sources = [
        const SourceEndpoint(name: 'old', url: 'https://old.example')
      ];
    final client = _FakeCatalog()..blocked = Completer<CatalogListing>();
    final controller = BrowseController(library, client: client);
    controller.dispose();
    client.blocked!.complete(const CatalogListing([]));
    await Future<void>.delayed(Duration.zero);
    client.dispose();
  });
}
