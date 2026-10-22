import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;

/// One channel from a public IPTV playlist.
class LiveChannel {
  const LiveChannel(
      {required this.name,
      required this.url,
      required this.group,
      this.logo = '',
      this.source = ''});
  final String name;
  final String url;
  final String group;
  final String logo;
  final String source;
}

/// Public IPTV playlists. iptv-org is listed first because its IPv4 relay
/// streams work on any network, so it wins the channel-name dedupe for the
/// CCTV suite; fanmingming's IPv6-only carrier relays (北京移动) supply the
/// satellite/local channels that iptv-org lacks. index.m3u is skipped: its
/// Authinfo tokens are region-locked and expire quickly.
const livePlaylists = [
  (
    name: 'iptv-org',
    urls: ['https://iptv-org.github.io/iptv/countries/cn.m3u']
  ),
  (
    name: '央视卫视',
    urls: [
      // raw.githubusercontent.com is unreachable from mainland networks;
      // try jsDelivr mirrors first, fall back to GitHub.
      'https://cdn.jsdelivr.net/gh/fanmingming/live@main/tv/m3u/ipv6.m3u',
      'https://fastly.jsdelivr.net/gh/fanmingming/live@main/tv/m3u/ipv6.m3u',
      'https://raw.githubusercontent.com/fanmingming/live/main/tv/m3u/ipv6.m3u',
    ]
  ),
];

/// Parses `#EXTINF` channel declarations. Only http/https stream URLs are
/// kept; cleartext is permitted because public IPTV relays rarely offer TLS.
List<LiveChannel> parseLivePlaylist(String text, {String source = ''}) {
  final channels = <LiveChannel>[];
  String? name;
  String group = '其他';
  var logo = '';
  for (final raw in const LineSplitter().convert(text)) {
    final line = raw.trim();
    if (line.startsWith('#EXTINF')) {
      group = RegExp(r'group-title="([^"]*)"')
              .firstMatch(line)
              ?.group(1)
              ?.trim() ??
          '';
      if (group.isEmpty) group = '其他';
      logo =
          RegExp(r'tvg-logo="([^"]*)"').firstMatch(line)?.group(1)?.trim() ??
              '';
      final comma = line.indexOf(',');
      name = comma < 0 ? null : line.substring(comma + 1).trim();
    } else if (!line.startsWith('#') && line.isNotEmpty) {
      if (name != null &&
          name.isNotEmpty &&
          line.startsWith('http')) {
        channels.add(LiveChannel(
            name: name, url: line, group: group, logo: logo, source: source));
      }
      name = null;
      group = '其他';
      logo = '';
    }
  }
  return channels;
}

/// Mainland-TV heuristic: channel names containing CJK characters or the
/// state-broadcaster prefixes used by English-named feeds (CCTV, CGTN…).
/// Foreign channels in mixed playlists such as iptv-org are dropped.
final _mainlandCjk = RegExp(r'[一-鿿]');
final _mainlandPrefix =
    RegExp(r'^(cctv|cetv|chc|sitv|newtv|ihot|cnc)', caseSensitive: false);
// International feeds that pass the name check but are not Mandarin
// domestic channels (CGTN languages, CCTV+ wire feeds, part-time streams).
final _nonMandarin = RegExp(
    r'cgtn|cctv\+|阿语|俄语|法语|西语|阿文|英文|not 24/7',
    caseSensitive: false);
final _bracketTags = RegExp(r'\s*\[[^\]]*\]');
final _qualityTags = RegExp(r'\s*\(\d{3,4}[pi]\)');
final _cctvNumber = RegExp(r'^CCTV[-\s]?\d', caseSensitive: false);

bool isMainlandChannel(LiveChannel channel) =>
    (_mainlandCjk.hasMatch(channel.name) ||
        _mainlandPrefix.hasMatch(channel.name)) &&
    !_nonMandarin.hasMatch(channel.name);

/// '[Geo-blocked]' / '(720p)' tags leak into names from iptv-org.
String cleanChannelName(String name) => name
    .replaceAll(_bracketTags, '')
    .replaceAll(_qualityTags, '')
    .trim();

/// Dedupe key: 'CCTV-1综合', 'CCTV-1 HD' and 'CCTV-1' are the same channel;
/// '4K'/'8K'/'5+' suffixes keep their own key so 4K/体育赛事 stay distinct.
String _channelKey(String name) {
  final cleaned = cleanChannelName(name);
  final cctv =
      RegExp(r'CCTV[-\s]?(\d+K?\+?)', caseSensitive: false).firstMatch(cleaned);
  if (cctv != null) return 'cctv-${cctv.group(1)!.toLowerCase()}';
  return cleaned;
}

/// Filters foreign feeds, normalizes names, regroups numbered CCTV channels,
/// and dedupes so the first playlist wins each channel.
List<LiveChannel> mergeChannels(Iterable<LiveChannel> raw) {
  final seen = <String>{};
  return [
    for (final channel in raw)
      if (isMainlandChannel(channel) && seen.add(_channelKey(channel.name)))
        LiveChannel(
            name: cleanChannelName(channel.name),
            url: channel.url,
            // English-named CCTV feeds land in iptv-org groups like
            // 'General'; regroup numbered CCTV channels together.
            group: _cctvNumber.hasMatch(channel.name)
                ? '央视频道'
                : channel.group,
            logo: channel.logo,
            source: channel.source),
  ];
}

/// Fetches and merges all live playlists; results cache for the session.
class LiveCatalog extends ChangeNotifier {
  LiveCatalog({http.Client? client})
      : _client = client ?? http.Client(),
        _ownsClient = client == null;
  final http.Client _client;
  final bool _ownsClient;

  List<LiveChannel> channels = const [];
  bool loading = false;
  String? error;

  Future<void> load() async {
    if (loading) return;
    loading = true;
    error = null;
    notifyListeners();
    final merged = <LiveChannel>[];
    await Future.wait(livePlaylists.map((playlist) async {
      for (final url in playlist.urls) {
        try {
          final response = await _client
              .get(Uri.parse(url))
              .timeout(const Duration(seconds: 15));
          if (response.statusCode == 200 &&
              response.bodyBytes.length <= 4 * 1024 * 1024) {
            merged.addAll(parseLivePlaylist(utf8.decode(response.bodyBytes),
                source: playlist.name));
            break;
          }
        } catch (_) {}
      }
    }));
    channels = mergeChannels(merged);
    loading = false;
    error = channels.isEmpty ? '直播源加载失败，请检查网络后重试' : null;
    notifyListeners();
  }

  /// Group titles in first-seen order.
  List<String> get groups {
    final seen = <String>{};
    return [
      for (final channel in channels)
        if (channel.group.isNotEmpty && seen.add(channel.group)) channel.group,
    ];
  }

  List<LiveChannel> inGroup(String group) => group == '全部'
      ? channels
      : [for (final channel in channels) if (channel.group == group) channel];

  @override
  void dispose() {
    if (_ownsClient) _client.close();
    super.dispose();
  }
}
