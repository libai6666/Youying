import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:youying/catalog.dart';
import 'package:youying/library.dart';

void main() {
  test('optional playback headers are typed and cannot inject new header lines', () {
    expect(parseHeaders(''), isEmpty);
    expect(parseHeaders('{"Referer":"https://example.com"}'), {'Referer': 'https://example.com'});
    expect(() => parseHeaders(jsonEncode({'X-Test': 'ok\r\nInjected: value'})), throwsFormatException);
    expect(() => parseHeaders('{"X-Test":1}'), throwsFormatException);
  });

  test('episode identity separates resume and downloaded-file ownership', () {
    const first = Episode(name: '第1集', url: 'https://example.com/1.mp4');
    const second = Episode(name: '第2集', url: 'https://example.com/2.mp4');
    expect(Library.episodeKey('movie', first), isNot(Library.episodeKey('movie', second)));
    expect(Library.episodeKey('movie', first), Library.episodeKey('movie', first));
  });

  test('only an explicitly supplied HTTPS endpoint can be configured', () {
    expect(() => SourceEndpoint.parseHttps('http://example.com/api'), throwsFormatException);
    expect(() => SourceEndpoint.parseHttps('https://name:password@example.com/api'), throwsFormatException);
    expect(() => SourceEndpoint.parseHttps('file:///etc/passwd'), throwsFormatException);
    expect(SourceEndpoint.parseHttps('https://example.com/api').host, 'example.com');
  });

  test('JSON list response separates sources and playable episodes', () {
    final entries = MediaEntry.parseResponse({
      'list': [
        {
          'vod_id': 42,
          'vod_name': '示例作品',
          'vod_play_from': r'线路A$$$线路B',
          'vod_play_url': r'第1集$https://example.com/1.m3u8#第2集$https://example.com/2.mp4$$$1080p$http://invalid.example/3.mp4',
        },
      ],
    }, '手动源');
    expect(entries.single.title, '示例作品');
    expect(entries.single.id, '手动源:42');
    expect(entries.single.lines['线路A']!.length, 2);
    expect(entries.single.lines.containsKey('线路B'), isFalse);
    expect(entries.single.playable, isTrue);
    final serialized = MediaEntry.encodeList(entries);
    expect(MediaEntry.fromJson((jsonDecode(serialized) as List).single).lines['线路A']!.length, 2);
  });

  test('adapter does not send empty queries; explicit query contacts configured endpoint only', () async {
    final requested = <Uri>[];
    final client = CatalogClient(client: MockClient((request) async {
      requested.add(request.url);
      return http.Response('{"list": [{"vod_id": 1, "vod_name": "Test"}]}', 200);
    }));
    const source = SourceEndpoint(name: '测试源', url: 'https://example.com/api?key=test');
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
    expect(() => MediaEntry.parseResponse({'foo': 1}, 'test'), throwsFormatException);
    expect(MediaEntry.parseResponse({'list': [null, {'vod_name': ''}]}, 'test'), isEmpty);
  });

  test('duplicate line names preserve both source groups', () {
    final entries = MediaEntry.parseResponse({'list': [{
      'vod_name': '作品',
      'vod_play_from': r'线路$$$线路',
      'vod_play_url': r'一$https://example.com/1.mp4$$$二$https://example.com/2.mp4',
    }]}, 'source');
    expect(entries.single.lines.length, 2);
  });

  test('redirecting JSON source is not followed implicitly', () async {
    final client = CatalogClient(client: MockClient((request) async {
      expect(request.followRedirects, isFalse);
      return http.Response('', 302, headers: {'location': 'http://example.com'});
    }));
    const source = SourceEndpoint(name: 'test', url: 'https://example.com/api');
    await expectLater(client.search(source, 'test'), throwsException);
    client.dispose();
  });
}
