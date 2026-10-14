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

  test('first load seeds seven checked presets and no retired endpoints',
      () async {
    final library = await Library.open();
    expect(sourcePresets, hasLength(7));
    expect(sourcePresets.where((p) => p.introducedIn == 2), hasLength(5));
    expect(library.sources.length, sourcePresets.length);
    expect(library.enabledSources, library.sources);
    expect(library.sources.map((s) => s.url).toSet(), hasLength(7));
    expect(library.sources.map((s) => s.name).toSet(), hasLength(7));
    expect(library.sources.any((s) => retiredSourcePresetUrls.contains(s.url)),
        false);
    expect(store.values['public_sources_initialized_v1'], true);
    expect(store.values['public_sources_initialized_v2'], true);
    expect((await Library.open()).sources.length, sourcePresets.length);
    for (final preset in sourcePresets) {
      expect(SourceEndpoint.parseHttps(preset.source.url).scheme, 'https');
      expect(presetFor(preset.source), preset);
    }
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
    expect(library.sources, hasLength(7));
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
    expect(library.sources, hasLength(6));
  });

  test('v1 empty configuration receives only the five new presets once',
      () async {
    store.values['public_sources_initialized_v1'] = true;
    store.values['sources'] = '[]';
    final library = await Library.open();
    expect(
        library.sources.map((s) => s.url),
        sourcePresets
            .where((p) => p.introducedIn == 2)
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
    expect(library.sources, hasLength(5));
    expect(library.sources.first.url, 'https://custom.example/api');
    expect(library.sources[1].name, 'custom alias');
    expect(library.sources.take(2).every((s) => !s.enabled), true);
    expect((await Library.open()).sources, hasLength(5));
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
    expect((await Library.open()).sources, hasLength(5));
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
    await tester.tap(find.byType(Switch).first);
    await tester.pumpAndSettle();
    expect(library.sources.first.enabled, false);
    await tester.tap(find.byTooltip('移除360资源'));
    await tester.pumpAndSettle();
    expect(library.sources.any((s) => s.name == '360资源'), false);
    expect((await Library.open()).sources.any((s) => s.name == '360资源'), false);
    expect(tester.takeException(), isNull);
  });
}
