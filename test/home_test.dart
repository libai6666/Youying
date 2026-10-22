import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:shared_preferences_platform_interface/shared_preferences_async_platform_interface.dart';
import 'package:youying/catalog.dart';
import 'package:youying/library.dart';
import 'package:youying/main.dart';

final class _NoStorage extends SharedPreferencesAsyncPlatform {
  @override
  dynamic noSuchMethod(Invocation invocation) {
    if (invocation.memberName == #setString) return Future<void>.value();
    throw StateError('Unexpected storage');
  }
}

class PreviewCatalog extends CatalogClient {
  final requested = <String>[];
  bool fail = false;
  Completer<void>? categoriesGate;
  Completer<void>? browseGate;
  @override
  Future<List<CatalogCategory>> categories(SourceEndpoint source) async {
    if (categoriesGate != null) await categoriesGate!.future;
    return const [
      CatalogCategory('1', '电影'),
      CatalogCategory('2', '连续剧'),
      CatalogCategory('3', '综艺'),
      CatalogCategory('4', '动漫'),
      CatalogCategory('46', '爽文短剧'),
    ];
  }

  @override
  Future<CatalogListing> browse(SourceEndpoint source,
      {String? categoryId, int page = 1}) async {
    if (browseGate != null) await browseGate!.future;
    requested.add('$categoryId:$page');
    if (fail) throw const FormatException('mock network failure');
    final name = switch (categoryId) {
      '2' => '剧集',
      '3' => '综艺',
      '4' => '动漫',
      _ => '影片'
    };
    return CatalogListing(
        List.generate(
            10,
            (i) => MediaEntry(
                  id: '${source.name}:$categoryId:$page:$i',
                  title: '$name示例 ${i + 1}',
                  source: source.name,
                  category: name,
                  year: '2026',
                  area: '中国大陆',
                  remarks: '更新至12集',
                  actors: '演员甲,演员乙,演员丙',
                  description: '这是自动化组件测试的数据，仅用于验证页面布局与交互，不代表真实影视资源或热度排行。',
                )),
        page: page,
        pageCount: 2);
  }
}

Library previewLibrary() => Library(SharedPreferencesAsync())
  ..sources = [
    const SourceEndpoint(name: '测试源', url: 'https://example.com/api')
  ]
  ..history['demo'] =
      const MediaEntry(id: 'demo', title: '最近观看示例', source: '测试源');

class FacetCatalog extends PreviewCatalog {
  @override
  Future<CatalogListing> browse(SourceEndpoint source,
      {String? categoryId, int page = 1}) async {
    if (categoryId != '1') {
      return super.browse(source, categoryId: categoryId, page: page);
    }
    return CatalogListing(
        page == 1
            ? const [
                MediaEntry(
                    id: 'action',
                    title: '动作电影甲',
                    source: '测试源',
                    category: '动作片',
                    genres: '动作,冒险',
                    area: '美国',
                    language: '英语',
                    year: '2025',
                    rating: 7,
                    popularity: 100,
                    updatedAtMs: 100),
                MediaEntry(
                    id: 'comedy',
                    title: '喜剧电影乙',
                    source: '测试源',
                    category: '喜剧片',
                    area: '中国大陆',
                    language: '汉语普通话',
                    year: '2026',
                    rating: 9,
                    popularity: 10,
                    updatedAtMs: 200),
              ]
            : const [
                MediaEntry(
                    id: 'more',
                    title: '动作电影丙',
                    source: '测试源',
                    category: '动作片',
                    area: '美国',
                    language: '英语',
                    year: '2025',
                    updatedAtMs: 300)
              ],
        page: page,
        pageCount: 2);
  }
}

class AiDramaCatalog extends PreviewCatalog {
  @override
  Future<List<CatalogCategory>> categories(SourceEndpoint source) async => [
        ...await super.categories(source),
        const CatalogCategory('54', 'AI漫剧'),
      ];

