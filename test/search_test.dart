import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:shared_preferences_platform_interface/shared_preferences_async_platform_interface.dart';
import 'package:youying/catalog.dart';
import 'package:youying/library.dart';
import 'package:youying/main.dart';
import 'package:youying/ui_locale.dart';

final class _MemoryStorage extends SharedPreferencesAsyncPlatform {
  final values = <String, Object>{};
  @override
  dynamic noSuchMethod(Invocation invocation) {
    final key = invocation.positionalArguments.first as String;
    if (invocation.memberName == #setString) {
      values[key] = invocation.positionalArguments[1] as String;
      return Future<void>.value();
    }
    throw StateError('Unexpected preference call');
  }
}

void main() {
  setUp(() => SharedPreferencesAsyncPlatform.instance = _MemoryStorage());
  Library library() => Library(SharedPreferencesAsync())
    ..sources = const [
      SourceEndpoint(name: 'A', url: 'https://a.example/api'),
      SourceEndpoint(name: 'B', url: 'https://b.example/api'),
    ];
  http.Response response(String name, {String kind = '电影'}) => http.Response(
      jsonEncode({
        'list': [
          {'vod_id': 1, 'vod_name': name, 'vod_year': 2026, 'type_name': kind}
        ]
      }),
      200,
      headers: {'content-type': 'application/json; charset=utf-8'});

  testWidgets('search merges matching work and supports category filters',
      (tester) async {
    final client =
        CatalogClient(client: MockClient((_) async => response('共同电影')));
    addTearDown(client.dispose);
    final lib = library();
    await tester.pumpWidget(MaterialApp(
        home: Scaffold(body: SearchPage(library: lib, client: client))));
    expect(find.byType(SearchResultsPage), findsNothing);
    expect(find.byType(EntryList), findsNothing);
    await tester.enterText(find.byType(TextField), '共同电影');
    await tester.pump();
    await tester.tap(find.widgetWithText(TextButton, '搜索'));
    await tester.pump();
    await tester.runAsync(() async {
      await Future<void>.delayed(const Duration(milliseconds: 30));
    });
    await tester.pumpAndSettle();
    expect(find.byType(SearchResultsPage), findsOneWidget);
    expect(find.text('搜索历史'), findsNothing);
    expect(
        find.descendant(
            of: find.byType(EntryList), matching: find.text('共同电影')),
        findsOneWidget);
    expect(find.text('找到 1 部影片'), findsOneWidget);
    await tester.tap(find.widgetWithText(ChoiceChip, '电视剧'));
    await tester.pumpAndSettle();
    expect(
        find.descendant(
            of: find.byType(EntryList), matching: find.text('共同电影')),
        findsNothing);
    await tester.tap(find.widgetWithText(ChoiceChip, '电影'));
    await tester.pumpAndSettle();
    expect(
        find.descendant(
            of: find.byType(EntryList), matching: find.text('共同电影')),
        findsOneWidget);
    await tester.tap(find.byTooltip('收藏'));
    await tester.pumpAndSettle();
    expect(lib.favorites.length, 1);
    expect(find.byTooltip('取消收藏'), findsOneWidget);
    await tester.tap(find.byTooltip('取消收藏'));
    await tester.pumpAndSettle();
    expect(lib.favorites, isEmpty);
    await tester.tap(find.descendant(
        of: find.byType(EntryList), matching: find.text('共同电影')));
    await tester.pump();
    final detail =
        tester.widget<DetailPage>(find.byType(DetailPage, skipOffstage: false));
    expect(detail.entry.title, '共同电影');
    expect(detail.variants.length, 2);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('late responses cannot replace a newer query', (tester) async {
    final old = Completer<http.Response>();
    final client = CatalogClient(
        client: MockClient((request) async =>
            request.url.queryParameters['wd'] == 'old'
                ? old.future
                : response('new')));
    addTearDown(client.dispose);
    final lib = library()..sources = [library().sources.first];
    await tester.pumpWidget(MaterialApp(
        home: Scaffold(body: SearchPage(library: lib, client: client))));
    await tester.enterText(find.byType(TextField), 'old');
    await tester.pump();
    await tester.tap(find.widgetWithText(TextButton, '搜索'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 350));
    await tester.enterText(
        find.descendant(
            of: find.byType(SearchResultsPage),
            matching: find.byType(TextField)),
        'new');
    await tester.pump();
    await tester.runAsync(() async {
      await tester.tap(find.widgetWithText(TextButton, '搜索').last);
      await Future<void>.delayed(const Duration(milliseconds: 30));
      old.complete(response('old'));
      await Future<void>.delayed(const Duration(milliseconds: 30));
    });
    await tester.pumpAndSettle();
    expect(
        find.descendant(of: find.byType(EntryList), matching: find.text('new')),
        findsOneWidget);
    expect(
        find.descendant(of: find.byType(EntryList), matching: find.text('old')),
        findsNothing);
  });

  testWidgets('disabling a source during search discards its pending result',
      (tester) async {
    final pending = Completer<http.Response>();
    final client = CatalogClient(client: MockClient((_) => pending.future));
    addTearDown(client.dispose);
    final lib = library();
    await tester.pumpWidget(MaterialApp(
        home: Scaffold(body: SearchPage(library: lib, client: client))));
    await tester.enterText(find.byType(TextField), 'old');
    await tester.pump();
    await tester.tap(find.widgetWithText(TextButton, '搜索'));
    await tester.pump();
    lib.sources = [];
    lib.notifyListeners();
    await tester.runAsync(() async {
      pending.complete(response('old'));
      await Future<void>.delayed(const Duration(milliseconds: 30));
    });
    await tester.pumpAndSettle();
    expect(
        find.descendant(of: find.byType(EntryList), matching: find.text('old')),
        findsNothing);
    expect(find.text('来源设置已变化，请重新搜索'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets(
      'submitted history can be searched, individually removed and cleared',
      (tester) async {
    final requested = <String>[];
    final client = CatalogClient(client: MockClient((request) async {
      requested.add(request.url.queryParameters['wd']!);
      return response('结果');
    }));
    addTearDown(client.dispose);
    final lib = library()..sources = [library().sources.first];
    await lib.recordSearch('旧记录');
    await tester.pumpWidget(MaterialApp(
        home: Scaffold(body: SearchPage(library: lib, client: client))));
    await tester.enterText(find.byType(TextField), ' 新片名 ');
    await tester.pump();
    await tester.tap(find.widgetWithText(TextButton, '搜索'));
    await tester.pump();
    await tester.runAsync(() async {
      await Future<void>.delayed(const Duration(milliseconds: 30));
    });
    await tester.pumpAndSettle();
    expect(requested, ['新片名']);
    expect(lib.searchHistory, ['新片名', '旧记录']);
    expect(find.text('旧记录'), findsNothing);
    await tester.pageBack();
    await tester.pumpAndSettle();
    expect(find.byType(SearchResultsPage), findsNothing);
    final oldChip = find.widgetWithText(InkWell, '旧记录');
    await tester.tap(oldChip);
    await tester.pump();
    await tester.runAsync(() async {
      await Future<void>.delayed(const Duration(milliseconds: 30));
    });
    await tester.pumpAndSettle();
    expect(requested, ['新片名', '旧记录']);
    expect(tester.widget<TextField>(find.byType(TextField)).controller!.text,
        '旧记录');
    await tester.pageBack();
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('删除搜索记录：新片名'));
    await tester.pumpAndSettle();
    expect(lib.searchHistory, ['旧记录']);
    await tester.tap(find.text('清空'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('取消'));
    await tester.pumpAndSettle();
    expect(lib.searchHistory, ['旧记录']);
    await tester.tap(find.text('清空'));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(TextButton, '清空').last);
    await tester.pumpAndSettle();
    expect(lib.searchHistory, isEmpty);
    expect(find.text('搜索历史'), findsNothing);
  });

  testWidgets('long history keywords fit a narrow screen with large text',
      (tester) async {
    tester.view.physicalSize = const Size(320, 700);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final lib = library();
    await lib.recordSearch(List.filled(30, '这是很长的影片名字').join());
    await tester.pumpWidget(MaterialApp(
        builder: (context, child) => MediaQuery(
            data: MediaQuery.of(context)
                .copyWith(textScaler: TextScaler.linear(1.4)),
            child: child!),
        home: Scaffold(body: SearchPage(library: lib))));
    expect(
        find.text(List.filled(30, '这是很长的影片名字').join()), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('entry disables empty searches and reacts to source changes',
      (tester) async {
    final lib = library()..sources = [];
    final client = CatalogClient(client: MockClient((_) async {
      throw StateError('No search should run');
    }));
    addTearDown(client.dispose);
    await tester.pumpWidget(MaterialApp(
        home: Scaffold(body: SearchPage(library: lib, client: client))));
    TextButton button() =>
        tester.widget<TextButton>(find.widgetWithText(TextButton, '搜索'));
    expect(button().onPressed, isNull);
    await tester.enterText(find.byType(TextField), '关键词');
    await tester.pump();
    expect(button().onPressed, isNull);
    expect(find.text('没有启用的源，请在“设置”中启用或添加。'), findsOneWidget);
    lib.sources = library().sources;
    lib.notifyListeners();
    await tester.pump();
    expect(button().onPressed, isNotNull);
    expect(find.text('没有启用的源，请在“设置”中启用或添加。'), findsNothing);
    await tester.tap(find.byTooltip('清空'));
    await tester.pump();
    expect(button().onPressed, isNull);
    expect(find.byType(SearchResultsPage), findsNothing);
  });

  testWidgets('returning from pending results ignores late responses',
      (tester) async {
    final pending = Completer<http.Response>();
    final client = CatalogClient(client: MockClient((_) => pending.future));
    addTearDown(client.dispose);
    final lib = library()..sources = [library().sources.first];
    await tester.pumpWidget(MaterialApp(
        home: Scaffold(body: SearchPage(library: lib, client: client))));
    await tester.enterText(find.byType(TextField), '未完成');
    await tester.pump();
    await tester.tap(find.widgetWithText(TextButton, '搜索'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 350));
    await tester.pump();
    await tester.pageBack();
    await tester.pumpAndSettle();
    await tester.runAsync(() async {
      pending.complete(response('未完成'));
      await Future<void>.delayed(const Duration(milliseconds: 30));
    });
    await tester.pumpAndSettle();
    expect(find.byType(SearchResultsPage), findsNothing);
    expect(find.byType(EntryList), findsNothing);
    expect(lib.searchHistory, ['未完成']);
    expect(tester.takeException(), isNull);
  });

  testWidgets('entry and results follow English locale and large system text',
      (tester) async {
    tester.view.physicalSize = const Size(320, 700);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final client =
        CatalogClient(client: MockClient((_) async => response('现在就出发')));
    addTearDown(client.dispose);
    await tester.pumpWidget(MaterialApp(
        locale: const Locale('en'),
        supportedLocales: appLocales,
        localizationsDelegates: appLocalizationsDelegates,
        builder: (context, child) => MediaQuery(
            data: MediaQuery.of(context)
                .copyWith(textScaler: TextScaler.linear(2)),
            child: child!),
        home: Scaffold(body: SearchPage(library: library(), client: client))));
    expect(find.text('Search movies, series, anime'), findsOneWidget);
    await tester.enterText(find.byType(TextField), '现在就出发');
    await tester.pump();
    await tester.tap(find.widgetWithText(TextButton, 'Search'));
    await tester.pump();
    await tester.runAsync(() async {
      await Future<void>.delayed(const Duration(milliseconds: 30));
    });
    await tester.pumpAndSettle();
    expect(find.byType(SearchResultsPage), findsOneWidget);
    expect(find.text('Search results'), findsWidgets);
    expect(
        find.descendant(
            of: find.byType(EntryList), matching: find.text('现在就出发')),
        findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
