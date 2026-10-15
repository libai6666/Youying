import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:shared_preferences_platform_interface/shared_preferences_async_platform_interface.dart';
import 'package:youying/catalog.dart';
import 'package:youying/library.dart';
import 'package:youying/main.dart';

final class _NoStorage extends SharedPreferencesAsyncPlatform {
  @override
  dynamic noSuchMethod(Invocation invocation) =>
      throw StateError('Unexpected storage');
}

class PreviewCatalog extends CatalogClient {
  final requested = <String>[];
  bool fail = false;
  @override
  Future<List<CatalogCategory>> categories(SourceEndpoint source) async =>
      const [
        CatalogCategory('1', '电影'),
        CatalogCategory('2', '连续剧'),
        CatalogCategory('3', '综艺'),
        CatalogCategory('4', '动漫'),
        CatalogCategory('46', '爽文短剧'),
      ];
  @override
  Future<CatalogListing> browse(SourceEndpoint source,
      {String? categoryId, int page = 1}) async {
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

void main() {
  setUp(() => SharedPreferencesAsyncPlatform.instance = _NoStorage());
  Future<PreviewCatalog> mount(WidgetTester tester,
      {double width = 390, double textScale = 1}) async {
    tester.view.physicalSize = Size(width, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final client = PreviewCatalog();
    addTearDown(client.dispose);
    await tester.pumpWidget(MaterialApp(
        theme: youyingTheme(),
        builder: (context, child) => MediaQuery(
            data: MediaQuery.of(context)
                .copyWith(textScaler: TextScaler.linear(textScale)),
            child: child!),
        home: HomePage(library: previewLibrary(), browseClient: client)));
    await tester.pumpAndSettle();
    return client;
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
    expect(find.text('加载更多').hitTestable(), findsOneWidget);
    await tester.tap(find.text('加载更多'));
    await tester.pumpAndSettle();
    expect(client.requested, contains('1:2'));
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
    expect(find.text('已下载文件：0'), findsOneWidget);
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
    await tester.ensureVisible(find.text('AI漫剧'));
    await tester.tap(find.text('AI漫剧'));
    await tester.pumpAndSettle();
    expect(find.text('已启用来源未提供“AI漫剧”分类'), findsOneWidget);
  });

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
