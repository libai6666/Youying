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
import 'package:youying/offline_downloads.dart';
import 'package:youying/player.dart';
import 'package:youying/ui_locale.dart';

final class _MemoryWrites extends SharedPreferencesAsyncPlatform {
  bool failWrites = false;
  @override
  dynamic noSuchMethod(Invocation invocation) {
    if (invocation.memberName == #setString ||
        invocation.memberName == #setBool) {
      if (failWrites) return Future<void>.error(StateError('save failed'));
      return Future<void>.value();
    }
    throw StateError('Unexpected preference access: ${invocation.memberName}');
  }
}

const _episodes = [
  Episode(name: '第1集', url: 'https://example.com/1.mp4'),
  Episode(name: '第2集', url: 'https://example.com/2.mp4'),
];
const _entry = MediaEntry(
    id: 'test:movie',
    remoteId: 'movie',
    title: '测试剧集',
    source: 'test',
    lines: {'主线路': _episodes});

MediaEntry _series({bool alternative = false}) =>
    MediaEntry(id: 'test:series', title: '长篇测试剧集', source: 'test', lines: {
      '主线路': List.generate(
          195,
          (index) => Episode(
              name: '第${index + 1}集',
              url: 'https://example.com/series/${index + 1}.mp4')),
      if (alternative) '备用线路': _episodes,
    });

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  test('the next episode stays on the current line and stops at the end', () {
    expect(nextEpisodeOnLine(_entry.lines, '主线路', _episodes.first),
        _episodes.last);
    expect(nextEpisodeOnLine(_entry.lines, '主线路', _episodes.last), isNull);
    expect(nextEpisodeOnLine(_entry.lines, 'missing', _episodes.first), isNull);
  });

  test('long-press scrub is bounded to the video duration', () {
    expect(scrubPositionMs(30000, 35, 120000), 65000);
    expect(scrubPositionMs(30000, -99, 120000), 0);
    expect(scrubPositionMs(30000, 999, 120000), 120000);
  });

  final messenger =
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
  final calls = <MethodCall>[];
  late Library library;
  var nextTextureId = 1;

  setUp(() {
    SharedPreferencesAsyncPlatform.instance = _MemoryWrites();
    library = Library(SharedPreferencesAsync());
    calls.clear();
    nextTextureId = 1;
    messenger.setMockMethodCallHandler(MediaController.methods, (call) async {
      calls.add(call);
      return null;
    });
    messenger.setMockMethodCallHandler(
        const MethodChannel('flutter_player_av/events'), (_) async => null);
    messenger.setMockMethodCallHandler(SystemChannels.platform_views,
        (call) async {
      if (call.method == 'create') return nextTextureId++;
      if (call.method == 'resize') {
        final dimensions = call.arguments as Map;
        return {'width': dimensions['width'], 'height': dimensions['height']};
      }
      return null;
    });
    messenger.setMockMethodCallHandler(
        SystemChannels.platform, (_) async => null);
  });

  tearDown(() {
    messenger.setMockMethodCallHandler(MediaController.methods, null);
    messenger.setMockMethodCallHandler(
        const MethodChannel('flutter_player_av/events'), null);
    messenger.setMockMethodCallHandler(SystemChannels.platform_views, null);
    messenger.setMockMethodCallHandler(SystemChannels.platform, null);
    playerFullscreenViewport.value = false;
  });

  Future<void> mount(WidgetTester tester,
      {bool showDetails = false,
      bool preferOffline = false,
      MediaEntry entry = _entry,
      Episode? initial,
      bool english = false,
      double width = 390,
      double textScale = 1}) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = Size(width, 844);
    addTearDown(tester.view.resetDevicePixelRatio);
    addTearDown(tester.view.resetPhysicalSize);
    await tester.pumpWidget(MaterialApp(
        locale: english ? const Locale('en', 'US') : null,
        supportedLocales: appLocales,
        localizationsDelegates: english ? appLocalizationsDelegates : null,
        builder: (_, child) => PhoneViewport(
            child: MediaQuery.withClampedTextScaling(
                minScaleFactor: textScale,
                maxScaleFactor: textScale,
                child: child!)),
        home: Scaffold(
            body: SingleChildScrollView(
                child: PlayerPage(
                    entry: entry,
                    initial: initial,
                    library: library,
                    preferOffline: preferOffline,
                    embedded: true,
                    onShowDetails: showDetails ? () {} : null)))));
    await tester.pumpAndSettle();
    expect(
        calls.where(
            (call) => call.method == (preferOffline ? 'openDownload' : 'open')),
        hasLength(1));
  }

  Future<void> emit(WidgetTester tester, String type, Object value) async {
    final id = (calls.firstWhere((call) => call.method == 'create').arguments
        as Map)['playerId'];
    final message = const StandardMethodCodec()
        .encodeSuccessEnvelope({'playerId': id, 'type': type, 'value': value});
    await messenger.handlePlatformMessage(
        'flutter_player_av/events', message, (_) {});
    await tester.pump();
  }

  bool selectedTile(WidgetTester tester, String key) =>
      tester
          .widget<Semantics>(find
              .descendant(
                  of: find.byKey(ValueKey(key)),
                  matching: find.byType(Semantics))
              .first)
          .properties
          .selected ==
      true;

  Future<void> finishEpisode(WidgetTester tester) async {
    await emit(tester, 'duration', 60000);
    await emit(tester, 'position', 59000);
    await emit(tester, 'completed', true);
  }

  for (final width in [320.0, 390.0, 1280.0]) {
    for (final scale in [1.4, 2.0]) {
      testWidgets('English player and picker fit $width at $scale',
          (tester) async {
        await mount(tester,
            english: true,
            width: width,
            textScale: scale,
            showDetails: true,
            entry: _series());
        expect(find.byTooltip('Details'), findsOneWidget);
        expect(find.text('第1集'), findsWidgets);
        expect(tester.takeException(), isNull);
        await tester.tap(find.text('All 195 episodes'));
        await tester.pumpAndSettle();
        expect(find.text('Oldest first'), findsOneWidget);
        expect(tester.takeException(), isNull);
        await tester.tap(find.byTooltip('Close episodes'));
        await tester.pumpAndSettle();
        await tester.tap(find.byTooltip('Download episodes').last);
        await tester.pumpAndSettle();
        expect(find.text('View downloads'), findsOneWidget);
        expect(tester.takeException(), isNull);
      });
    }
  }

  testWidgets('completed native task opens cache token without a network open',
      (tester) async {
    library.offline.tasks = [
      DownloadTask(
          id: 'cached-episode',
          entry: _entry,
          episode: _episodes.first,
          state: 'completed')
    ];
    await mount(tester, preferOffline: true);
    expect(calls.where((call) => call.method == 'open'), isEmpty);
    expect(calls.firstWhere((call) => call.method == 'openDownload').arguments,
        containsPair('downloadId', 'cached-episode'));
  });

  testWidgets(
      'download selection and list return to the same fullscreen player',
      (tester) async {
    await mount(tester);
    await tester.tap(find.byTooltip('全屏'));
    await tester.pumpAndSettle();
    tester.view.physicalSize = const Size(844, 390);
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('下载剧集').last);
    await tester.pumpAndSettle();
    expect(find.text('下载剧集'), findsOneWidget);
    expect(find.text('查看下载列表'), findsOneWidget);
    expect(playerFullscreenViewport.value, true);
    await tester.tap(find.text('查看下载列表'));
    await tester.pumpAndSettle();
    expect(find.text('我的下载'), findsOneWidget);
    await tester.pageBack();
    await tester.pumpAndSettle();
    expect(find.byTooltip('退出全屏'), findsWidgets);
    expect(playerFullscreenViewport.value, true);
    expect(calls.where((call) => call.method == 'create'), hasLength(1));
    expect(calls.where((call) => call.method == 'open'), hasLength(1));
  });

  testWidgets('episode preview is a compact horizontal list, not 195 buttons',
      (tester) async {
    await mount(tester, entry: _series());
    final strip = find.byKey(const ValueKey('episode-strip'));
    final list = tester.widget<ListView>(strip);
    expect(list.scrollDirection, Axis.horizontal);
    expect(find.byType(GridView), findsNothing);
    expect(find.text('第195集'), findsNothing);
    expect(tester.getSize(strip).height, 56);
    expect(selectedTile(tester, 'episode-strip-0'), true);
    await tester.timedDrag(
        strip, const Offset(-220, 0), const Duration(milliseconds: 600));
    await tester.pumpAndSettle();
    final scroll = tester.state<ScrollableState>(
        find.descendant(of: strip, matching: find.byType(Scrollable)));
    expect(scroll.position.pixels, greaterThan(0));
    expect(calls.where((call) => call.method == 'open'), hasLength(1));
  });

  testWidgets(
      'all episodes use two columns, reveal current, and select in place',
      (tester) async {
    final entry = _series();
    final episodes = entry.lines['主线路']!;
    await mount(tester, entry: entry, initial: episodes[137]);
    expect(selectedTile(tester, 'episode-strip-137'), true);
    await emit(tester, 'position', 38000);
    await tester.tap(find.byTooltip('全部剧集'));
    await tester.pumpAndSettle();
    final grid = find.byKey(const ValueKey('episode-grid'));
    final delegate = tester.widget<GridView>(grid).gridDelegate
        as SliverGridDelegateWithFixedCrossAxisCount;
    expect(delegate.crossAxisCount, 2);
    expect(selectedTile(tester, 'episode-grid-137'), true);
    await tester.tap(find.descendant(of: grid, matching: find.text('第139集')));
    await tester.pumpAndSettle();
    expect(find.byType(BottomSheet), findsNothing);
    expect(selectedTile(tester, 'episode-strip-138'), true);
    final opens = calls.where((call) => call.method == 'open').toList();
    expect(opens, hasLength(2));
    expect(opens.last.arguments, containsPair('url', episodes[138].url));
    expect(library.resumePosition(entry.id, episodes[137]), 38000);
    expect(calls.where((call) => call.method == 'create'), hasLength(1));
  });

  testWidgets('episode sort reverses display only and keeps the final boundary',
      (tester) async {
    final entry = _series();
    await mount(tester, entry: entry);
    await tester.tap(find.byTooltip('全部剧集'));
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('切换倒序'));
    await tester.pumpAndSettle();
    final grid = find.byKey(const ValueKey('episode-grid'));
    expect(find.descendant(of: grid, matching: find.text('第195集')),
        findsOneWidget);
    expect(nextEpisodeOnLine(entry.lines, '主线路', entry.lines['主线路']!.first),
        entry.lines['主线路']![1]);
    await tester.tap(find.descendant(of: grid, matching: find.text('第195集')));
    await tester.pumpAndSettle();
    expect(calls.lastWhere((call) => call.method == 'open').arguments,
        containsPair('url', entry.lines['主线路']!.last.url));
    await finishEpisode(tester);
    await tester.pumpAndSettle();
    expect(calls.where((call) => call.method == 'open'), hasLength(2));
    expect(find.text('本线路已播完'), findsOneWidget);
  });

  testWidgets(
      'open episode panel follows auto-next and closes without reopening',
      (tester) async {
    await mount(tester, entry: _series());
    await tester.tap(find.byTooltip('全部剧集'));
    await tester.pumpAndSettle();
    await finishEpisode(tester);
    await tester.pump(const Duration(seconds: 3));
    await tester.pumpAndSettle();
    expect(find.byType(BottomSheet), findsOneWidget);
    expect(selectedTile(tester, 'episode-grid-1'), true);
    await tester.tap(find.byTooltip('关闭全部剧集'));
    await tester.pumpAndSettle();
    expect(find.byType(BottomSheet), findsNothing);
    expect(calls.where((call) => call.method == 'open'), hasLength(2));
  });

  testWidgets('changing line replaces the preview and full episode list',
      (tester) async {
    final entry = _series(alternative: true);
    await mount(tester, entry: entry, initial: entry.lines['主线路']![137]);
    expect(find.byType(ChoiceChip), findsNothing);
    await tester.tap(find.byTooltip('切换线路'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('备用线路'));
    await tester.pumpAndSettle();
    expect(find.text('全部 2 集'), findsOneWidget);
    await tester.tap(find.byTooltip('全部剧集'));
    await tester.pumpAndSettle();
    final grid = find.byKey(const ValueKey('episode-grid'));
    expect(
        find.descendant(of: grid, matching: find.text('第1集')), findsOneWidget);
    expect(
        find.descendant(of: grid, matching: find.text('第2集')), findsOneWidget);
    expect(find.text('第138集'), findsNothing);
    expect(tester.takeException(), isNull);
  });

  for (final width in [320.0, 390.0, 1280.0]) {
    testWidgets('episode preview and panel fit $width width and 1.4x text',
        (tester) async {
      await mount(tester, entry: _series(), width: width, textScale: 1.4);
      await tester.tap(find.byTooltip('全部剧集'));
      await tester.pumpAndSettle();
      expect(tester.getSize(find.byKey(const ValueKey('episode-grid'))).width,
          lessThanOrEqualTo(480));
      expect(tester.takeException(), isNull);
      await tester.tap(find.byTooltip('关闭全部剧集'));
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
    });
  }

  testWidgets('controls live over video, toggle on tap, and offer speeds',
      (tester) async {
    await mount(tester);
    expect(find.byTooltip('全屏'), findsOneWidget);
    expect(find.byTooltip('播放下一集'), findsOneWidget);
    expect(find.byTooltip('下载剧集'), findsOneWidget);
    expect(find.byTooltip('收藏'), findsOneWidget);
    final video = tester.getRect(find.byType(AndroidView));
    await tester.tapAt(video.center);
    await tester.pump();
    expect(find.byTooltip('全屏'), findsNothing);
    await tester.tapAt(video.center);
    await tester.pump();
    await tester.tap(find.byTooltip('倍速'));
    await tester.pumpAndSettle();
    for (final speed in ['0.5x', '1.0x', '2.0x', '3.0x']) {
      expect(find.text(speed), findsWidgets);
    }
    await tester.tap(find.text('3.0x').last);
    await tester.pumpAndSettle();
    expect(calls.lastWhere((call) => call.method == 'setRate').arguments,
        containsPair('rate', 3.0));
  });

  testWidgets('right hold uses temporary 2x and drag seeks before restoring',
      (tester) async {
    await mount(tester);
    await tester.tap(find.byTooltip('倍速'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('0.5x').last);
    await tester.pumpAndSettle();
    await emit(tester, 'duration', 120000);
    await emit(tester, 'position', 30000);
    final bounds = tester.getRect(find.byType(AndroidView));
    final gesture =
        await tester.startGesture(Offset(bounds.right - 45, bounds.center.dy));
    await tester.pump(const Duration(milliseconds: 600));
    expect(calls.lastWhere((call) => call.method == 'setRate').arguments,
        containsPair('rate', 2.0));
    await gesture.moveBy(const Offset(-35, 0));
    await tester.pump();
    expect(find.text('00:00 / 02:00'), findsWidgets);
    await gesture.up();
    await tester.pump();
    expect(calls.lastWhere((call) => call.method == 'seek').arguments,
        containsPair('positionMs', 0));
    expect(calls.lastWhere((call) => call.method == 'setRate').arguments,
        containsPair('rate', 0.5));
  });

  testWidgets('cancelled hold restores speed without committing a seek',
      (tester) async {
    await mount(tester);
    final bounds = tester.getRect(find.byType(AndroidView));
    final gesture =
        await tester.startGesture(Offset(bounds.right - 45, bounds.center.dy));
    await tester.pump(const Duration(milliseconds: 600));
    await gesture.cancel();
    await tester.pump();
    expect(calls.lastWhere((call) => call.method == 'setRate').arguments,
        containsPair('rate', 1.0));
    expect(calls.where((call) => call.method == 'seek'), isEmpty);
  });

  testWidgets('next and completed event open one next episode, never wrap',
      (tester) async {
    await mount(tester);
    await finishEpisode(tester);
    expect(find.text('3 秒后播放下一集'), findsOneWidget);
    await emit(tester, 'completed', true);
    await tester.pump(const Duration(seconds: 2));
    expect(calls.where((call) => call.method == 'open'), hasLength(1));
    await tester.pump(const Duration(seconds: 1));
    await tester.pumpAndSettle();
    final opens = calls.where((call) => call.method == 'open').toList();
    expect(opens, hasLength(2));
    expect(opens.last.arguments, containsPair('url', _episodes.last.url));
    expect(opens.last.arguments, containsPair('startMs', 0));
    expect(find.byTooltip('播放下一集'), findsOneWidget);
    await finishEpisode(tester);
    await tester.pumpAndSettle();
    expect(calls.where((call) => call.method == 'open'), hasLength(2));
    final nextButton = tester.widget<IconButton>(find.ancestor(
        of: find.byTooltip('播放下一集'), matching: find.byType(IconButton)));
    expect(nextButton.onPressed, isNull);
    expect(find.text('本线路已播完'), findsOneWidget);
  });

  testWidgets('the next button selects the following episode at its start',
      (tester) async {
    await mount(tester);
    await emit(tester, 'position', 38000);
    await tester.tap(find.byTooltip('播放下一集'));
    await tester.pumpAndSettle();
    final opens = calls.where((call) => call.method == 'open').toList();
    expect(opens, hasLength(2));
    expect(opens.last.arguments, containsPair('url', _episodes.last.url));
    expect(opens.last.arguments, containsPair('startMs', 0));
    expect(library.resumePosition(_entry.id, _episodes.first), 38000);
  });

  testWidgets(
      'auto-next can be disabled and settings cancel a pending countdown',
      (tester) async {
    await mount(tester);
    await finishEpisode(tester);
    await library.setAutoPlayNext(false);
    await tester.pump(const Duration(seconds: 4));
    expect(calls.where((call) => call.method == 'open'), hasLength(1));
    expect(find.text('取消续播'), findsNothing);
    expect(find.byTooltip('重播'), findsOneWidget);
    expect(library.resumePosition(_entry.id, _episodes.first), 60000);
    await tester.tap(find.byTooltip('重播'));
    await tester.pump();
    await finishEpisode(tester);
    await tester.pump(const Duration(seconds: 4));
    expect(calls.where((call) => call.method == 'open'), hasLength(1));
    expect(find.text('3 秒后播放下一集'), findsNothing);
  });

  testWidgets(
      'a legacy finished episode stays at the end and advances after three seconds',
      (tester) async {
    library.positionsMs[Library.episodeKey(_entry.id, _episodes.first)] = 60000;
    await mount(tester);
    await emit(tester, 'completed', true);
    await emit(tester, 'duration', 60000);
    await emit(tester, 'position', 60000);
    await emit(tester, 'completed', true);
    expect(find.text('3 秒后播放下一集'), findsOneWidget);
    await tester.pump(const Duration(seconds: 2));
    expect(calls.where((call) => call.method == 'open'), hasLength(1));
    expect(calls.where((call) => call.method == 'seek'), isEmpty);
    expect(library.watchProgress(_entry.id, _episodes.first).percent, 100);
    await tester.pump(const Duration(seconds: 1));
    await tester.pumpAndSettle();
    expect(calls.where((call) => call.method == 'open'), hasLength(2));
  });

  testWidgets(
      'saved completion restores the end, cancel preserves it and explicit replay resets progress',
      (tester) async {
    await library.recordPlay(_entry,
        episode: _episodes.first,
        position: 60000,
        duration: 60000,
        completed: true);
    await mount(tester);
    expect(calls.firstWhere((call) => call.method == 'open').arguments,
        containsPair('startMs', 60000));
    expect(find.text('3 秒后播放下一集'), findsOneWidget);
    await tester.tap(find.text('取消续播'));
    await tester.pump(const Duration(seconds: 4));
    expect(calls.where((call) => call.method == 'open'), hasLength(1));
    expect(library.watchProgress(_entry.id, _episodes.first).completed, true);
    await tester.tap(find.byTooltip('重播'));
    await tester.pumpAndSettle();
    expect(library.watchProgress(_entry.id, _episodes.first).completed, false);
    expect(library.resumePosition(_entry.id, _episodes.first), 0);
  });

  testWidgets(
      'a partial episode in the last seconds is not mistaken for completion',
      (tester) async {
    library.positionsMs[Library.episodeKey(_entry.id, _episodes.first)] = 58000;
    await mount(tester);
    await emit(tester, 'duration', 60000);
    await emit(tester, 'position', 0);
    await emit(tester, 'playing', false);
    expect(library.resumePosition(_entry.id, _episodes.first), 58000);
    await emit(tester, 'position', 58000);
    await tester.pump(const Duration(seconds: 4));
    expect(find.text('取消续播'), findsNothing);
    expect(calls.where((call) => call.method == 'open'), hasLength(1));
    expect(calls.where((call) => call.method == 'seek'), isEmpty);
    expect(library.watchProgress(_entry.id, _episodes.first).percent, 96);
  });

  testWidgets(
      'failed progress persistence does not block playback or episode changes',
      (tester) async {
    final store = SharedPreferencesAsyncPlatform.instance as _MemoryWrites;
    store.failWrites = true;
    await mount(tester);
    await emit(tester, 'duration', 60000);
    await emit(tester, 'position', 30000);
    await tester.tap(find.byTooltip('播放下一集'));
    await tester.pumpAndSettle();
    expect(calls.where((call) => call.method == 'open'), hasLength(2));
    expect(find.text('播放地址不可用'), findsNothing);
    expect(tester.takeException(), isNull);
    store.failWrites = false;
    await emit(tester, 'duration', 60000);
    await emit(tester, 'position', 15000);
    expect(library.watchProgress(_entry.id, _episodes.last).percent, 25);
  });

  testWidgets('reopened completed episodes respect disabled auto-next',
      (tester) async {
    await library.setAutoPlayNext(false);
    await library.recordPlay(_entry,
        episode: _episodes.first, duration: 60000, completed: true);
    await mount(tester);
    await emit(tester, 'position', 0);
    await tester.pump(const Duration(seconds: 4));
    expect(find.byTooltip('重播'), findsOneWidget);
    expect(find.text('取消续播'), findsNothing);
    expect(calls.where((call) => call.method == 'open'), hasLength(1));
    expect(library.watchProgress(_entry.id, _episodes.first).percent, 100);
  });

  testWidgets('cancel keeps the completed episode and permits replay',
      (tester) async {
    await mount(tester);
    await finishEpisode(tester);
    await tester.tap(find.text('取消续播'));
    await tester.pump(const Duration(seconds: 4));
    expect(calls.where((call) => call.method == 'open'), hasLength(1));
    await tester.tap(find.byTooltip('重播'));
    await tester.pump();
    expect(calls.lastWhere((call) => call.method == 'seek').arguments,
        containsPair('positionMs', 0));
  });

  testWidgets('manual episode selection cancels the pending countdown',
      (tester) async {
    await mount(tester, entry: _series());
    await finishEpisode(tester);
    await tester.tap(find.byTooltip('全部剧集'));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('episode-grid-3')));
    await tester.pumpAndSettle();
    await tester.pump(const Duration(seconds: 4));
    final opens = calls.where((call) => call.method == 'open').toList();
    expect(opens, hasLength(2));
    expect(opens.last.arguments,
        containsPair('url', _series().lines['主线路']![3].url));
  });

  testWidgets(
      'switching lines cancels countdown and does not restore completed progress',
      (tester) async {
    await mount(tester, entry: _series(alternative: true));
    await finishEpisode(tester);
    await tester.tap(find.byTooltip('切换线路'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('备用线路'));
    await tester.pumpAndSettle();
    await tester.pump(const Duration(seconds: 4));
    final opens = calls.where((call) => call.method == 'open').toList();
    expect(opens, hasLength(2));
    expect(opens.last.arguments, containsPair('url', _episodes.first.url));
  });

  testWidgets('disposing cancels countdown and preserves completed progress',
      (tester) async {
    await mount(tester);
    await finishEpisode(tester);
    await tester.pumpWidget(const SizedBox());
    await tester.pump(const Duration(seconds: 4));
    expect(calls.where((call) => call.method == 'open'), hasLength(1));
    expect(library.resumePosition(_entry.id, _episodes.first), 60000);
    expect(tester.takeException(), isNull);
  });

  testWidgets('fullscreen shares the three-second next-episode countdown',
      (tester) async {
    await mount(tester);
    await tester.tap(find.byTooltip('全屏'));
    await tester.pumpAndSettle();
    await finishEpisode(tester);
    expect(find.text('3 秒后播放下一集'), findsOneWidget);
    await tester.pump(const Duration(seconds: 3));
    await tester.pumpAndSettle();
    expect(calls.where((call) => call.method == 'open'), hasLength(2));
    expect(playerFullscreenViewport.value, true);
    await tester.tap(find.byTooltip('退出全屏').first);
    await tester.pumpAndSettle();
  });

  testWidgets('favorite is available over the video', (tester) async {
    await mount(tester);
    await tester.tap(find.byTooltip('收藏'));
    await tester.pump();
    expect(library.isFavorite(_entry), true);
  });

  testWidgets('fullscreen reuses the player and releases the viewport clamp',
      (tester) async {
    await mount(tester);
    tester.view.physicalSize = const Size(900, 420);
    await tester.pump();
    await tester.tap(find.byTooltip('全屏'));
    await tester.pumpAndSettle();
    expect(playerFullscreenViewport.value, true);
    expect(find.byTooltip('退出全屏'), findsWidgets);
    expect(tester.getSize(find.byType(AndroidView)).width, greaterThan(480));
    expect(calls.where((call) => call.method == 'create'), hasLength(1));
    expect(calls.where((call) => call.method == 'open'), hasLength(1));
    await tester.tap(find.byTooltip('退出全屏').last);
    await tester.pumpAndSettle();
    expect(playerFullscreenViewport.value, false);
    expect(find.byTooltip('全屏'), findsOneWidget);
    expect(calls.where((call) => call.method == 'open'), hasLength(1));
  });

  testWidgets(
      'fullscreen episode panel selects another episode without exiting',
      (tester) async {
    final entry = _series();
    final episodes = entry.lines['主线路']!;
    await mount(tester, entry: entry, initial: episodes[137]);
    tester.view.physicalSize = const Size(900, 420);
    await tester.pump();
    await tester.tap(find.byTooltip('全屏'));
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('选集').last);
    await tester.pumpAndSettle();
    final grid = find.byKey(const ValueKey('episode-grid'));
    expect(find.byType(BottomSheet), findsOneWidget);
    expect(selectedTile(tester, 'episode-grid-137'), true);
    await tester.tap(find.descendant(of: grid, matching: find.text('第139集')));
    await tester.pumpAndSettle();
    expect(playerFullscreenViewport.value, true);
    expect(find.byTooltip('退出全屏'), findsWidgets);
    expect(tester.getSize(find.byType(AndroidView)).width, greaterThan(480));
    expect(calls.where((call) => call.method == 'create'), hasLength(1));
    final opens = calls.where((call) => call.method == 'open').toList();
    expect(opens, hasLength(2));
    expect(opens.last.arguments, containsPair('url', episodes[138].url));
    await tester.tap(find.byTooltip('仅一条线路').last);
    await tester.pump(const Duration(milliseconds: 250));
    expect(find.textContaining('当前只有一条播放线路'), findsOneWidget);
  });

  const firstSource = MediaEntry(
      id: 'alpha:42', remoteId: '42', title: '测试剧集', source: 'alpha');
  const secondSource =
      MediaEntry(id: 'beta:42', remoteId: '42', title: '测试剧集', source: 'beta');

  Future<void> mountSources(WidgetTester tester,
      {bool failSecond = false}) async {
    library.sources = [
      const SourceEndpoint(name: 'alpha', url: 'https://alpha.example/api'),
      const SourceEndpoint(name: 'beta', url: 'https://beta.example/api')
    ];
    final client = CatalogClient(client: MockClient((request) async {
      if (failSecond && request.url.host == 'beta.example') {
        return http.Response('', 503);
      }
      final delimiter = String.fromCharCode(36);
      final host = request.url.host;
      return http.Response.bytes(
          utf8.encode(jsonEncode({
            'list': [
              {
                'vod_id': 42,
                'vod_name': '测试剧集',
                'vod_play_from': 'jsm3u8',
                'vod_play_url':
                    '第1集${delimiter}https://$host/1.mp4#第2集${delimiter}https://$host/2.mp4'
              }
            ]
          })),
          200);
    }));
    addTearDown(client.dispose);
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(390, 844);
    addTearDown(tester.view.resetDevicePixelRatio);
    addTearDown(tester.view.resetPhysicalSize);
    await tester.pumpWidget(MaterialApp(
        builder: (_, child) => PhoneViewport(child: child!),
        home: DetailPage(
            entry: firstSource,
            variants: const [secondSource],
            library: library,
            client: client)));
    await tester
        .runAsync(() => Future<void>.delayed(const Duration(milliseconds: 20)));
    await tester.pumpAndSettle();
    expect(calls.where((call) => call.method == 'create'), hasLength(1));
    expect(calls.where((call) => call.method == 'open'), hasLength(1));
    tester.view.physicalSize = const Size(900, 420);
    await tester.pump();
    await tester.tap(find.byTooltip('全屏'));
    await tester.pumpAndSettle();
    expect(playerFullscreenViewport.value, true);
  }

  testWidgets('switching sources in fullscreen keeps the route and player',
      (tester) async {
    await mountSources(tester);
    await emit(tester, 'position', 38000);
    await tester.tap(find.byTooltip('换源').last);
    await tester.pumpAndSettle();
    expect(playerFullscreenViewport.value, true);
    expect(find.byType(BottomSheet), findsOneWidget);
    await tester.tap(find.widgetWithText(ListTile, 'beta'));
    await tester
        .runAsync(() => Future<void>.delayed(const Duration(milliseconds: 20)));
    await tester.pumpAndSettle();
    expect(find.byType(BottomSheet), findsNothing);
    expect(playerFullscreenViewport.value, true);
    expect(find.byTooltip('退出全屏'), findsWidgets);
    expect(tester.getSize(find.byType(AndroidView)).width, greaterThan(480));
    expect(calls.where((call) => call.method == 'create'), hasLength(1));
    expect(calls.where((call) => call.method == 'dispose'), isEmpty);
    final opens = calls.where((call) => call.method == 'open').toList();
    expect(opens, hasLength(2));
    expect(opens.last.arguments,
        containsPair('url', 'https://beta.example/1.mp4'));
    expect(opens.last.arguments, containsPair('startMs', 38000));
  });

  testWidgets('failed source lookup keeps the old fullscreen video',
      (tester) async {
    await mountSources(tester, failSecond: true);
    await tester.tap(find.byTooltip('换源').last);
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(ListTile, 'beta'));
    await tester
        .runAsync(() => Future<void>.delayed(const Duration(milliseconds: 20)));
    await tester.pumpAndSettle();
    expect(playerFullscreenViewport.value, true);
    expect(find.byTooltip('退出全屏'), findsWidgets);
    expect(calls.where((call) => call.method == 'open'), hasLength(1));
    expect(calls.where((call) => call.method == 'create'), hasLength(1));
    expect(calls.where((call) => call.method == 'dispose'), isEmpty);
    expect(tester.takeException(), isNull);
  });
}
