import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:youying/download.dart';

const playlist = '#EXTM3U\n#EXT-X-TARGETDURATION:6\n'
    '#EXTINF:6,\nseg.ts\n#EXT-X-ENDLIST\n';
final base =
    Uri.parse('https://example.com/videos/index.m3u8?token=not-propagated');

void main() {
  test('concurrent calls cannot both pass the download guard', () async {
    final root = await Directory.systemTemp.createTemp('youying-guard-');
    addTearDown(() => root.delete(recursive: true));
    final response = Completer<http.Response>();
    final downloader =
        MediaDownloader(client: MockClient((_) => response.future));
    addTearDown(downloader.close);
    final first = downloader.download(
        'https://example.com/a.mp4', Directory('${root.path}/first'));
    await expectLater(
        downloader.download(
            'https://example.com/b.mp4', Directory('${root.path}/second')),
        throwsStateError);
    response.complete(http.Response('video', 200));
    expect(await File(await first).readAsString(), 'video');
    expect(await Directory('${root.path}/second').exists(), isFalse);
  });

  test('stale partial directories are preserved, not silently deleted',
      () async {
    final root = await Directory.systemTemp.createTemp('youying-stale-');
    addTearDown(() => root.delete(recursive: true));
    final partial = await Directory('${root.path}/saved.partial').create();
    final existing =
        await File('${partial.path}/keep').writeAsString('previous');
    final downloader = MediaDownloader(
        client:
            MockClient((_) async => throw StateError('No request expected')));
    addTearDown(downloader.close);
    await expectLater(
        downloader.download(
            'https://example.com/a.mp4', Directory('${root.path}/saved')),
        throwsFormatException);
    expect(await existing.readAsString(), 'previous');
  });

  test('relative HLS segments become local-only manifest references', () {
    final plan = HlsPlan.parse(playlist, base);
    expect(
        plan.assets.single.uri.toString(), 'https://example.com/videos/seg.ts');
    expect(plan.manifest, contains('asset0.ts'));
    expect(plan.manifest, isNot(contains('https:')));
  });

  test('first muxed master variant and fMP4 init segments are supported', () {
    final master = HlsPlan.parse(
        '#EXTM3U\n#EXT-X-STREAM-INF:BANDWIDTH=123\nsub/v.m3u8\n', base);
    expect(master.variant.toString(), 'https://example.com/videos/sub/v.m3u8');
    final plan = HlsPlan.parse(
        playlist
            .replaceFirst('#EXTINF:6,', '#EXT-X-MAP:URI="init.mp4"\n#EXTINF:6,')
            .replaceFirst('seg.ts', 'seg.m4s'),
        base);
    expect(plan.assets.length, 2);
    expect(plan.manifest, contains('#EXT-X-MAP:URI="asset0.mp4"'));
    expect(plan.manifest, contains('asset1.m4s'));
  });

  for (final tag in [
    '#EXT-X-KEY:METHOD=AES-128,URI="key"',
    '#EXT-X-KEY:METHOD=SAMPLE-AES,URI="key"',
    '#EXT-X-BYTERANGE:10@0',
    '#EXT-X-GAP',
    '#EXT-X-PART:DURATION=1,URI="part.ts"',
    '#EXT-X-MAP:URI="init.mp4",BYTERANGE="100@0"'
  ]) {
    test('unsupported HLS is rejected before any assets: $tag', () {
      expect(
          () => HlsPlan.parse(
              playlist.replaceFirst('#EXTINF:', '$tag\n#EXTINF:'), base),
          throwsFormatException);
    });
  }

  test('live, insecure and malformed manifests are rejected', () {
    for (final text in [
      playlist.replaceFirst('#EXT-X-ENDLIST', ''),
      playlist.replaceFirst('seg.ts', 'http://example.com/a.ts'),
      playlist.replaceFirst('seg.ts', 'https://user:pass@example.com/a.ts'),
      playlist.replaceFirst('#EXTINF:6,', ''),
      playlist.replaceFirst('#EXTINF:6,', '#EXTINF:NaN,'),
      playlist.replaceFirst('#EXT-X-TARGETDURATION:6', ''),
      '<html>not a manifest</html>',
      '#EXTM3U\n#EXT-X-STREAM-INF:BANDWIDTH=1,AUDIO="audio"\na.m3u8\n'
    ]) {
      expect(() => HlsPlan.parse(text, base), throwsFormatException);
    }
  });

  late Directory parent;
  setUp(() async =>
      parent = await Directory.systemTemp.createTemp('youying-test-'));
  tearDown(() async => parent.delete(recursive: true));

  test(
      'downloads master plus VOD atomically; completed files contain no network references',
      () async {
    final requested = <Uri>[];
    final client = MockClient((request) async {
      requested.add(request.url);
      expect(request.followRedirects, isFalse);
      if (request.url.path.endsWith('master.m3u8')) {
        return http.Response(
            '#EXTM3U\n#EXT-X-STREAM-INF:BANDWIDTH=10\nindex.m3u8\n', 200);
      }
      if (request.url.path.endsWith('index.m3u8')) {
        return http.Response(playlist, 200);
      }
      return http.Response.bytes([1, 2, 3], 200);
    });
    final downloader = MediaDownloader(client: client);
    addTearDown(downloader.close);
    final progress = <int>[];
    final path = await downloader.download(
        'https://example.com/master.m3u8', Directory('${parent.path}/complete'),
        onProgress: (n, _) => progress.add(n));
    expect(requested.length, 3);
    expect(await File(path).readAsString(), contains('asset0.ts'));
    expect(await File('${parent.path}/complete/asset0.ts').readAsBytes(),
        [1, 2, 3]);
    expect(progress.last, 3);
    expect(
        await Directory('${parent.path}/complete.partial').exists(), isFalse);
  });

  test(
      'custom headers reach only original origin, never a cross-origin segment',
      () async {
    final client = MockClient((request) async {
      if (request.url.path.endsWith('.m3u8')) {
        expect(request.headers['authorization'], 'Bearer test-only');
        return http.Response(
            playlist.replaceFirst('seg.ts', 'https://cdn.example/seg.ts'), 200);
      }
      expect(request.headers.containsKey('authorization'), isFalse);
      return http.Response('segment', 200);
    });
    final downloader = MediaDownloader(client: client);
    addTearDown(downloader.close);
    await downloader.download(
        base.toString(), Directory('${parent.path}/complete'),
        headers: {'Authorization': 'Bearer test-only'});
  });

  test('encrypted HLS never requests a key and leaves no partial files',
      () async {
    var calls = 0;
    final downloader = MediaDownloader(client: MockClient((request) async {
      calls++;
      return http.Response(
          playlist.replaceFirst(
              '#EXTINF:', '#EXT-X-KEY:METHOD=AES-128,URI="key"\n#EXTINF:'),
          200);
    }));
    addTearDown(downloader.close);
    await expectLater(
        downloader.download(base.toString(), Directory('${parent.path}/bad')),
        throwsFormatException);
    expect(calls, 1);
    expect(await parent.list().toList(), isEmpty);
  });

  test('segment failure and redirects roll back the whole download', () async {
    for (final status in [302, 404]) {
      final downloader = MediaDownloader(
          client: MockClient((request) async =>
              request.url.path.endsWith('.m3u8')
                  ? http.Response(playlist, 200)
                  : http.Response('', status,
                      headers: {'location': 'https://other.example/seg.ts'})));
      addTearDown(downloader.close);
      await expectLater(
          downloader.download(base.toString(), Directory('${parent.path}/bad')),
          throwsA(isA<HttpException>()));
      expect(await parent.list().toList(), isEmpty);
    }
  });

  test('bounded direct downloads work without Content-Length', () async {
    final downloader = MediaDownloader(
        client: MockClient.streaming((request, _) async =>
            http.StreamedResponse(Stream.value(utf8.encode('video')), 200)));
    addTearDown(downloader.close);
    final path = await downloader.download(
        'https://example.com/a.mp4', Directory('${parent.path}/ok'));
    expect(await File(path).readAsString(), 'video');
  });

  test('truncated and oversized streams are removed', () async {
    for (final size in [null, 10]) {
      final downloader = MediaDownloader(
          maxBytes: size == null ? 2 : 100,
          client: MockClient.streaming((request, _) async =>
              http.StreamedResponse(Stream.value([1, 2, 3]), 200,
                  contentLength: size)));
      addTearDown(downloader.close);
      await expectLater(
          downloader.download(
              'https://example.com/a.mp4', Directory('${parent.path}/bad')),
          throwsFormatException);
      expect(await parent.list().toList(), isEmpty);
    }
  });

  test('existing downloads are never overwritten', () async {
    final dir = await Directory('${parent.path}/existing').create();
    final downloader = MediaDownloader(
        client: MockClient((_) async => throw StateError('no network')));
    addTearDown(downloader.close);
    await expectLater(downloader.download('https://example.com/a.mp4', dir),
        throwsFormatException);
    expect(await dir.exists(), isTrue);
  });
}