  @override
  Future<CatalogListing> browse(SourceEndpoint source,
      {String? categoryId, int page = 1}) async {
    if (categoryId != '54') {
      return super.browse(source, categoryId: categoryId, page: page);
    }
    return CatalogListing(const [
      MediaEntry(
          id: 'ai-travel',
          title: '和闺蜜穿越落魄王府',
          source: '测试源',
          category: 'AI漫剧',
          area: '中国大陆',
          language: '普通话',
          year: '2026',
          updatedAtMs: 200),
      MediaEntry(
          id: 'ai-doom',
          title: '天灾降临囤物资',
          source: '测试源',
          category: 'AI漫剧',
          area: '中国大陆',
          language: '普通话',
          year: '2026',
          updatedAtMs: 100),
    ], page: page, pageCount: 1);
  }
}

class PartialFailureCatalog extends PreviewCatalog {
  bool failCategories = false;
  bool failBrowse = false;

  @override
  Future<List<CatalogCategory>> categories(SourceEndpoint source) async {
    if (source.name == '故障源' && failCategories) {
      throw const FormatException('mock category failure');
    }
    return super.categories(source);
  }

  @override
  Future<CatalogListing> browse(SourceEndpoint source,
      {String? categoryId, int page = 1}) async {
    if (source.name == '故障源' && failBrowse) {
      throw const FormatException('mock browse failure');
    }
    return super.browse(source, categoryId: categoryId, page: page);
  }
}

class ArtworkCatalog extends PreviewCatalog {
  ArtworkCatalog({this.backdrop = ''});
  final String backdrop;

  @override
  Future<CatalogListing> browse(SourceEndpoint source,
          {String? categoryId, int page = 1}) async =>
      CatalogListing([
        MediaEntry(
            id: '${source.name}:1',
            title: '封面回归片',
            source: source.name,
            category: '电影',
            year: '2026',
            poster: source.name == 'A'
                ? 'https://images.example/blocked.jpg'
                : 'https://images.example/working.jpg',
            backdrop: backdrop),
      ]);
}

class SparseArtworkCatalog extends PreviewCatalog {
  int lookups = 0;

  @override
  Future<CatalogListing> browse(SourceEndpoint source,
          {String? categoryId, int page = 1}) async =>
      CatalogListing(source.name == 'A'
          ? const [
              MediaEntry(
                  id: 'A:1',
                  title: '同片异年',
                  source: 'A',
                  year: '2026',
                  category: '国产剧',
                  actors: '演员甲,演员乙',
                  poster: 'https://images.example/blocked.jpg'),
            ]
          : []);

  @override
  Future<List<MediaEntry>> search(SourceEndpoint source, String query) async {
    lookups++;
    return const [
      MediaEntry(
          id: 'B:2',
          title: '同片异年',
          source: 'B',
          year: '2014',
          category: '国产剧',
          actors: '演员甲,演员乙',
          poster: 'https://images.example/working.jpg'),
    ];
  }
}

class _ImageClient extends Fake implements HttpClient {
  final requests = <Uri>[];
  bool failAll = false;

