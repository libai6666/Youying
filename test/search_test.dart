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

final class _NoStorage extends SharedPreferencesAsyncPlatform {
  @override
  dynamic noSuchMethod(Invocation invocation) => throw StateError('No writes');
}

void main() {
  setUp(() => SharedPreferencesAsyncPlatform.instance = _NoStorage());
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
    await tester.pumpWidget(MaterialApp(
        home: Scaffold(body: SearchPage(library: library(), client: client))));
    await tester.enterText(find.byType(TextField), '共同电影');
    await tester.runAsync(() async {
      await tester.tap(find.byTooltip('搜索'));
      await Future<void>.delayed(const Duration(milliseconds: 30));
    });
    await tester.pumpAndSettle();
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
    await tester.tap(find.byTooltip('搜索'));
    await tester.pump();
    await tester.enterText(find.byType(TextField), 'new');
    await tester.runAsync(() async {
      await tester.tap(find.byTooltip('搜索'));
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
    await tester.tap(find.byTooltip('搜索'));
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
}
