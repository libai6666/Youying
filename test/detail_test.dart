import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:shared_preferences_platform_interface/shared_preferences_async_platform_interface.dart';
import 'package:youying/catalog.dart';
import 'package:youying/library.dart';
import 'package:youying/main.dart';
import 'package:youying/player.dart';

final class _NoWrites extends SharedPreferencesAsyncPlatform {
  @override
  dynamic noSuchMethod(Invocation invocation) =>
      throw StateError('Unexpected persistence');
}

void main() {
  setUp(() => TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(MediaController.methods, (_) async {
        throw PlatformException(code: 'test-no-native-player');
      }));
  tearDown(() => TestDefaultBinaryMessengerBinding
      .instance.defaultBinaryMessenger
      .setMockMethodCallHandler(MediaController.methods, null));
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

  for (final width in [320.0, 390.0, 1280.0]) {
    testWidgets('embedded detail fits $width width and larger text',
        (tester) async {
      tester.view.devicePixelRatio = 1;
      tester.view.physicalSize = Size(width, 844);
      addTearDown(tester.view.resetDevicePixelRatio);
      addTearDown(tester.view.resetPhysicalSize);
      final client = CatalogClient(
          client: MockClient((_) async => http.Response(body(), 200)));
      addTearDown(client.dispose);
      await tester.pumpWidget(MaterialApp(
          builder: (_, child) => PhoneViewport(
              child: MediaQuery.withClampedTextScaling(
                  minScaleFactor: 1.4, maxScaleFactor: 1.4, child: child!)),
          home: DetailPage(entry: entry, library: library(), client: client)));
      await tester.runAsync(
          () => Future<void>.delayed(const Duration(milliseconds: 20)));
      await tester.pumpAndSettle();
      await tester.scrollUntilVisible(find.text('Full description'), 200,
          scrollable: find.byType(Scrollable).first);
      expect(tester.takeException(), isNull);
    });
  }

  testWidgets('detail loads selectable episodes from the configured source',
      (tester) async {
    final response = Completer<http.Response>();
    final client =
        CatalogClient(client: MockClient((request) => response.future));
    addTearDown(client.dispose);
    await tester.pumpWidget(MaterialApp(
        home: DetailPage(entry: entry, library: library(), client: client)));
    expect(find.text('正在加载播放资源…'), findsOneWidget);
    expect(find.byType(CircularProgressIndicator), findsOneWidget);
    expect(find.byType(ChoiceChip), findsNothing);
    expect(find.text('播放来源'), findsNothing);
    final videoPosition =
        tester.getTopLeft(find.byKey(const ValueKey('detail-video')));
    await tester.runAsync(() async {
      response.complete(http.Response(body(), 200));
      await Future<void>.delayed(const Duration(milliseconds: 20));
    });
    await tester.pumpAndSettle();
    expect(find.byType(PlayerPage), findsOneWidget);
    expect(tester.getTopLeft(find.byKey(const ValueKey('detail-video'))),
        videoPosition);
    expect(find.text('正在加载播放资源…'), findsNothing);
    expect(find.text('ep1'), findsOneWidget);
    expect(find.text('ep2'), findsNothing);
    await tester.ensureVisible(find.byTooltip('切换线路'));
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('切换线路'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('B'));
    await tester.pumpAndSettle();
    expect(find.text('ep2'), findsOneWidget);
    await tester.scrollUntilVisible(find.text('Full description'), 300,
        scrollable: find.byType(Scrollable).first);
    expect(find.text('Full description'), findsOneWidget);
    expect(find.byType(LinearProgressIndicator), findsNothing);
  });

  testWidgets(
      'known playable episodes appear immediately while details refresh without replacing the player',
      (tester) async {
    final response = Completer<http.Response>();
    final client = CatalogClient(client: MockClient((_) => response.future));
    addTearDown(client.dispose);
    const cached = MediaEntry(
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
        home: DetailPage(entry: cached, library: library(), client: client)));
    expect(find.byType(PlayerPage), findsOneWidget);
    expect(find.text('cached'), findsOneWidget);
    expect(find.text('正在加载播放资源…'), findsNothing);
    final player = tester.state(find.byType(PlayerPage));
    await tester.runAsync(() async {
      response.complete(http.Response(body(), 200));
      await Future<void>.delayed(const Duration(milliseconds: 20));
    });
    await tester.pumpAndSettle();
    expect(tester.state(find.byType(PlayerPage)), same(player));
    expect(find.text('ep1'), findsOneWidget);
    expect(find.text('cached'), findsNothing);
  });

  testWidgets('immediate playback still selects the last watched episode',
      (tester) async {
    const episode = Episode(name: 'ep2', url: 'https://example.com/2.mp4');
    const cached =
        MediaEntry(id: 'test:42', title: 'Title', source: 'test', lines: {
      'old': [Episode(name: 'ep1', url: 'https://example.com/1.mp4'), episode]
    });
    final saved = library();
    saved.positionsMs[Library.episodeKey(cached.id, episode)] = 30000;
    await tester.pumpWidget(
        MaterialApp(home: DetailPage(entry: cached, library: saved)));
    expect(tester.widget<PlayerPage>(find.byType(PlayerPage)).initial, episode);
    expect(find.text('正在加载播放资源…'), findsNothing);
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
  });

  testWidgets('initial resource failure stays in the video area and can retry',
      (tester) async {
    final first = Completer<http.Response>();
    final second = Completer<http.Response>();
    var attempts = 0;
    final client = CatalogClient(
        client:
            MockClient((_) => ++attempts == 1 ? first.future : second.future));
    addTearDown(client.dispose);
    await tester.pumpWidget(MaterialApp(
        home: DetailPage(entry: entry, library: library(), client: client)));
    final videoPosition =
        tester.getTopLeft(find.byKey(const ValueKey('detail-video')));
    await tester.runAsync(() async {
      first.complete(http.Response('', 503));
      await Future<void>.delayed(const Duration(milliseconds: 20));
    });
    await tester.pumpAndSettle();
    expect(find.text('播放资源加载失败，请重试或换源'), findsOneWidget);
    expect(find.byType(PlayerPage), findsNothing);
    await tester.tap(find.text('重试详情'));
    await tester.pump();
    expect(find.text('正在加载播放资源…'), findsOneWidget);
    expect(find.text('播放来源'), findsNothing);
    await tester.runAsync(() async {
      second.complete(http.Response(body(), 200));
      await Future<void>.delayed(const Duration(milliseconds: 20));
    });
    await tester.pumpAndSettle();
    expect(find.text('ep1'), findsOneWidget);
    expect(tester.getTopLeft(find.byKey(const ValueKey('detail-video'))),
        videoPosition);
    expect(tester.takeException(), isNull);
  });

  testWidgets(
      'empty episode results show a video-area fallback instead of an inert player',
      (tester) async {
    final client = CatalogClient(
        client: MockClient((_) async => http.Response(
            jsonEncode({
              'list': [
                {'vod_id': 42, 'vod_name': 'Title'}
              ]
            }),
            200)));
    addTearDown(client.dispose);
    await tester.pumpWidget(MaterialApp(
        home: DetailPage(entry: entry, library: library(), client: client)));
    await tester
        .runAsync(() => Future<void>.delayed(const Duration(milliseconds: 20)));
    await tester.pumpAndSettle();
    expect(find.text('当前来源暂无可播放视频，请换源'), findsOneWidget);
    expect(find.byType(PlayerPage), findsNothing);
    expect(find.text('换源'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  for (final width in [320.0, 1280.0]) {
    testWidgets('video loading and failure fit $width width with larger text',
        (tester) async {
      tester.view.devicePixelRatio = 1;
      tester.view.physicalSize = Size(width, 844);
      addTearDown(tester.view.resetDevicePixelRatio);
      addTearDown(tester.view.resetPhysicalSize);
      final response = Completer<http.Response>();
      final client = CatalogClient(client: MockClient((_) => response.future));
      addTearDown(client.dispose);
      await tester.pumpWidget(MaterialApp(
          builder: (_, child) => PhoneViewport(
              child: MediaQuery.withClampedTextScaling(
                  minScaleFactor: 1.4, maxScaleFactor: 1.4, child: child!)),
          home: DetailPage(entry: entry, library: library(), client: client)));
      expect(find.text('正在加载播放资源…'), findsOneWidget);
      expect(tester.takeException(), isNull);
      await tester.runAsync(() async {
        response.complete(http.Response('', 503));
        await Future<void>.delayed(const Duration(milliseconds: 20));
      });
      await tester.pumpAndSettle();
      expect(find.text('播放资源加载失败，请重试或换源'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });
  }

  testWidgets('video source picker discovers and switches catalog sources',
      (tester) async {
    final data = jsonDecode(body()) as Map;
    (data['list'] as List)
        .first
        .addAll({'type_name': '电视剧', 'vod_year': '2026'});
    final response = jsonEncode(data);
    final client = CatalogClient(
        client: MockClient(
            (_) async => http.Response.bytes(utf8.encode(response), 200)));
    addTearDown(client.dispose);
    final saved = library()
      ..sources = [
        const SourceEndpoint(name: 'test', url: 'https://example.com/api'),
        const SourceEndpoint(name: 'other', url: 'https://example.org/api'),
      ];
    await tester.pumpWidget(MaterialApp(
        home: DetailPage(entry: entry, library: saved, client: client)));
    await tester
        .runAsync(() => Future<void>.delayed(const Duration(milliseconds: 20)));
    await tester.pumpAndSettle();
    expect(find.byTooltip('详情介绍'), findsOneWidget);
    await tester.tap(find.byTooltip('详情介绍'));
    await tester.pumpAndSettle();
    expect(
        find.descendant(
            of: find.byType(BottomSheet),
            matching: find.text('Full description')),
        findsOneWidget);
    await tester.tapAt(const Offset(10, 10));
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('换源'));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(ListTile, '查找更多播放源'));
    await tester
        .runAsync(() => Future<void>.delayed(const Duration(milliseconds: 20)));
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('换源'));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(ListTile, 'other'));
    await tester
        .runAsync(() => Future<void>.delayed(const Duration(milliseconds: 20)));
    await tester.pumpAndSettle();
    await tester.scrollUntilVisible(
        find.widgetWithText(ChoiceChip, 'other'), 200,
        scrollable: find.byType(Scrollable).first);
    expect(
        tester
            .widget<ChoiceChip>(find.widgetWithText(ChoiceChip, 'other'))
            .selected,
        isTrue);
    await tester.scrollUntilVisible(find.text('Full description'), 200,
        scrollable: find.byType(Scrollable).first);
    expect(find.text('Full description'), findsWidgets);
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
    await tester.scrollUntilVisible(find.text('重试详情'), 200,
        scrollable: find.byType(Scrollable).first);
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
