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

final class _NoWrites extends SharedPreferencesAsyncPlatform {
  @override
  dynamic noSuchMethod(Invocation invocation) =>
      throw StateError('Unexpected persistence');
}

void main() {
  setUp(() => SharedPreferencesAsyncPlatform.instance = _NoWrites());
  Library library() => Library(SharedPreferencesAsync())
    ..sources = [
      const SourceEndpoint(name: 'test', url: 'https://example.com/api')
    ];
  const entry =
      MediaEntry(id: 'test:42', remoteId: '42', title: 'Title', source: 'test');
  String body() => jsonEncode({
        'list': [
          {
            'vod_id': 42,
            'vod_name': 'Title',
            'vod_content': 'Full description',
            'vod_play_from': r'A$$$B',
            'vod_play_url':
                r'ep1$https://example.com/1.m3u8$$$ep2$https://example.com/2.m3u8',
          }
        ]
      });

  testWidgets('detail loads selectable episodes from the configured source',
      (tester) async {
    final response = Completer<http.Response>();
    final client =
        CatalogClient(client: MockClient((request) => response.future));
    addTearDown(client.dispose);
    await tester.pumpWidget(MaterialApp(
        home: DetailPage(entry: entry, library: library(), client: client)));
    expect(find.byType(LinearProgressIndicator), findsOneWidget);
    await tester.runAsync(() async {
      response.complete(http.Response(body(), 200));
      await Future<void>.delayed(const Duration(milliseconds: 20));
    });
    await tester.pumpAndSettle();
    expect(find.text('Full description'), findsOneWidget);
    expect(find.text('ep1'), findsOneWidget);
    expect(find.text('ep2'), findsOneWidget);
    expect(find.byType(LinearProgressIndicator), findsNothing);
  });

  testWidgets('detail failure is retryable without losing existing episodes',
      (tester) async {
    var attempts = 0;
    final client = CatalogClient(
        client: MockClient((_) async => ++attempts == 1
            ? http.Response('', 503)
            : http.Response(body(), 200)));
    addTearDown(client.dispose);
    const existing = MediaEntry(
        id: 'test:42',
        remoteId: '42',
        title: 'Title',
        source: 'test',
        lines: {
          'old': [
            Episode(name: 'cached', url: 'https://example.com/cached.mp4')
          ]
        });
    await tester.pumpWidget(MaterialApp(
        home: DetailPage(entry: existing, library: library(), client: client)));
    await tester
        .runAsync(() => Future<void>.delayed(const Duration(milliseconds: 20)));
    await tester.pumpAndSettle();
    expect(find.text('cached'), findsOneWidget);
    await tester.tap(find.text('重试详情'));
    await tester
        .runAsync(() => Future<void>.delayed(const Duration(milliseconds: 20)));
    await tester.pumpAndSettle();
    expect(find.text('ep1'), findsOneWidget);
    expect(find.text('cached'), findsNothing);
  });

  testWidgets(
      'leaving detail before the response does not update disposed state',
      (tester) async {
    final response = Completer<http.Response>();
    final client = CatalogClient(client: MockClient((_) => response.future));
    addTearDown(client.dispose);
    await tester.pumpWidget(MaterialApp(
        home: DetailPage(entry: entry, library: library(), client: client)));
    await tester.pumpWidget(const MaterialApp(home: SizedBox()));
    response.complete(http.Response(body(), 200));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
  });
}
