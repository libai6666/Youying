import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:youying/catalog.dart';
import 'package:youying/library.dart';

void main() {
  MediaEntry movie(String id,
          {String title = '祥赌必赢',
          String year = '2025',
          String category = '喜剧片',
          String actors = '蔡卓妍,张继聪,邱士缙',
          String director = '罗耀辉'}) =>
      MediaEntry(
          id: id,
          remoteId: id,
          title: title,
          source: id,
          year: year,
          category: category,
          actors: actors,
          director: director,
          poster: 'https://example.com/same.jpg');

  test(
      'corroborated language editions and conflicting source years share a card',
      () {
    final entries = [
      movie('360:国语', title: '祥赌必赢国语', year: '2026'),
      movie('360:粤语', title: '祥赌必赢粤语', year: '2026'),
      movie('极速:85011'),
      movie('豪华:108569'),
    ];
    final grouped = groupCatalog(entries);
    expect(grouped, hasLength(1));
    expect(grouped.single.entries.map((e) => e.id), entries.map((e) => e.id));
    expect(grouped.single.entries[0].title, '祥赌必赢国语');
    expect(grouped.single.entries[1].year, '2026');
    expect(catalogWorkTitle('祥赌必赢（粤语版）'), '祥赌必赢');
    expect(catalogWorkTitle('A Movie 国语'), 'A Movie');
  });

  test('duplicate matching never relies on a shared poster or title alone', () {
    final original = movie('original');
    for (final other in [
      movie('different-director', director: '另一导演'),
      movie('different-cast', actors: '另一演员甲,另一演员乙'),
      movie('remake', year: '1999', director: '另一导演'),
      movie('unknown-year', year: '', director: ''),
      movie('no-evidence', year: '2026', actors: '', director: ''),
      movie('one-actor', year: '2026', actors: '蔡卓妍'),
      movie('different-season', title: '祥赌必赢第二季'),
      movie('different-type', category: '电视剧'),
      movie('commentary', title: '祥赌必赢[电影解说]', category: '电影解说'),
      movie('uncorroborated-edition', title: '祥赌必赢国语', actors: ''),
    ]) {
      expect(groupCatalog([original, other]), hasLength(2), reason: other.id);
    }
  });

  test('year suffix normalization preserves original metadata and stable IDs',
      () {
    final a = movie('A', year: '2025年');
    final b = movie('B');
    expect(groupCatalog([a, b]), hasLength(1));
    expect(a.year, '2025年');
    expect(a.remoteId, 'A');
    expect(catalogIdentity(a), isNot(catalogIdentity(b)));
  });

  test('an ambiguous entry cannot bridge conflicting remake metadata', () {
    final weak = movie('weak', actors: '', director: '');
    final first = movie('first', director: '导演甲');
    final remake = movie('remake', director: '导演乙');
    final groups = groupCatalog([weak, first, remake]);
    expect(groups, hasLength(2));
    expect(groups.first.entries.map((e) => e.id), ['weak', 'first']);
    expect(groups.last.entries.single.id, 'remake');
  });

  test('artwork metadata is optional and survives old and new records', () {
    final old =
        MediaEntry.fromJson({'id': 'old', 'title': '旧记录', 'source': 'A'});
    expect(old.posterCandidates, isEmpty);
    expect(old.backdrop, isEmpty);
    final entry = MediaEntry.parseResponse({
      'list': [
        {
          'vod_id': 1,
          'vod_name': '新记录',
          'vod_pic': 'https://example.com/poster.jpg',
          'vod_pic_slide': 'https://example.com/banner.jpg',
        }
      ]
    }, 'A')
        .single;
    final restored = MediaEntry.fromJson(entry.toJson());
    expect(restored.posterCandidates, ['https://example.com/poster.jpg']);
    expect(restored.backdrop, 'https://example.com/banner.jpg');
    for (final slide in ['', 'http://example.com/invalid.jpg']) {
      expect(
          MediaEntry.parseResponse({
            'list': [
              {
                'vod_id': 2,
                'vod_name': '横图兼容',
                'vod_pic_slide': slide,
                'backdrop': 'https://example.com/backdrop.jpg',
              }
            ]
          }, 'A')
              .single
              .backdrop,
          'https://example.com/backdrop.jpg');
    }
    expect(
        MediaEntry.fromJson({
          ...entry.toJson(),
          'posterFallbacks': [null, 4]
        }).posterFallbacks,
        isEmpty);
  });

  test('same-work artwork fallback never changes playback ownership', () {
    const primary = MediaEntry(
        id: 'A:1',
        remoteId: '1',
        title: '同片',
        source: 'A',
        year: '2026',
        category: '国产剧',
        poster: 'https://a.example/blocked.jpg',
        lines: {
          '主线': [Episode(name: '1', url: 'https://a.example/1.mp4')]
        });
    const alternative = MediaEntry(
        id: 'B:2',
        title: '同片',
        source: 'B',
        year: '2026',
        category: '电视剧',
        poster: 'https://b.example/working.jpg',
        backdrop: 'https://b.example/wide.jpg');
    final group = groupCatalog([primary, alternative]).single;
    final entry = group.primary;
    expect(entry.id, primary.id);
    expect(entry.remoteId, primary.remoteId);
    expect(entry.source, primary.source);
    expect(entry.lines['主线']!.single.url, primary.lines['主线']!.single.url);
    expect(entry.posterCandidates,
        ['https://a.example/blocked.jpg', 'https://b.example/working.jpg']);
    final restored = MediaEntry.fromJson(entry.toJson());
    expect(restored.posterCandidates, entry.posterCandidates);
    expect(restored.backdrop, alternative.backdrop);
    expect(primary.posterFallbacks, isEmpty);
  });

  test('artwork candidates reject unsafe URLs, deduplicate and isolate remakes',
      () {
    expect(
        catalogImageUrls([
          ' https://example.com/p.jpg?a=1&amp;b=2 ',
          'https://example.com/p.jpg?a=1&b=2',
          'http://example.com/plain.jpg',
          'file:///tmp/a',
          'https://user:password@example.com/p.jpg',
          '',
        ]),
        ['https://example.com/p.jpg?a=1&b=2']);
    final groups = groupCatalog([
      const MediaEntry(
          id: '1', title: '同名', source: 'A', year: '2026', category: '电影'),
      const MediaEntry(
          id: '2',
          title: '同名',
          source: 'B',
          year: '2020',
          category: '电影',
          poster: 'https://example.com/remake.jpg'),
    ]);
    expect(groups.first.primary.posterCandidates, isEmpty);
    expect(groups, hasLength(2));
  });

  test('detail keeps same-resource artwork alternatives from its listing',
      () async {
    final client = CatalogClient(
        client: MockClient((_) async => http.Response(
            jsonEncode({
              'list': [
                {
                  'vod_id': 1,
                  'vod_name': '同片',
                  'vod_pic': 'https://a.example/new.jpg'
                }
              ]
            }),
            200,
            headers: {'content-type': 'application/json; charset=utf-8'})));
    addTearDown(client.dispose);
    final result = await client.detail(
        const SourceEndpoint(name: 'A', url: 'https://a.example/api'),
        const MediaEntry(
            id: 'A:1',
            remoteId: '1',
            title: '同片',
            source: 'A',
            poster: 'https://a.example/old.jpg',
            posterFallbacks: ['https://b.example/p.jpg']));
    expect(result.posterCandidates, [
      'https://a.example/new.jpg',
      'https://a.example/old.jpg',
      'https://b.example/p.jpg'
    ]);
    expect(result.source, 'A');
  });

  test(
      'detail metadata survives persistence and numbered episodes match across lines',
      () {
    final entry = MediaEntry.parseResponse({
      'list': [
        {
          'vod_id': 1,
          'vod_name': 'Title',
          'vod_director': '<b>Director</b>',
          'vod_lang': '国语',
          'vod_duration': '45分钟',
        }
      ]
    }, 'test')
        .single;
    final restored = MediaEntry.fromJson(entry.toJson());
    expect(restored.director, 'Director');
    expect(restored.language, '国语');
    expect(restored.duration, '45分钟');
    const current = Episode(name: '第02集', url: 'https://example.com/old.m3u8');
    const target = [
      Episode(name: 'EP2', url: 'https://example.com/2.m3u8'),
      Episode(name: 'EP1', url: 'https://example.com/1.m3u8'),
    ];
    expect(Episode.onLine(target, current, [current])?.name, 'EP2');
  });
  test('detail uses stable remote ID and clears stale search parameters',
      () async {
    final requested = <Uri>[];
    final client = CatalogClient(client: MockClient((request) async {
      requested.add(request.url);
      return http.Response(
          jsonEncode({
            'list': [
              {
                'vod_id': 42,
                'vod_name': 'Full title',
                'vod_play_from': 'A',
                'vod_play_url': r'1$https://example.com/1.m3u8',
              }
            ]
          }),
          200);
    }));
    addTearDown(client.dispose);
    const source = SourceEndpoint(
        name: 'test',
        url: 'https://example.com/api?wd=old&pg=2&ac=list&key=example');
    final entry = MediaEntry.parseResponse({
      'list': [
        {'vod_id': 42, 'vod_name': 'title'}
      ]
    }, 'test')
        .single;
    final restored = MediaEntry.fromJson(entry.toJson());
    final result = await client.detail(source, restored);
    expect(result.remoteId, '42');
    expect(result.playable, isTrue);
    expect(requested.single.queryParameters,
        {'ac': 'detail', 'ids': '42', 'key': 'example'});
  });

  test('detail refuses absent IDs, mismatched sources and mismatched responses',
      () async {
    var requests = 0;
    final client = CatalogClient(client: MockClient((_) async {
      requests++;
      return http.Response('{"list":[{"vod_id":2,"vod_name":"Other"}]}', 200);
    }));
    addTearDown(client.dispose);
    const source = SourceEndpoint(name: 'test', url: 'https://example.com/api');
    await expectLater(
        client.detail(
            source, const MediaEntry(id: 'test:x', title: 'x', source: 'test')),
        throwsFormatException);
    await expectLater(
        client.detail(
            source,
            const MediaEntry(
                id: 'test:x', remoteId: 'x', title: 'x', source: 'other')),
        throwsFormatException);
    expect(requests, 0);
    await expectLater(
        client.detail(
            source,
            const MediaEntry(
                id: 'test:1', remoteId: '1', title: 'x', source: 'test')),
        throwsFormatException);
  });

  test(
      'switching source matches episode name, then index, then first available',
      () {
    const old = [
      Episode(name: 'one', url: 'https://a/1'),
      Episode(name: 'two', url: 'https://a/2')
    ];
    const target = [
      Episode(name: 'two', url: 'https://b/2'),
      Episode(name: 'one', url: 'https://b/1')
    ];
    expect(Episode.onLine(target, old[1], old), target[0]);
    const unnamed = [
      Episode(name: 'x', url: 'https://b/1'),
      Episode(name: 'y', url: 'https://b/2')
    ];
    expect(Episode.onLine(unnamed, old[1], old), unnamed[1]);
    expect(Episode.onLine([unnamed.first], old[1], old), unnamed.first);
    expect(Episode.onLine([], old[1], old), isNull);
  });

  test('optional playback headers are typed and cannot inject new header lines',
      () {
    expect(parseHeaders(''), isEmpty);
    expect(parseHeaders('{"Referer":"https://example.com"}'),
        {'Referer': 'https://example.com'});
    expect(() => parseHeaders(jsonEncode({'X-Test': 'ok\r\nInjected: value'})),
        throwsFormatException);
    expect(() => parseHeaders('{"X-Test":1}'), throwsFormatException);
  });

  test('episode identity separates resume and downloaded-file ownership', () {
    const first = Episode(name: '第1集', url: 'https://example.com/1.mp4');
    const second = Episode(name: '第2集', url: 'https://example.com/2.mp4');
    expect(Library.episodeKey('movie', first),
        isNot(Library.episodeKey('movie', second)));
    expect(
        Library.episodeKey('movie', first), Library.episodeKey('movie', first));
  });

  test('only an explicitly supplied HTTPS endpoint can be configured', () {
    expect(() => SourceEndpoint.parseHttps('http://example.com/api'),
        throwsFormatException);
    expect(
        () =>
            SourceEndpoint.parseHttps('https://name:password@example.com/api'),
        throwsFormatException);
    expect(() => SourceEndpoint.parseHttps('file:///etc/passwd'),
        throwsFormatException);
    expect(SourceEndpoint.parseHttps('https://example.com/api').host,
        'example.com');
  });

  test('JSON list response separates sources and playable episodes', () {
    final entries = MediaEntry.parseResponse({
      'list': [
        {
          'vod_id': 42,
          'vod_name': '示例作品',
          'vod_play_from': r'线路A$$$线路B',
          'vod_play_url':
              r'第1集$https://example.com/1.m3u8#第2集$https://example.com/2.mp4$$$1080p$http://invalid.example/3.mp4',
        },
      ],
    }, '手动源');
    expect(entries.single.title, '示例作品');
    expect(entries.single.id, '手动源:42');
    expect(entries.single.lines['线路A']!.length, 2);
    expect(entries.single.lines.containsKey('线路B'), isFalse);
    expect(entries.single.playable, isTrue);
    final serialized = MediaEntry.encodeList(entries);
    expect(
        MediaEntry.fromJson((jsonDecode(serialized) as List).single)
            .lines['线路A']!
            .length,
        2);
  });

  test(
      'adapter does not send empty queries; explicit query contacts configured endpoint only',
      () async {
    final requested = <Uri>[];
    final client = CatalogClient(client: MockClient((request) async {
      requested.add(request.url);
      return http.Response(
          '{"list": [{"vod_id": 1, "vod_name": "Test"}]}', 200);
    }));
    const source =
        SourceEndpoint(name: '测试源', url: 'https://example.com/api?key=test');
    expect(await client.search(source, ''), isEmpty);
    expect(requested, isEmpty);
    final found = await client.search(source, '星际');
    expect(found.single.title, 'Test');
    expect(requested.single.host, 'example.com');
    expect(requested.single.queryParameters['wd'], '星际');
    expect(requested.single.queryParameters['ac'], 'videolist');
    client.dispose();
  });

  test('malformed source data fails closed', () {
    expect(() => MediaEntry.parseResponse({'foo': 1}, 'test'),
        throwsFormatException);
    expect(
        MediaEntry.parseResponse({
          'list': [
            null,
            {'vod_name': ''}
          ]
        }, 'test'),
        isEmpty);
  });

  test('catalog facet and sorting metadata survive history serialization', () {
    final entry = MediaEntry.parseResponse({
      'list': [
        {
          'vod_id': 1,
          'vod_name': '测试',
          'vod_class': '动作,冒险',
          'vod_area': '中国大陆',
          'vod_lang': '汉语普通话',
          'vod_year': '2026',
          'vod_douban_score': '8.2',
          'vod_hits': '120',
          'vod_time': '2026-01-02 10:00:00',
        }
      ]
    }, 'A')
        .single;
    final restored =
        MediaEntry.fromJson(jsonDecode(MediaEntry.encodeList([entry]))[0]);
    expect(restored.genres, '动作,冒险');
    expect(restored.rating, 8.2);
    expect(restored.popularity, 120);
    expect(
        restored.updatedAtMs, DateTime(2026, 1, 2, 10).millisecondsSinceEpoch);
    expect(
        MediaEntry.fromJson({'id': 'old', 'title': '旧记录', 'source': 'A'})
            .rating,
        isNull);
  });

  test('missing zero and invalid metrics never fabricate rating or popularity',
      () {
    for (final value in ['NaN', 'Infinity', '-1', '100', '']) {
      expect(catalogRating(value), isNull);
    }
    expect(catalogRating('0'), isNull);
    expect(catalogCount('0'), isNull);
    expect(catalogCount('-1'), isNull);
    expect(catalogCount('1.5'), isNull);
    expect(catalogDate('0'), isNull);
    expect(catalogDate('invalid'), isNull);
    expect(catalogDate('999999999999999999999'), isNull);
    expect(catalogDate('1767225600'), catalogDate('1767225600000'));
    final entry = MediaEntry.parseResponse({
      'list': [
        {
          'vod_name': '测试',
          'vod_douban_score': '0',
          'vod_score': '7.5',
          'vod_hits': '0'
        }
      ]
    }, 'A')
        .single;
    expect(entry.rating, 7.5);
    expect(entry.popularity, isNull);
  });

  test('duplicate line names preserve both source groups', () {
    final entries = MediaEntry.parseResponse({
      'list': [
        {
          'vod_name': '作品',
          'vod_play_from': r'线路$$$线路',
          'vod_play_url':
              r'一$https://example.com/1.mp4$$$二$https://example.com/2.mp4',
        }
      ]
    }, 'source');
    expect(entries.single.lines.length, 2);
  });

  test('redirecting JSON source is not followed implicitly', () async {
    final client = CatalogClient(client: MockClient((request) async {
      expect(request.followRedirects, isFalse);
      return http.Response('', 302,
          headers: {'location': 'http://example.com'});
    }));
    const source = SourceEndpoint(name: 'test', url: 'https://example.com/api');
    await expectLater(client.search(source, 'test'), throwsException);
    client.dispose();
  });
}
