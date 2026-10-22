import 'package:flutter_test/flutter_test.dart';
import 'package:youying/live.dart';

void main() {
  test('parseLivePlaylist keeps https channels with group and logo', () {
    const playlist = '#EXTM3U\n'
        '#EXTINF:-1 tvg-logo="https://img.example/cctv1.png" group-title="央视频道",CCTV-1\n'
        'https://live.example.com/cctv1.m3u8\n'
        '#EXTINF:-1 group-title="卫视频道",湖南卫视\n'
        'http://insecure.example.com/hunan.m3u8\n'
        '#EXTINF:-1,无分组频道\n'
        'https://live.example.com/other.m3u8\n'
        '#EXTINF:-1,非HTTP协议\n'
        'udp://239.1.1.1:1234\n';
    final channels = parseLivePlaylist(playlist, source: '测试');
    expect(channels, hasLength(3));
    expect(channels[0].name, 'CCTV-1');
    expect(channels[0].group, '央视频道');
    expect(channels[0].logo, 'https://img.example/cctv1.png');
    expect(channels[0].source, '测试');
    // Cleartext http is allowed: domestic IPTV relays do not offer TLS.
    expect(channels[1].name, '湖南卫视');
    expect(channels[2].group, '其他');
    expect(channels.any((c) => c.url.startsWith('udp:')), isFalse);
  });

  test('parseLivePlaylist ignores malformed input', () {
    expect(parseLivePlaylist(''), isEmpty);
    expect(parseLivePlaylist('not a playlist'), isEmpty);
    expect(
        parseLivePlaylist(
            '#EXTINF:-1,名字后没有地址\n#EXT-X-ENDLIST\n'),
        isEmpty);
  });

  test('isMainlandChannel keeps domestic and drops foreign channels', () {
    LiveChannel named(String name) =>
        LiveChannel(name: name, url: 'https://a.example/x.m3u8', group: 'g');
    expect(isMainlandChannel(named('CCTV-1')), isTrue);
    expect(isMainlandChannel(named('CCTV-14 少儿')), isTrue);
    expect(isMainlandChannel(named('湖南卫视')), isTrue);
    expect(isMainlandChannel(named('河南都市')), isTrue);
    expect(isMainlandChannel(named('CGTN Documentary')), isFalse);
    expect(isMainlandChannel(named('CGTN阿语')), isFalse);
    expect(isMainlandChannel(named('CCTV+ 1 (600p)')), isFalse);
    expect(isMainlandChannel(named('ABN China')), isFalse);
    expect(isMainlandChannel(named('CNN International')), isFalse);
  });

  test('mergeChannels dedupes CCTV aliases and regroups them', () {
    final merged = mergeChannels([
      const LiveChannel(
          name: 'CCTV-1 (720p)',
          url: 'http://ipv4.example/a.m3u8',
          group: 'General'),
      const LiveChannel(
          name: 'CCTV-1综合',
          url: 'http://[2409::1]/a.m3u8',
          group: '央视频道'),
      const LiveChannel(
          name: 'CCTV-4K HD',
          url: 'http://ipv4.example/4k.m3u8',
          group: 'General'),
      const LiveChannel(
          name: '湖南卫视',
          url: 'http://[2409::1]/h.m3u8',
          group: '卫视频道'),
    ]);
    // CCTV-1 aliases collapse to the first (IPv4) stream; CCTV-4K stays
    // distinct from a hypothetical CCTV-4, and 湖南卫视 keeps its group.
    expect(merged, hasLength(3));
    expect(merged[0].name, 'CCTV-1');
    expect(merged[0].url, contains('ipv4'));
    expect(merged[0].group, '央视频道');
    expect(merged[1].name, 'CCTV-4K HD');
    expect(merged[2].group, '卫视频道');
  });
}
