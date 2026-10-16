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
import 'package:youying/source_presets.dart';

final class _MemoryPreferences extends SharedPreferencesAsyncPlatform {
  final Map<String, Object> values = {};
  bool failWrites = false;

  @override
  Future<String?> getString(
          String key, SharedPreferencesOptions options) async =>
      values[key] as String?;
  @override
  Future<bool?> getBool(String key, SharedPreferencesOptions options) async =>
      values[key] as bool?;
  @override
  Future<void> setString(
      String key, String value, SharedPreferencesOptions options) async {
    if (failWrites) throw StateError('disk failure');
    values[key] = value;
  }

  @override
  Future<void> setBool(
      String key, bool value, SharedPreferencesOptions options) async {
    if (failWrites) throw StateError('disk failure');
    values[key] = value;
  }

  @override
  dynamic noSuchMethod(Invocation invocation) =>
      throw StateError('Unexpected preference call');
}

void main() {
  late _MemoryPreferences store;
  setUp(() {
    store = _MemoryPreferences();
    SharedPreferencesAsyncPlatform.instance = store;
  });

  const episodes = [
    Episode(name: '第01集', url: 'https://example.com/1.mp4'),
    Episode(name: '第02集', url: 'https://example.com/2.mp4')
  ];
  const watchedEntry = MediaEntry(
      id: 'watch:1', title: '进度测试', source: '测试来源', lines: {'主线': episodes});

  test(
      'episode duration, completion and the most recent episode survive reload',
      () async {
    final library = await Library.open();
    await library.recordPlay(watchedEntry,
        episode: episodes.first, position: 30000, duration: 60000);
    expect(library.watchProgress(watchedEntry.id, episodes.first).percent, 50);
    await library.recordPlay(watchedEntry,
        episode: episodes.first,
        position: 60000,
        duration: 60000,
        completed: true);
    await library.recordPlay(watchedEntry,
        episode: episodes.last, position: 15000, duration: 60000);
    final restored = await Library.open();
    expect(restored.watchProgress(watchedEntry.id, episodes.first).completed,
        true);
    expect(
        restored.watchProgress(watchedEntry.id, episodes.first).percent, 100);
    expect(restored.resumePosition(watchedEntry.id, episodes.first), 60000);
    expect(restored.lastWatchedEpisode(watchedEntry)!.url, episodes.last.url);
    expect(restored.watchSummary(watchedEntry),
        '测试来源 · 第02集 · 已观看 25% · 0:15 / 1:00');
    await restored.recordPlay(watchedEntry, episode: episodes.first);
    expect(restored.watchProgress(watchedEntry.id, episodes.first).completed,
        true);
    library.dispose();
    restored.dispose();
  });

  test(
      'rapid playback saves stay ordered and a failed write does not block later saves',
      () async {
    final library = await Library.open();
    await Future.wait([
      library.recordPlay(watchedEntry,
          episode: episodes.first, position: 10000, duration: 60000),
      library.recordPlay(watchedEntry,
          episode: episodes.first,
          position: 60000,
          duration: 60000,
          completed: true),
      library.recordPlay(watchedEntry,
          episode: episodes.last, position: 30000, duration: 60000),
    ]);
    store.failWrites = true;
    await expectLater(
        library.recordPlay(watchedEntry,
            episode: episodes.last, position: 35000),
        throwsStateError);
    store.failWrites = false;
    await library.recordPlay(watchedEntry,
        episode: episodes.last, position: 40000);
    final restored = await Library.open();
    expect(
        restored.watchProgress(watchedEntry.id, episodes.first).percent, 100);
    expect(restored.watchProgress(watchedEntry.id, episodes.last).positionMs,
        40000);
    expect(restored.lastWatchedEpisode(watchedEntry)!.url, episodes.last.url);
    library.dispose();
    restored.dispose();
  });

  test('old or malformed watch metadata never fabricates a viewing percentage',
      () async {
    store.values['positions'] = jsonEncode(
        {Library.episodeKey(watchedEntry.id, episodes.first): 15000});
    for (final bad in ['invalid json', '[]', '{"episodes":false}']) {
      store.values['watch_progress'] = bad;
      final library = await Library.open();
      expect(library.watchProgress(watchedEntry.id, episodes.first).percent,
          isNull);
      expect(library.watchProgress(watchedEntry.id, episodes.first).label,
          contains('0:15'));
      expect(library.watchProgress(watchedEntry.id, episodes.last).label,
          '未观看 · 0%');
      library.dispose();
    }
  });

  test('first load seeds eight checked presets and no retired endpoints',
      () async {
    final library = await Library.open();
    expect(sourcePresets, hasLength(8));
    expect(sourcePresets.where((p) => p.introducedIn == 2), hasLength(5));
    expect(library.sources.length, sourcePresets.length);
    expect(library.enabledSources, library.sources);
    expect(library.sources.map((s) => s.url).toSet(), hasLength(8));
    expect(library.sources.map((s) => s.name).toSet(), hasLength(8));
    expect(library.sources.any((s) => retiredSourcePresetUrls.contains(s.url)),
        false);
    expect(store.values['public_sources_initialized_v1'], true);
    expect(store.values['public_sources_initialized_v2'], true);
    expect(store.values['public_sources_initialized_v3'], true);
    expect((await Library.open()).sources.length, sourcePresets.length);
    for (final preset in sourcePresets) {
      expect(SourceEndpoint.parseHttps(preset.source.url).scheme, 'https');
      expect(presetFor(preset.source), preset);
    }
  });

  test('favorites and history remain one work across source variants',
      () async {
    final library = await Library.open();
    const a = MediaEntry(
        id: 'A:1', title: '同一作品', source: 'A', year: '2026', category: '国产剧');
    const b = MediaEntry(
        id: 'B:90', title: '同一作品', source: 'B', year: '2026', category: '电视剧');
    await library.toggleFavorite(a);
    expect(library.isFavorite(b), true);
    expect((await Library.open()).isFavorite(b), true);
    await library.toggleFavorite(b);
    expect(library.favorites, isEmpty);
    await library.recordPlay(a);
    await library.recordPlay(b);
    expect(library.recentEntries.map((e) => e.id), ['B:90']);
    expect(library.history['A:1'], a);
  });

  test(
      'migration preserves custom source names URLs disabled state and library data',
      () async {
    store.values['sources'] = jsonEncode([
      {
        'name': 'custom',
        'url': sourcePresets.first.source.url,
        'enabled': false
      },
      {'name': '极速资源', 'url': 'https://example.com/private'},
    ]);
    store.values['favorites'] = MediaEntry.encodeList([
      const MediaEntry(id: 'fav', title: 'Saved', source: 'custom'),
    ]);
    final library = await Library.open();
    expect(library.sources.length, sourcePresets.length);
    expect(library.sources.first.name, 'custom');
    expect(library.sources.first.enabled, false);
    expect(library.sources[1].url, 'https://example.com/private');
    expect(library.sources[1].enabled, true);
    expect(library.favorites['fav']?.title, 'Saved');
  });

  test(
      'disabled and removed presets stay that way across restarts including empty list',
      () async {
    final library = await Library.open();
    await library.setSourceEnabled(library.sources.first, false);
    await library.removeSource(library.sources[1]);
    var restored = await Library.open();
    expect(restored.sources.length, sourcePresets.length - 1);
    expect(restored.sources.first.enabled, false);
    expect(restored.sources.any((s) => s.name == '极速资源'), false);
    for (final source in List.of(restored.sources)) {
      await restored.removeSource(source);
    }
    restored = await Library.open();
    expect(restored.sources, isEmpty);
  });

  test('corrupt source data is not overwritten by migration', () async {
    store.values['sources'] = 'corrupt';
    expect((await Library.open()).sources, isEmpty);
    expect(store.values['sources'], 'corrupt');
    expect(store.values.containsKey('public_sources_initialized_v1'), false);
    expect(store.values.containsKey('public_sources_initialized_v2'), false);
    expect(store.values.containsKey('public_sources_initialized_v3'), false);
  });

  test('v1 upgrade retires failed URLs without restoring deleted v1 presets',
      () async {
    store.values['public_sources_initialized_v1'] = true;
    store.values['sources'] = jsonEncode([
      sourcePresets.first.source.withEnabled(false).toJson(),
      {'name': 'renamed retired', 'url': retiredSourcePresetUrls.first},
      {'name': '量子资源', 'url': retiredSourcePresetUrls.last, 'enabled': false},
      {'name': '无尽资源', 'url': 'https://custom.example/api', 'enabled': false},
    ]);
    final saved = MediaEntry.encodeList([
      const MediaEntry(id: 'saved', title: 'Saved', source: '无尽资源'),
    ]);
    store.values['favorites'] = saved;
    store.values['history'] = saved;
    store.values['positions'] = '{"saved":1234}';
    store.values['downloads'] = '{"saved":"/local/video.mp4"}';
    var library = await Library.open();
    expect(library.sources, hasLength(8));
    expect(library.sources.first.enabled, false);
    expect(library.sources.any((s) => s.name == '极速资源'), false);
    expect(library.sources.any((s) => retiredSourcePresetUrls.contains(s.url)),
        false);
    expect(library.sources[1].url, 'https://custom.example/api');
    expect(library.sources[1].enabled, false);
    expect(library.favorites['saved']?.title, 'Saved');
    expect(library.history['saved']?.title, 'Saved');
    expect(library.positionsMs['saved'], 1234);
    expect(library.downloads['saved'], '/local/video.mp4');
    await library.removeSource(library.sources.last);
    library = await Library.open();
    expect(library.sources, hasLength(7));
  });

  test('v1 empty configuration receives later presets once', () async {
    store.values['public_sources_initialized_v1'] = true;
    store.values['sources'] = '[]';
    final library = await Library.open();
    expect(
        library.sources.map((s) => s.url),
        sourcePresets
            .where((p) => p.introducedIn > 1)
            .map((p) => p.source.url));
    for (final source in List.of(library.sources)) {
      await library.removeSource(source);
    }
    expect((await Library.open()).sources, isEmpty);
  });

  test('upgrade preserves user overrides for new preset names and URLs',
      () async {
    store.values['public_sources_initialized_v1'] = true;
    final additions = sourcePresets.where((p) => p.introducedIn == 2).toList();
    store.values['sources'] = jsonEncode([
      {
        'name': additions[0].source.name,
        'url': 'https://custom.example/api',
        'enabled': false
      },
      {
        'name': 'custom alias',
        'url': additions[1].source.url,
        'enabled': false
      },
    ]);
    final library = await Library.open();
    expect(library.sources, hasLength(6));
    expect(library.sources.first.url, 'https://custom.example/api');
    expect(library.sources[1].name, 'custom alias');
    expect(library.sources.take(2).every((s) => !s.enabled), true);
    expect((await Library.open()).sources, hasLength(6));
  });

  test('v1 upgrade does not overwrite corrupt state or mark migration complete',
      () async {
    store.values['public_sources_initialized_v1'] = true;
    for (final raw in ['corrupt', '{}', '[{"name":"invalid"}]']) {
      store.values['sources'] = raw;
      expect((await Library.open()).sources, isEmpty);
      expect(store.values['sources'], raw);
      expect(store.values.containsKey('public_sources_initialized_v2'), false);
    }
  });

  test(
      'failed v2 migration can retry without losing the old source configuration',
      () async {
    store.values['public_sources_initialized_v1'] = true;
    final previous = jsonEncode([
      {'name': '无尽资源', 'url': retiredSourcePresetUrls.first},
    ]);
    store.values['sources'] = previous;
    store.failWrites = true;
    await expectLater(Library.open(), throwsStateError);
    expect(store.values['sources'], previous);
    expect(store.values.containsKey('public_sources_initialized_v2'), false);
    store.failWrites = false;
    expect((await Library.open()).sources, hasLength(6));
  });

  test('v3 migration respects a deliberately empty v2 source list', () async {
    store.values['public_sources_initialized_v1'] = true;
    store.values['public_sources_initialized_v2'] = true;
    store.values['sources'] = '[]';
    expect((await Library.open()).sources, isEmpty);
    expect(store.values['public_sources_initialized_v3'], true);
  });

  test(
      'v3 adds only the new preset without restoring removed or disabled sources',
      () async {
    store.values['public_sources_initialized_v1'] = true;
    store.values['public_sources_initialized_v2'] = true;
    store.values['sources'] = jsonEncode([
      sourcePresets.first.source.withEnabled(false).toJson(),
      {'name': 'custom', 'url': 'https://custom.example/api', 'enabled': false},
    ]);
    final library = await Library.open();
    expect(library.sources, hasLength(3));
    expect(library.sources.take(2).every((source) => !source.enabled), true);
    expect(library.sources.last.name, '魔都资源');
    expect(library.sources.any((source) => source.name == '极速资源'), false);
    await library.removeSource(library.sources.last);
    expect((await Library.open()).sources, hasLength(2));
  });

  test('failed persistence does not change the source list', () async {
    final library = await Library.open();
    store.failWrites = true;
    await expectLater(library.setSourceEnabled(library.sources.first, false),
        throwsStateError);
    expect(library.sources.first.enabled, true);
    await expectLater(
        library.removeSource(library.sources.first), throwsStateError);
    expect(library.sources.length, sourcePresets.length);
  });

  test('legacy source defaults enabled and new source state round trips', () {
    expect(
        SourceEndpoint.fromJson({'name': 'test', 'url': 'https://example.com'})
            .enabled,
        true);
    final disabled = sourcePresets.first.source.withEnabled(false);
    expect(SourceEndpoint.fromJson(disabled.toJson()).enabled, false);
    expect(
        () => SourceEndpoint.fromJson(
            {'name': 'test', 'url': 'https://example.com', 'enabled': 'false'}),
        throwsFormatException);
  });

  test('disabled sources make no search or detail request', () async {
    final client = CatalogClient(
        client:
            MockClient((_) async => throw StateError('Unexpected network')));
    addTearDown(client.dispose);
    final source = sourcePresets.first.source.withEnabled(false);
    expect(await client.search(source, 'query'), isEmpty);
    await expectLater(
        client.detail(
            source,
            MediaEntry(
                id: '1', remoteId: '1', title: 'Title', source: source.name)),
        throwsFormatException);
  });

  test(
      'catalog ignores webpage lines and keeps direct media including query strings',
      () {
    final entry = MediaEntry.parseResponse({
      'list': [
        {
          'vod_id': 1,
          'vod_name': 'test',
          'vod_play_from': r'web$$$hls$$$dash',
          'vod_play_url':
              r'1$https://example.com/share/123$$$1$https://example.com/video.M3U8?key=test$$$1$https://example.com/video.mpd',
        }
      ],
    }, 'source')
        .single;
    expect(entry.lines.keys, ['hls', 'dash']);
    expect(entry.lines['hls']!.single.url, endsWith('?key=test'));
  });

  testWidgets(
      'search continues after one source fails and skips disabled sources',
      (tester) async {
    final library = Library(SharedPreferencesAsync())
      ..sources = [
        const SourceEndpoint(name: 'bad', url: 'https://bad.example/api'),
        const SourceEndpoint(
            name: 'off', url: 'https://off.example/api', enabled: false),
        const SourceEndpoint(name: 'good', url: 'https://good.example/api'),
      ];
    final requested = <String>[];
    final client = CatalogClient(client: MockClient((request) async {
      requested.add(request.url.host);
      return request.url.host == 'bad.example'
          ? http.Response('', 403)
          : http.Response('{"list":[{"vod_id":1,"vod_name":"Found"}]}', 200);
    }));
    addTearDown(client.dispose);
    await tester.pumpWidget(MaterialApp(
        home: Scaffold(body: SearchPage(library: library, client: client))));
    expect(requested, isEmpty);
    await tester.enterText(find.byType(TextField), 'query');
    await tester.runAsync(() async {
      await tester.tap(find.byTooltip('搜索'));
      await Future<void>.delayed(const Duration(milliseconds: 50));
    });
    await tester.pumpAndSettle();
    expect(requested, ['bad.example', 'good.example']);
    expect(find.text('Found'), findsOneWidget);
    expect(find.text('bad：请求失败或返回格式不兼容'), findsNothing);
    await tester.tap(find.text('来源状态'));
    await tester.pumpAndSettle();
    expect(find.text('bad：请求失败或返回格式不兼容'), findsOneWidget);
    expect(find.text('good：1 条'), findsOneWidget);
  });

  testWidgets(
      'settings switches and removes sources at phone width without restoring them',
      (tester) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final library = await Library.open();
    await tester.pumpWidget(
        MaterialApp(home: Scaffold(body: SettingsPage(library: library))));
    final sourceTile = find.ancestor(
        of: find.byTooltip('移除360资源'), matching: find.byType(ListTile));
    final sourceSwitch =
        find.descendant(of: sourceTile, matching: find.byType(Switch));
    await tester.ensureVisible(sourceSwitch);
    await tester.tap(sourceSwitch);
    await tester.pumpAndSettle();
    expect(library.sources.first.enabled, false);
    await tester.tap(find.byTooltip('移除360资源'));
    await tester.pumpAndSettle();
    expect(library.sources.any((s) => s.name == '360资源'), false);
    expect((await Library.open()).sources.any((s) => s.name == '360资源'), false);
    expect(tester.takeException(), isNull);
  });

  test(
      'search history persists, trims, deduplicates and limits recent keywords',
      () async {
    final library = await Library.open();
    await library.recordSearch('  测试片名  ');
    await library.recordSearch('Another');
    await library.recordSearch(' another ');
    await library.recordSearch('   ');
    expect(library.searchHistory, ['another', '测试片名']);
    expect((await Library.open()).searchHistory, ['another', '测试片名']);
    for (var index = 0; index < 25; index++) {
      await library.recordSearch('片名$index');
    }
    expect(library.searchHistory, hasLength(Library.maxSearchHistory));
    expect(library.searchHistory.first, '片名24');
    await library.removeSearch('片名24');
    expect((await Library.open()).searchHistory.first, '片名23');
    await library.clearSearchHistory();
    expect((await Library.open()).searchHistory, isEmpty);
    expect(library.history, isEmpty);
  });

  test(
      'clearing serializes with rapid searches and cannot restore old keywords',
      () async {
    final library = await Library.open();
    final first = library.recordSearch('第一部');
    final second = library.recordSearch('第二部');
    final clear = library.clearSearchHistory();
    await Future.wait([first, second, clear]);
    expect(library.searchHistory, isEmpty);
    expect((await Library.open()).searchHistory, isEmpty);
  });

  test(
      'corrupt search history is ignored without rewriting other persisted data',
      () async {
    store.values['search_history'] = '{broken';
    final library = await Library.open();
    expect(library.searchHistory, isEmpty);
    expect(store.values['search_history'], '{broken');
    store.values['search_history'] = jsonEncode(['', 12, ' A ', 'a', 'B']);
    expect((await Library.open()).searchHistory, ['A', 'B']);
    store.values['search_history'] = '{}';
    expect((await Library.open()).searchHistory, isEmpty);
  });

  test(
      'failed history writes preserve existing state and later edits can recover',
      () async {
    final library = await Library.open();
    await library.recordSearch('保留');
    store.failWrites = true;
    await expectLater(library.clearSearchHistory(), throwsStateError);
    expect(library.searchHistory, ['保留']);
    store.failWrites = false;
    await library.recordSearch('恢复');
    expect(library.searchHistory, ['恢复', '保留']);
  });

  test(
      'auto-next defaults on, persists off and does not change after a failed write',
      () async {
    final library = await Library.open();
    expect(library.autoPlayNext, true);
    await library.setAutoPlayNext(false);
    expect((await Library.open()).autoPlayNext, false);
    store.failWrites = true;
    await expectLater(library.setAutoPlayNext(true), throwsStateError);
    expect(library.autoPlayNext, false);
  });

  testWidgets('settings exposes an enabled-by-default auto-next switch',
      (tester) async {
    final library = await Library.open();
    await tester.pumpWidget(
        MaterialApp(home: Scaffold(body: SettingsPage(library: library))));
    final setting = find.widgetWithText(SwitchListTile, '自动续播下一集');
    expect(tester.widget<SwitchListTile>(setting).value, true);
    await tester.tap(setting);
    await tester.pumpAndSettle();
    expect(tester.widget<SwitchListTile>(setting).value, false);
    expect((await Library.open()).autoPlayNext, false);
  });
}