  @override
  Future<HttpClientRequest> getUrl(Uri url) async {
    requests.add(url);
    return _ImageRequest(failAll || !url.path.endsWith('working.jpg'));
  }
}

class _ImageRequest extends Fake implements HttpClientRequest {
  _ImageRequest(this.failed);
  final bool failed;
  @override
  Future<HttpClientResponse> close() async => _ImageResponse(failed);
}

class _ImageResponse extends Fake implements HttpClientResponse {
  _ImageResponse(this.failed);
  final bool failed;
  static final bytes = base64Decode(
      'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR4nGNgYGD4DwABBAEAX+XDSwAAAABJRU5ErkJggg==');
  @override
  int get statusCode => failed ? 418 : 200;
  @override
  int get contentLength => bytes.length;
  @override
  HttpClientResponseCompressionState get compressionState =>
      HttpClientResponseCompressionState.notCompressed;
  @override
  Future<E> drain<E>([E? futureValue]) async => futureValue as E;
  @override
  StreamSubscription<List<int>> listen(void Function(List<int>)? onData,
          {Function? onError, void Function()? onDone, bool? cancelOnError}) =>
      Stream<List<int>>.value(bytes).listen(onData,
          onError: onError, onDone: onDone, cancelOnError: cancelOnError);
}

void main() {
  setUp(() => SharedPreferencesAsyncPlatform.instance = _NoStorage());
  Future<PreviewCatalog> mount(WidgetTester tester,
      {double width = 390,
      double textScale = 1,
      PreviewCatalog? catalog,
      Library? library}) async {
    tester.view.physicalSize = Size(width, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final client = catalog ?? PreviewCatalog();
    addTearDown(client.dispose);
    await tester.pumpWidget(MaterialApp(
        theme: youyingTheme(),
        builder: (context, child) => MediaQuery(
            data: MediaQuery.of(context)
                .copyWith(textScaler: TextScaler.linear(textScale)),
            child: child!),
        home: HomePage(
            library: library ?? previewLibrary(), browseClient: client)));
    await tester.pumpAndSettle();
    return client;
  }

  Library artworkLibrary() => previewLibrary()
    ..history.clear()
    ..sources = const [
      SourceEndpoint(name: 'A', url: 'https://a.example/api'),
      SourceEndpoint(name: 'B', url: 'https://b.example/api'),
    ];

  Future<_ImageClient> mountArtwork(WidgetTester tester,
      {String backdrop = '',
      PreviewCatalog? catalog,
      bool failAll = false,
      double width = 390,
      double textScale = 1}) async {
    final images = _ImageClient()..failAll = failAll;
    debugNetworkImageHttpClientProvider = () => images;
    addTearDown(() {
      debugNetworkImageHttpClientProvider = null;
      PaintingBinding.instance.imageCache.clear();
      PaintingBinding.instance.imageCache.clearLiveImages();
    });
    try {
      await mount(tester,
          width: width,
          textScale: textScale,
          catalog: catalog ?? ArtworkCatalog(backdrop: backdrop),
          library: artworkLibrary());
      for (var i = 0; i < 8; i++) {
        await tester.runAsync(
            () => Future<void>.delayed(const Duration(milliseconds: 10)));
        await tester.pump();
      }
      return images;
    } finally {
      debugNetworkImageHttpClientProvider = null;
    }
  }

  testWidgets('home retries another source artwork after HTTP 418',
      (tester) async {
    final images = await mountArtwork(tester);
    expect(images.requests.any((uri) => uri.path == '/blocked.jpg'), isTrue);
    expect(images.requests.any((uri) => uri.path == '/working.jpg'), isTrue);
    expect(images.requests.every((uri) => uri.scheme == 'https'), isTrue);
    final spotlight = find.byType(PageView).first;
    final poster = find.descendant(
        of: spotlight,
        matching: find.byWidgetPredicate((widget) =>
            widget is Image &&
            widget.key ==
                const ValueKey('https://images.example/working.jpg')));
    expect(poster, findsOneWidget);
    expect(tester.widget<Image>(poster).fit, BoxFit.contain);
    expect(
        find.descendant(
            of: poster,
            matching: find.byWidgetPredicate(
                (widget) => widget is RawImage && widget.image != null)),
        findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets(
      'failed cover searches unloaded source and corroborates different years',
      (tester) async {
    final client = SparseArtworkCatalog();
    final images = await mountArtwork(tester, catalog: client);
    expect(images.requests.any((uri) => uri.path == '/blocked.jpg'), true);
    expect(images.requests.any((uri) => uri.path == '/working.jpg'), true);
    expect(client.lookups, 1);
    expect(tester.takeException(), isNull);
  });

  testWidgets('spotlight uses an uncropped backdrop when provided',
      (tester) async {
    await mountArtwork(tester, backdrop: 'https://images.example/working.jpg');
    final spotlight = find.byType(PageView).first;
    final image = find.descendant(
        of: spotlight,
        matching: find.byWidgetPredicate((widget) =>
            widget is Image &&
            widget.key ==
                const ValueKey('https://images.example/working.jpg')));
    expect(tester.widget<Image>(image).fit, BoxFit.contain);
    expect(tester.takeException(), isNull);
  });

  testWidgets(
      'failed backdrop keeps the full portrait on a small accessible layout',
      (tester) async {
    await mountArtwork(tester,
        width: 320,
        textScale: 1.4,
        backdrop: 'https://images.example/failed-wide.jpg');
    final image = find.descendant(
        of: find.byType(PageView).first,
        matching: find.byWidgetPredicate((widget) =>
            widget is Image &&
            widget.key ==
                const ValueKey('https://images.example/working.jpg')));
    expect(image, findsOneWidget);
    expect(tester.widget<Image>(image).fit, BoxFit.contain);
    expect(
        find.descendant(
            of: image,
            matching: find.byWidgetPredicate(
                (widget) => widget is RawImage && widget.image != null)),
        findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets(
      'failed backdrop falls back to portrait, exhausted covers show a placeholder',
      (tester) async {
    final images = await mountArtwork(tester,
        backdrop: 'https://images.example/failed-wide.jpg', failAll: true);
    expect(
        images.requests.any((uri) => uri.path == '/failed-wide.jpg'), isTrue);
    expect(images.requests.any((uri) => uri.path == '/blocked.jpg'), isTrue);
    expect(images.requests.any((uri) => uri.path == '/working.jpg'), isTrue);
    expect(find.byIcon(Icons.movie_outlined), findsWidgets);
    expect(tester.takeException(), isNull);
  });

  Library partialLibrary() => previewLibrary()
    ..sources = [
      ...previewLibrary().sources,
      const SourceEndpoint(name: '故障源', url: 'https://broken.example/api'),
    ];

  Future<void> saveScrollOffset(WidgetTester tester, Finder list) async {
    final scrollable =
        find.descendant(of: list, matching: find.byType(Scrollable)).first;
    final position = tester.state<ScrollableState>(scrollable).position;
    expect(position.maxScrollExtent, greaterThan(0));
    position.jumpTo(position.maxScrollExtent);
    await tester.pumpAndSettle();
    final context = tester.element(list);
    expect(PageStorage.of(context).readState(context), isA<double>());
  }

  testWidgets('home keeps spotlight and poster sections while refreshing',
      (tester) async {
    final client = PreviewCatalog();
    await mount(tester, catalog: client);
    expect(find.text('剧集示例 1'), findsWidgets);
    client.categoriesGate = Completer<void>();
    client.browseGate = Completer<void>();
    final pending = tester
        .widget<RefreshIndicator>(find.byType(RefreshIndicator).first)
        .onRefresh();
    await tester.pump();
    expect(find.text('剧集示例 1'), findsWidgets);
    expect(find.text('热播剧推荐'), findsOneWidget);
    client.categoriesGate!.complete();
    await tester.pump();
    expect(find.text('剧集示例 1'), findsWidgets);
    client.fail = true;
    client.browseGate!.complete();
    await tester.pumpAndSettle();
    await pending;
    expect(find.text('剧集示例 1'), findsWidgets);
    expect(tester.takeException(), isNull);
  });

  testWidgets('home source issues do not read saved scroll offsets as booleans',
      (tester) async {
    final client = PartialFailureCatalog();
    await mount(tester, catalog: client, library: partialLibrary());
    final list = find.byKey(const PageStorageKey('home-首页'));
    await saveScrollOffset(tester, list);
    client.failCategories = true;
    await tester
        .widget<RefreshIndicator>(find.byType(RefreshIndicator).first)
        .onRefresh();
    await tester.pumpAndSettle();
    await tester.drag(list, const Offset(0, -2000));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    expect(find.text('部分内容来源暂时不可用'), findsOneWidget);
    await tester.tap(find.text('部分内容来源暂时不可用'));
    await tester.pumpAndSettle();
    final tileContext = tester.element(find.byType(ExpansionTile).first);
    expect(PageStorage.of(tileContext).readState(tileContext), isTrue);
    final listContext = tester.element(list);
    expect(PageStorage.of(listContext).readState(listContext), isA<double>());
  });

  for (final ranked in [false, true]) {
    testWidgets(
        '${ranked ? 'ranking' : 'category'} keeps cards throughout refresh and failure',
        (tester) async {
      final client = PreviewCatalog();
      await mount(tester, catalog: client);
      if (ranked) {
        await tester.tap(find.text('排行榜'));
        await tester.pumpAndSettle();
      }
      await tester.tap(find.text('电影'));
      await tester.pumpAndSettle();
      expect(find.text('影片示例 1'), findsOneWidget);
      client.categoriesGate = Completer<void>();
      client.browseGate = Completer<void>();
      final pending = tester
          .widget<RefreshIndicator>(find.byType(RefreshIndicator).first)
          .onRefresh();
      await tester.pump();
      expect(find.text('影片示例 1'), findsOneWidget);
      client.categoriesGate!.complete();
      await tester.pump();
      expect(find.text('影片示例 1'), findsOneWidget);
      client.fail = true;
      client.browseGate!.complete();
      await tester.pumpAndSettle();
      await pending;
      expect(find.text('影片示例 1'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });

    testWidgets(
        '${ranked ? 'ranking' : 'category'} issues have separate storage from scrolling',
        (tester) async {
      final client = PartialFailureCatalog();
      await mount(tester, catalog: client, library: partialLibrary());
      if (ranked) {
        await tester.tap(find.text('排行榜'));
        await tester.pumpAndSettle();
      }
      await tester.tap(find.text('电影'));
      await tester.pumpAndSettle();
      if (!ranked) {
        tester.view.physicalSize = const Size(390, 420);
        await tester.pumpAndSettle();
      }
      final list =
          find.byKey(PageStorageKey('${ranked ? 'ranking' : 'home'}-电影'));
      await saveScrollOffset(tester, list);
      client.failBrowse = true;
      final refresh = find.byType(RefreshIndicator).first;
      await tester.widget<RefreshIndicator>(refresh).onRefresh();
      await tester.pumpAndSettle();
      await tester.drag(list, const Offset(0, -2000));
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      // Scrolling to the end retries the failed source automatically.
      final issues = find.text('部分来源加载失败');
      if (issues.evaluate().isEmpty) {
        expect(find.text('本批内容加载失败，请重试'), findsOneWidget);
        expect(find.text('重试'), findsOneWidget);
      } else {
        await tester.tap(issues);
        await tester.pumpAndSettle();
        expect(find.text('重试未完成来源').hitTestable(), findsOneWidget);
      }
      final listContext = tester.element(list);
      expect(PageStorage.of(listContext).readState(listContext), isA<double>());
    });
  }

  testWidgets(
      'home renders real-feed sections and search navigation without login or ads',
      (tester) async {
    await mount(tester);
    expect(find.text('热播剧推荐'), findsOneWidget);
    expect(find.text('热播综艺'), findsOneWidget);
    expect(find.text('请输入关键字'), findsOneWidget);
    expect(find.text('登录'), findsNothing);
    expect(find.text('广告'), findsNothing);
    await tester.tap(find.text('请输入关键字'));
    await tester.pumpAndSettle();
    expect(find.byType(SearchPage), findsOneWidget);
    expect(find.byType(TextField), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('category facets combine, survive tab changes, and reset',
      (tester) async {
    await mount(tester,
        catalog: FacetCatalog(), library: previewLibrary()..history.clear());
    await tester.tap(find.text('电影'));
    await tester.pumpAndSettle();
    for (final facet in [
      ('类型', '动作'),
      ('地区', '美国'),
      ('语言', '英语'),
      ('年份', '2025')
    ]) {
      final chip = find.byKey(ValueKey('filter-电影-${facet.$1}-${facet.$2}'));
      await tester.ensureVisible(chip);
      await tester.tap(chip);
      await tester.pumpAndSettle();
    }
    expect(find.text('喜剧电影乙'), findsNothing);
    expect(find.text('动作电影甲'), findsOneWidget);
    await tester.tap(find.text('电视剧'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('电影'));
    await tester.pumpAndSettle();
    expect(
        tester
            .widget<ChoiceChip>(find.byKey(const ValueKey('filter-电影-类型-动作')))
            .selected,
        isTrue);
    await tester.ensureVisible(find.text('重置筛选'));
    await tester.tap(find.text('重置筛选'));
    await tester.pumpAndSettle();
    expect(find.text('喜剧电影乙'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('real metrics enable sorting while absent metrics are disabled',
      (tester) async {
    await mount(tester);
    await tester.tap(find.text('电影'));
    await tester.pumpAndSettle();
    expect(
        tester
            .widget<ChoiceChip>(find.byKey(const ValueKey('filter-电影-排序-最热')))
            .onSelected,
        isNull);
    expect(
        tester
            .widget<ChoiceChip>(find.byKey(const ValueKey('filter-电影-排序-好评')))
            .onSelected,
        isNull);
  });

  testWidgets('category ordering follows real heat and score values',
      (tester) async {
    await mount(tester,
        catalog: FacetCatalog(), library: previewLibrary()..history.clear());
    await tester.tap(find.text('电影'));
    await tester.pumpAndSettle();
    expect(tester.getTopLeft(find.text('喜剧电影乙')).dx,
        lessThan(tester.getTopLeft(find.text('动作电影甲')).dx));
    await tester.tap(find.byKey(const ValueKey('filter-电影-排序-最热')));
    await tester.pumpAndSettle();
    expect(tester.getTopLeft(find.text('动作电影甲')).dx,
        lessThan(tester.getTopLeft(find.text('喜剧电影乙')).dx));
    expect(find.text('按来源点击量排序，不是平台热度榜'), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('filter-电影-排序-好评')));
    await tester.pumpAndSettle();
    expect(tester.getTopLeft(find.text('喜剧电影乙')).dx,
        lessThan(tester.getTopLeft(find.text('动作电影甲')).dx));
  });

  testWidgets(
      'load more applies the current facets without mixing old selections',
      (tester) async {
    await mount(tester,
        catalog: FacetCatalog(), library: previewLibrary()..history.clear());
    await tester.tap(find.text('电影'));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('filter-电影-类型-动作')));
    await tester.pumpAndSettle();
    expect(find.text('上滑加载更多'), findsOneWidget);
    expect(find.text('加载更多'), findsNothing);
    await tester.drag(
        find.byKey(const PageStorageKey('home-电影')), const Offset(0, -600));
    await tester.pumpAndSettle();
    expect(find.text('动作电影甲'), findsOneWidget);
    expect(find.text('动作电影丙'), findsOneWidget);
    expect(find.text('喜剧电影乙'), findsNothing);
    await tester.ensureVisible(find.byKey(const ValueKey('filter-电影-类型-喜剧')));
    await tester.tap(find.byKey(const ValueKey('filter-电影-类型-喜剧')));
    await tester.pumpAndSettle();
    expect(find.text('喜剧电影乙'), findsOneWidget);
    expect(find.text('动作电影甲'), findsNothing);
    expect(find.text('动作电影丙'), findsNothing);
  });

  testWidgets('AI tab filters by inferred theme without region facets',
      (tester) async {
    await mount(tester,
        catalog: AiDramaCatalog(), library: previewLibrary()..history.clear());
    await tester.ensureVisible(find.text('AI短剧'));
    await tester.tap(find.text('AI短剧'));
    await tester.pumpAndSettle();
    expect(find.text('题材'), findsOneWidget);
    expect(find.text('题材按片名和简介推断，仅供参考'), findsOneWidget);
    for (final facet in ['地区', '语言', '年份', '类型']) {
      expect(find.text(facet), findsNothing);
    }
    expect(find.byKey(const ValueKey('filter-AI短剧-排序-好评')), findsNothing);
    expect(find.byKey(const ValueKey('filter-AI短剧-题材-冒险')), findsNothing);
    expect(find.text('和闺蜜穿越落魄王府'), findsOneWidget);
    expect(find.text('天灾降临囤物资'), findsOneWidget);
    final chip = find.byKey(const ValueKey('filter-AI短剧-题材-末世'));
    await tester.ensureVisible(chip);
    await tester.tap(chip);
    await tester.pumpAndSettle();
    expect(find.text('天灾降临囤物资'), findsOneWidget);
    expect(find.text('和闺蜜穿越落魄王府'), findsNothing);
    expect(tester.takeException(), isNull);
  });

  for (final width in [320.0, 1280.0]) {
    testWidgets('category filters fit $width with large text', (tester) async {
      await mount(tester,
          width: width, textScale: 1.4, catalog: FacetCatalog());
      await tester.tap(find.text('电影'));
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('filter-电影-年份-2025')), findsOneWidget);
      expect(tester.takeException(), isNull);
    });
  }

  testWidgets(
      'rankings expose source-order disclaimer and category cards with pagination',
      (tester) async {
    final client = await mount(tester);
    await tester.tap(find.text('排行榜'));
    await tester.pumpAndSettle();
    expect(find.text('聚合更新顺序 · 非热度榜'), findsOneWidget);
    expect(find.text('剧集示例 1'), findsOneWidget);
    await tester.tap(find.text('电影'));
    await tester.pumpAndSettle();
    expect(client.requested, contains('1:1'));
    await tester.drag(
        find.byKey(const PageStorageKey('ranking-电影')), const Offset(0, -1000));
    await tester.pumpAndSettle();
    await tester.drag(
        find.byKey(const PageStorageKey('ranking-电影')), const Offset(0, -1000));
    await tester.pumpAndSettle();
    expect(client.requested, contains('1:2'));
    expect(client.requested.where((r) => r == '1:2'), hasLength(1));
    expect(tester.takeException(), isNull);
  });

  testWidgets('my page connects local history favorites downloads and settings',
      (tester) async {
    await mount(tester);
    await tester.tap(find.text('我的'));
    await tester.pumpAndSettle();
    expect(find.text('本地观影'), findsOneWidget);
    expect(find.text('常用功能'), findsOneWidget);
    expect(find.text('系统消息'), findsNothing);
    expect(find.text('留言求片'), findsNothing);
    await tester.tap(find.text('我的收藏'));
    await tester.pumpAndSettle();
    expect(find.text('还没有收藏，去详情页收藏喜欢的内容吧'), findsOneWidget);
    await tester.pageBack();
    await tester.pumpAndSettle();
    await tester.tap(find.text('我的下载'));
    await tester.pumpAndSettle();
    expect(find.text('暂无下载任务'), findsOneWidget);
    await tester.pageBack();
    await tester.pumpAndSettle();
    await tester.tap(find.text('设置'));
    await tester.pumpAndSettle();
    expect(find.byType(SettingsPage), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets(
      'unsupported categories explain the gap instead of inventing content',
      (tester) async {
    await mount(tester);
    await tester.ensureVisible(find.text('AI短剧'));
    await tester.tap(find.text('AI短剧'));
    await tester.pumpAndSettle();
    expect(find.text('已启用来源未提供“AI短剧”分类'), findsOneWidget);
  });

  for (final width in [320.0, 390.0]) {
    testWidgets(
        'history shows source, most recent episode and progress at $width with large text',
        (tester) async {
      const episodes = [
        Episode(name: '第01集', url: 'https://example.com/1.mp4'),
        Episode(name: '第02集', url: 'https://example.com/2.mp4')
      ];
      const entry = MediaEntry(
          id: 'history:1',
          title: '进度展示剧集',
          source: '测试来源',
          lines: {'主线': episodes});
      final library = previewLibrary();
      await library.recordPlay(entry,
          episode: episodes.first,
          position: 60000,
          duration: 60000,
          completed: true);
      await library.recordPlay(entry,
          episode: episodes.last, position: 30000, duration: 60000);
      await mount(tester, width: width, textScale: 1.4, library: library);
      await tester.tap(find.text('我的'));
      await tester.pumpAndSettle();
      expect(find.text('测试来源 · 第02集'), findsOneWidget);
      expect(find.text('已观看 50%'), findsOneWidget);
      expect(find.text('0:30'), findsOneWidget);
      expect(tester.takeException(), isNull);
      await tester.tap(find.text('观看历史').first);
      await tester.pumpAndSettle();
      expect(find.text('测试来源 · 第02集 · 已观看 50% · 0:30 / 1:00'), findsOneWidget);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
      library.dispose();
    });
  }

  testWidgets('320px phone has no overflowing layouts', (tester) async {
    await mount(tester, width: 320);
    expect(tester.takeException(), isNull);
    await tester.tap(find.text('排行榜'));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    await tester.tap(find.text('我的'));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
  });

  testWidgets('larger accessibility text fits the three main pages',
      (tester) async {
    await mount(tester, width: 320, textScale: 1.3);
    expect(tester.takeException(), isNull);
    await tester.tap(find.text('排行榜'));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    await tester.tap(find.text('我的'));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
  });
}
