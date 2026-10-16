import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:shared_preferences_platform_interface/shared_preferences_async_platform_interface.dart';
import 'package:youying/catalog.dart';
import 'package:youying/download_widgets.dart';
import 'package:youying/library.dart';
import 'package:youying/main.dart';
import 'package:youying/offline_downloads.dart';
import 'package:youying/player.dart';

final class _PreferenceStub extends SharedPreferencesAsyncPlatform {
  @override
  dynamic noSuchMethod(Invocation invocation) {
    if (invocation.memberName == #setString) return Future<void>.value();
    throw StateError('Unexpected preferences call: ${invocation.memberName}');
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const channel = MethodChannel('test/offline/downloads');
  const events = EventChannel('test/offline/events');
  final first = Episode(name: '第01集', url: 'https://media.test/01.m3u8');
  final second = Episode(name: '第02集', url: 'https://media.test/02.m3u8');
  final third = Episode(name: '第03集', url: 'https://media.test/03.mp4');
  final entry = MediaEntry(id: 'test:1', title: '测试剧集', source: '测试', lines: {
    '普通线路': [first, second, third]
  });
  late OfflineDownloads offline;
  late Library library;
  late int parallelism;
  late List<Map<String, Object?>> enqueued;
  late List<(String, Object?)> commands;
  late List<Map<String, Object?>> tasks;

  setUp(() async {
    SharedPreferencesAsyncPlatform.instance = _PreferenceStub();
    parallelism = 3;
    enqueued = [];
    commands = [];
    tasks = [];
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
            const MethodChannel('test/offline/events'), (_) async => null);
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (call) async {
      if (call.method == 'initialize') {
        return {'parallelism': parallelism, 'tasks': tasks};
      }
      if (call.method == 'setParallelism') {
        parallelism = (call.arguments as Map)['value'] as int;
        return {'parallelism': parallelism, 'tasks': tasks};
      }
      if (call.method == 'enqueue') {
        enqueued.addAll(((call.arguments as Map)['items'] as List)
            .map((item) => Map<String, Object?>.from(item as Map)));
        return null;
      }
      commands.add((call.method, call.arguments));
      return null;
    });
    offline = OfflineDownloads(methods: channel, events: events);
    library = Library(SharedPreferencesAsync(), offline: offline);
    await offline.initialize();
  });

