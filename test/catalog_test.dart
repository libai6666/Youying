import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:youying/catalog.dart';
import 'package:youying/library.dart';

void main() {
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
