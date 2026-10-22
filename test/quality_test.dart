import 'package:flutter_test/flutter_test.dart';
import 'package:youying/catalog.dart';
import 'package:youying/player.dart';
import 'package:youying/quality.dart';

void main() {
  final base = Uri.parse('https://cdn.example.com/2026/abc/index.m3u8');

  test('parseMasterVariants returns resolutions and resolved URIs', () {
    const manifest = '#EXTM3U\n'
        '#EXT-X-VERSION:3\n'
        '#EXT-X-STREAM-INF:BANDWIDTH=800000,RESOLUTION=1280x720\n'
        '720p/index.m3u8\n'
        '#EXT-X-STREAM-INF:BANDWIDTH=2500000,RESOLUTION=1920x1080\n'
        'https://cdn.example.com/2026/abc/1080p/index.m3u8\n';
    final variants = parseMasterVariants(manifest, base);
    expect(variants, hasLength(2));
    expect(variants[0].height, 720);
    expect(variants[0].bandwidth, 800000);
    expect(variants[0].uri.toString(),
        'https://cdn.example.com/2026/abc/720p/index.m3u8');
    expect(variants[1].height, 1080);
    expect(variants[1].label, '1080p');
  });

  test('parseMasterVariants returns empty for media playlists', () {
    const manifest = '#EXTM3U\n'
        '#EXT-X-TARGETDURATION:8\n'
        '#EXTINF:4.0,\n'
        'seg0.ts\n'
        '#EXT-X-ENDLIST\n';
    expect(parseMasterVariants(manifest, base), isEmpty);
    expect(parseMasterVariants('not a manifest', base), isEmpty);
  });

  test('parseMasterVariants skips non-https variant URIs', () {
    const manifest = '#EXTM3U\n'
        '#EXT-X-STREAM-INF:RESOLUTION=1280x720\n'
        'http://insecure.example.com/x.m3u8\n'
        '#EXT-X-STREAM-INF:RESOLUTION=1920x1080\n'
        'ok/index.m3u8\n';
    final variants = parseMasterVariants(manifest, base);
    expect(variants, hasLength(1));
    expect(variants.single.height, 1080);
  });

  test('highestHeightChoice upgrades only to a strictly taller source', () {
    const low = MediaEntry(id: 'A:1', title: '片', source: 'A');
    const high = MediaEntry(id: 'B:2', title: '片', source: 'B');
    const mid = MediaEntry(id: 'C:3', title: '片', source: 'C');
    expect(
        highestHeightChoice(
                [low, high, mid], {'A:1': 720, 'B:2': 1080, 'C:3': 960}, 'A:1')
            ?.id,
        'B:2');
    expect(
        highestHeightChoice([low, high], {'A:1': 1080, 'B:2': 1080}, 'A:1'),
        isNull);
    expect(
        highestHeightChoice([low, high], {'A:1': null, 'B:2': 720}, 'A:1')?.id,
        'B:2');
    expect(
        highestHeightChoice([low, high], {'A:1': 1080, 'B:2': null}, 'A:1'),
        isNull);
    expect(highestHeightChoice([low], {'A:1': null}, 'A:1'), isNull);
  });

  test('VideoTrack.parse sorts by height and keeps selection state', () {
    final tracks = VideoTrack.parse([
      {
        'groupIndex': 0,
        'trackIndex': 0,
        'width': 1280,
        'height': 720,
        'bitrate': 900000,
        'selected': false
      },
      {
        'groupIndex': 0,
        'trackIndex': 1,
        'width': 1920,
        'height': 1080,
        'bitrate': 2000000,
        'selected': true
      },
    ]);
    expect(tracks, hasLength(2));
    expect(tracks.first.height, 1080);
    expect(tracks.first.selected, isTrue);
    expect(tracks.first.label, '1080p');
    expect(tracks.last.label, '720p');
  });

  test('VideoTrack.parse tolerates malformed input', () {
    expect(VideoTrack.parse(null), isEmpty);
    expect(VideoTrack.parse('x'), isEmpty);
    expect(VideoTrack.parse([42, 'bad']), isEmpty);
    final track = VideoTrack.parse([
      {'groupIndex': 1, 'trackIndex': 0}
    ]).single;
    expect(track.label, '默认');
  });
}