  tearDown(() {
    library.dispose();
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, null);
  });

  Future<void> restoreTasks() async {
    library.dispose();
    offline = OfflineDownloads(methods: channel, events: events);
    library = Library(SharedPreferencesAsync(), offline: offline);
    await offline.initialize();
  }

  Map<String, Object?> taskJson(String id, Episode episode, String state,
          {MediaEntry? media, int bytes = 1048576}) =>
      {
        'id': id,
        'entry': jsonEncode((media ?? entry).toJson()),
        'episodeName': episode.name,
        'url': episode.url,
        'state': state,
        'bytes': bytes,
        'total': 2097152,
        'percent': 50.0,
      };

  test('downloads group by media identity and source, not by title alone', () {
    final anotherSource =
        MediaEntry.fromJson({...entry.toJson(), 'source': '另一来源'});
    final anotherMovie =
        MediaEntry.fromJson({...entry.toJson(), 'id': 'test:2'});
    final groups = groupDownloads([
      DownloadTask(
          id: 'two',
          entry: entry,
          episode: second,
          state: 'downloading',
          bytes: 2097152),
      DownloadTask(
          id: 'one',
          entry: entry,
          episode: first,
          state: 'completed',
          bytes: 1048576),
      DownloadTask(
          id: 'other-source',
          entry: anotherSource,
          episode: first,
          state: 'completed',
          bytes: 10),
      DownloadTask(
          id: 'other-movie',
          entry: anotherMovie,
          episode: first,
          state: 'completed',
          bytes: 20),
    ]);
    expect(groups, hasLength(3));
    expect(groups.first.tasks.map((task) => task.id), ['one', 'two']);
    expect(groups.first.completedCount, 1);
    expect(groups.first.bytes, 3145728);
    expect(groups.map((group) => group.id).toSet(), hasLength(3));
  });

  test('grouping handles empty queues and orders episodes without saved lines',
      () {
    expect(groupDownloads([]), isEmpty);
    final media = MediaEntry.fromJson({...entry.toJson(), 'lines': {}});
    final groups = groupDownloads([
      DownloadTask(
          id: 'two',
          entry: media,
          episode: second,
          state: 'completed',
          bytes: -1),
      DownloadTask(
          id: 'one',
          entry: media,
          episode: first,
          state: 'completed',
          bytes: 1024),
    ]);
    expect(groups.single.tasks.map((task) => task.id), ['one', 'two']);
    expect(groups.single.bytes, 1024);
  });

  test('default parallelism, bounds and native persistence contract', () async {
    expect(offline.parallelism, 3);
    await offline.setParallelism(10);
    expect(parallelism, 10);
    expect(offline.parallelism, 10);
    await expectLater(offline.setParallelism(0), throwsFormatException);
    await expectLater(offline.setParallelism(11), throwsFormatException);
  });

  test(
      'download rejects insecure addresses and injected headers before queueing',
      () async {
    await expectLater(
        offline.enqueue(entry,
            [const Episode(name: '非法', url: 'http://media.test/video.mp4')]),
        throwsFormatException);
    await expectLater(
        offline.enqueue(entry, [first],
            headers: {'Referer': 'https://media.test\r\nBad: header'}),
        throwsFormatException);
    expect(enqueued, isEmpty);
  });

  testWidgets('download selection fits narrow large-text phones',
      (tester) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(320, 640);
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(MaterialApp(
        builder: (context, child) => MediaQuery(
            data: MediaQuery.of(context)
                .copyWith(textScaler: TextScaler.linear(1.4)),
            child: child!),
        home: Scaffold(
            body: DownloadEpisodeSheet(
                entry: entry,
                episodes: entry.lines['普通线路']!,
                current: first,
                library: library))));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    expect(find.text('查看下载列表'), findsOneWidget);
  });

  test('batch enqueues selected episodes once without storing metadata in logs',
      () async {
    await offline.enqueue(entry, [first, second, first]);
    expect(enqueued, hasLength(2));
    expect(enqueued.map((e) => e['url']), [first.url, second.url]);
    expect((jsonDecode(enqueued.first['entry'] as String) as Map)['title'],
        '测试剧集');
    expect(enqueued.first['episodeName'], '第01集');
    expect(enqueued.first['headers'], isEmpty);
  });

  test('completed download is returned as native offline token', () async {
    final task = {
      'id': 'sample',
      'entry': jsonEncode(entry.toJson()),
      'episodeName': first.name,
      'url': first.url,
      'state': 'completed',
      'bytes': 8000,
      'total': 8000,
      'percent': 100.0,
    };
    tasks.add(task);
    final restored = OfflineDownloads(methods: channel, events: events);
    await restored.initialize();
    final stored = Library(SharedPreferencesAsync(), offline: restored);
    expect(stored.downloadedFile(entry.id, first), 'media3:sample');
    await restored.enqueue(entry, [first, second]);
    expect(enqueued.map((item) => item['url']), [second.url]);
    stored.dispose();
  });

  test(
      'DRM and unsupported HLS errors are distinct, not misreported as emulator failures',
      () {
    final drm = DownloadTask.fromJson({
      'id': 'one',
      'entry': jsonEncode(entry.toJson()),
      'episodeName': first.name,
      'url': first.url,
      'state': 'failed',
      'error': 'DRM_OFFLINE_LICENSE_REQUIRED'
    });
    final sampleAes = DownloadTask.fromJson({
      'id': 'two',
      'entry': jsonEncode(entry.toJson()),
      'episodeName': second.name,
      'url': second.url,
      'state': 'failed',
      'error': 'HLS_ENCRYPTION_UNSUPPORTED'
    });
    expect(drm.failureMessage, contains('离线许可'));
    expect(sampleAes.failureMessage, contains('采样加密'));
  });

  testWidgets(
      'multi-episode sheet defaults to current episode and supports all start',
      (tester) async {
    await tester.pumpWidget(MaterialApp(
        home: Scaffold(
            body: Builder(
                builder: (context) => ElevatedButton(
                    onPressed: () => showModalBottomSheet<bool>(
                        context: context,
                        isScrollControlled: true,
                        builder: (_) => DownloadEpisodeSheet(
                            entry: entry,
                            episodes: entry.lines['普通线路']!,
                            current: second,
                            library: library)),
                    child: const Text('打开下载'))))));
    await tester.tap(find.text('打开下载'));
    await tester.pumpAndSettle();
    expect(find.text('下载剧集'), findsOneWidget);
    expect(
        find.byKey(ValueKey('download-episode-${third.url}')), findsOneWidget);
    expect(find.text('下载 1 集'), findsOneWidget);
    await tester.tap(find.text('全选'));
    await tester.pump();
    expect(find.text('全部开始'), findsOneWidget);
    await tester.runAsync(() async {
      await tester.tap(find.text('全部开始'));
      await Future<void>.delayed(Duration.zero);
    });
    await tester.pumpAndSettle();
    expect(enqueued.map((e) => e['url']), [first.url, second.url, third.url]);
    expect(find.textContaining('已加入 3 集'), findsOneWidget);
    await tester.tap(find.text('查看下载列表'));
    await tester.pumpAndSettle();
    expect(find.text('下载剧集'), findsNothing);
  });

  testWidgets('download list exposes progress, retry and pause actions',
      (tester) async {
    tasks.addAll([
      {
        'id': 'downloading',
        'entry': jsonEncode(entry.toJson()),
        'episodeName': first.name,
        'url': first.url,
        'state': 'downloading',
        'bytes': 1024,
        'total': 2048,
        'percent': 50.0,
      },
      {
        'id': 'failed',
        'entry': jsonEncode(entry.toJson()),
        'episodeName': second.name,
        'url': second.url,
        'state': 'failed',
        'bytes': 256,
        'total': 2048,
        'percent': 12.5,
        'error': 'DRM_OFFLINE_LICENSE_REQUIRED',
      }
    ]);
    library.dispose();
    offline = OfflineDownloads(methods: channel, events: events);
    library = Library(SharedPreferencesAsync(), offline: offline);
    await offline.initialize();
    await tester.pumpWidget(
        MaterialApp(home: Scaffold(body: DownloadsView(library: library))));
    expect(find.text('测试剧集'), findsOneWidget);
    expect(find.text('测试剧集 第01集'), findsNothing);
    await tester.tap(find.text('测试剧集'));
    await tester.pumpAndSettle();
    expect(find.text('下载中 · 1.0 KB / 2.0 KB'), findsOneWidget);
    expect(find.textContaining('离线许可'), findsOneWidget);
    await tester.tap(find.byTooltip('管理第01集'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('暂停'));
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('管理第02集'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('重试'));
    await tester.pumpAndSettle();
    expect(commands.map((e) => e.$1), ['pause', 'retry']);
  });

  testWidgets('group summary counts cached episodes and keeps sources separate',
      (tester) async {
    final other = MediaEntry.fromJson(
        {...entry.toJson(), 'id': 'other:1', 'source': '另一来源'});
    tasks.addAll([
      taskJson('second', second, 'completed', bytes: 2097152),
      taskJson('first', first, 'completed'),
      taskJson('other', first, 'completed', media: other),
    ]);
    await restoreTasks();
    await tester.pumpWidget(MaterialApp(home: DownloadsPage(library: library)));
    expect(find.text('测试剧集'), findsNWidgets(2));
    expect(find.text('已缓存 2 集 · 3.0 MB'), findsOneWidget);
    expect(find.text('已缓存 1 集 · 1.0 MB'), findsOneWidget);
    expect(find.byType(Card), findsNothing);
    await tester.tap(find.byKey(
        ValueKey('download-group-${groupDownloads(offline.tasks).first.id}')));
    await tester.pumpAndSettle();
    expect(find.text('测试剧集 第01集'), findsOneWidget);
    expect(find.text('测试剧集 第02集'), findsOneWidget);
    expect(find.byKey(const ValueKey('download-task-other')), findsNothing);
    expect(
        tester.getTopLeft(find.byKey(const ValueKey('download-task-first'))).dy,
        lessThan(tester
            .getTopLeft(find.byKey(const ValueKey('download-task-second')))
            .dy));
    expect(find.byType(LinearProgressIndicator), findsNothing);
  });

  testWidgets(
      'group filters keep mixed-state series visible and filter detail episodes',
      (tester) async {
    tasks.addAll([
      taskJson('first', first, 'completed'),
      taskJson('second', second, 'paused')
    ]);
    await restoreTasks();
    await tester.pumpWidget(MaterialApp(home: DownloadsPage(library: library)));
    await tester.tap(find.text('正在下载'));
    await tester.pump();
    expect(find.text('测试剧集'), findsOneWidget);
    expect(find.text('已缓存 1 集 · 2.0 MB'), findsOneWidget);
    await tester.tap(find.text('测试剧集'));
    await tester.pumpAndSettle();
    expect(find.text('测试剧集 第01集'), findsNothing);
    expect(find.text('测试剧集 第02集'), findsOneWidget);
    await tester.tap(find.text('已完成'));
    await tester.pump();
    expect(find.text('测试剧集 第01集'), findsOneWidget);
    expect(find.text('测试剧集 第02集'), findsNothing);
  });

  testWidgets(
      'episode management continues and deletes only the selected task with confirmation',
      (tester) async {
    tasks.addAll([
      taskJson('first', first, 'completed'),
      taskJson('second', second, 'paused')
    ]);
    await restoreTasks();
    await tester.pumpWidget(MaterialApp(home: DownloadsPage(library: library)));
    await tester.tap(find.text('测试剧集'));
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('管理第02集'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('继续'));
    await tester.pumpAndSettle();
    expect(commands.single.$1, 'resume');
    expect(commands.single.$2, {'id': 'second'});
    await tester.tap(find.byTooltip('管理第01集'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('删除'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('取消'));
    await tester.pumpAndSettle();
    expect(commands, hasLength(1));
    await tester.tap(find.byTooltip('管理第01集'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('删除'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('删除'));
    await tester.pumpAndSettle();
    expect(commands.last.$1, 'remove');
    expect(commands.last.$2, {'id': 'first'});
    tasks.removeWhere((task) => task['id'] == 'first');
    await tester.runAsync(() => offline.setParallelism(3));
    await tester.pumpAndSettle();
    expect(find.text('测试剧集 第01集'), findsNothing);
    expect(find.text('测试剧集 第02集'), findsOneWidget);
    tasks.clear();
    await tester.runAsync(() => offline.setParallelism(3));
    await tester.pumpAndSettle();
    expect(find.text('暂无下载任务'), findsOneWidget);
    await tester.pageBack();
    await tester.pumpAndSettle();
    expect(find.text('暂无下载任务'), findsOneWidget);
  });

  testWidgets(
      'completed episode opens offline playback and continues within downloaded episodes',
      (tester) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(390, 844);
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    tasks.addAll([
      taskJson('first', first, 'completed'),
      taskJson('second', second, 'completed')
    ]);
    await restoreTasks();
    final messenger =
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
    final calls = <MethodCall>[];
    messenger.setMockMethodCallHandler(MediaController.methods, (call) async {
      calls.add(call);
      return null;
    });
    messenger.setMockMethodCallHandler(
        const MethodChannel('flutter_player_av/events'), (_) async => null);
    messenger.setMockMethodCallHandler(SystemChannels.platform_views,
        (call) async {
      if (call.method == 'create') return 1;
      if (call.method == 'resize') {
        final dimensions = call.arguments as Map;
        return {'width': dimensions['width'], 'height': dimensions['height']};
      }
      return null;
    });
    messenger.setMockMethodCallHandler(
        SystemChannels.platform, (_) async => null);
    addTearDown(() {
      messenger.setMockMethodCallHandler(MediaController.methods, null);
      messenger.setMockMethodCallHandler(
          const MethodChannel('flutter_player_av/events'), null);
      messenger.setMockMethodCallHandler(SystemChannels.platform_views, null);
      messenger.setMockMethodCallHandler(SystemChannels.platform, null);
    });
    await tester.pumpWidget(MaterialApp(home: DownloadsPage(library: library)));
    await tester.tap(find.text('测试剧集'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('测试剧集 第01集'));
    await tester.pumpAndSettle();
    expect(
        tester.widget<PlayerPage>(find.byType(PlayerPage)).preferOffline, true);
    expect(calls.where((call) => call.method == 'open'), isEmpty);
    expect(calls.firstWhere((call) => call.method == 'openDownload').arguments,
        containsPair('downloadId', 'first'));
    final offlinePlayer = tester.widget<PlayerPage>(find.byType(PlayerPage));
    expect(offlinePlayer.entry.lines['普通线路'], hasLength(2));
    expect(offlinePlayer.originalEntry!.lines['普通线路'], hasLength(3));
    expect(library.history[entry.id]!.lines['普通线路'], hasLength(3));
    final id = (calls.firstWhere((call) => call.method == 'create').arguments
        as Map)['playerId'];
    for (final event in [
      {'type': 'duration', 'value': 60000},
      {'type': 'position', 'value': 59000},
      {'type': 'completed', 'value': true},
    ]) {
      await messenger.handlePlatformMessage(
          'flutter_player_av/events',
          const StandardMethodCodec()
              .encodeSuccessEnvelope({'playerId': id, ...event}),
          (_) {});
      await tester.pump();
    }
    await tester.pump(const Duration(seconds: 3));
    await tester.pumpAndSettle();
    expect(calls.lastWhere((call) => call.method == 'openDownload').arguments,
        containsPair('downloadId', 'second'));
    expect(calls.where((call) => call.method == 'open'), isEmpty);
    await tester.tap(find.text('返回原资源'));
    await tester.pumpAndSettle();
    expect(find.byType(DetailPage), findsOneWidget);
    final original = tester.widget<DetailPage>(find.byType(DetailPage)).entry;
    expect(original.id, entry.id);
    expect(original.source, entry.source);
    expect(original.lines['普通线路'], hasLength(3));
    await tester.tap(find.byTooltip('下载剧集'));
    await tester.pumpAndSettle();
    final sheet =
        tester.widget<DownloadEpisodeSheet>(find.byType(DownloadEpisodeSheet));
    expect(sheet.episodes, hasLength(3));
    expect(library.offline.tasks.map((task) => task.id), ['first', 'second']);
    await tester.tap(find.text('全选'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('全部开始'));
    await tester.pumpAndSettle();
    expect(enqueued, hasLength(1));
    expect(enqueued.single['url'], third.url);
    expect(
        library.offline.tasks
            .where((task) => task.completed)
            .map((task) => task.id),
        ['first', 'second']);
    await tester.pumpWidget(const SizedBox());
    await tester.pump();
  });

  testWidgets(
      'download rows show viewing progress separately from download completion and refresh live',
      (tester) async {
    tasks.addAll([
      taskJson('first', first, 'completed'),
      taskJson('second', second, 'completed')
    ]);
    await restoreTasks();
    await library.recordPlay(entry,
        episode: first, position: 30000, duration: 60000);
    await tester.pumpWidget(MaterialApp(home: DownloadsPage(library: library)));
    await tester.tap(find.text('测试剧集'));
    await tester.pumpAndSettle();
    expect(find.text('观看进度：已观看 50% · 0:30 / 1:00'), findsOneWidget);
    expect(find.text('观看进度：未观看 · 0%'), findsOneWidget);
    await library.recordPlay(entry,
        episode: first, duration: 60000, completed: true);
    await tester.pumpAndSettle();
    expect(find.text('观看进度：已看完 · 100%'), findsOneWidget);
    expect(library.offline.tasks.map((task) => task.id), ['first', 'second']);
    await tester.pumpWidget(const SizedBox());
    await tester.pump();
  });

  for (final width in [320.0, 1280.0]) {
    testWidgets(
        'grouped downloads and episode management fit $width width with large text',
        (tester) async {
      tester.view.devicePixelRatio = 1;
      tester.view.physicalSize = Size(width, 640);
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      tasks.add(taskJson('first', first, 'failed')
        ..['error'] = 'DRM_OFFLINE_LICENSE_REQUIRED');
      await restoreTasks();
      await tester.pumpWidget(MaterialApp(
          builder: (context, child) => MediaQuery(
              data: MediaQuery.of(context)
                  .copyWith(textScaler: TextScaler.linear(1.4)),
              child: child!),
          home: DownloadsPage(library: library)));
      await tester.tap(find.text('测试剧集'));
      await tester.pumpAndSettle();
      expect(find.byTooltip('管理第01集'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });
  }

  testWidgets('settings selects ten parallel episodes', (tester) async {
    await tester.pumpWidget(
        MaterialApp(home: Scaffold(body: SettingsPage(library: library))));
    expect(find.text('下载并发数'), findsOneWidget);
    expect(find.text('3 个'), findsOneWidget);
    await tester.tap(find.byType(DropdownButton<int>));
    await tester.pumpAndSettle();
    await tester.runAsync(() async {
      await tester.tap(find.text('10 个').last);
      await Future<void>.delayed(Duration.zero);
    });
    await tester.pumpAndSettle();
    await tester.runAsync(() => Future<void>.delayed(Duration.zero));
    await tester.pumpAndSettle();
    expect(parallelism, 10);
    expect(find.text('10 个'), findsOneWidget);
  });
}
