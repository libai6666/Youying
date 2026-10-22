import 'dart:convert';

import 'package:http/http.dart' as http;

import 'catalog.dart';

/// A video rendition declared by an HLS master playlist.
class HlsVariant {
  const HlsVariant(
      {required this.uri, this.width = 0, this.height = 0, this.bandwidth = 0});
  final Uri uri;
  final int width;
  final int height;
  final int bandwidth;

  String get label => height > 0
      ? '${height}p'
      : bandwidth > 0
          ? '${(bandwidth / 1000).round()}k'
          : '默认';
}

/// Extracts `#EXT-X-STREAM-INF` variants. Returns an empty list for media
/// playlists or invalid input.
List<HlsVariant> parseMasterVariants(String text, Uri base) {
  final lines = const LineSplitter().convert(text.trim());
  if (lines.isEmpty || lines.first.trim() != '#EXTM3U') return const [];
  final variants = <HlsVariant>[];
  int? pending;
  var width = 0;
  var height = 0;
  var bandwidth = 0;
  for (final raw in lines.skip(1)) {
    final line = raw.trim();
    if (line.isEmpty) continue;
    if (line.startsWith('#EXT-X-STREAM-INF:')) {
      if (pending != null) return const [];
      final attributes = line.substring(line.indexOf(':') + 1);
      final resolution =
          RegExp(r'RESOLUTION=(\d+)x(\d+)').firstMatch(attributes);
      width = int.tryParse(resolution?.group(1) ?? '') ?? 0;
      height = int.tryParse(resolution?.group(2) ?? '') ?? 0;
      bandwidth = int.tryParse(
              RegExp(r'BANDWIDTH=(\d+)').firstMatch(attributes)?.group(1) ??
                  '') ??
          0;
      pending = 1;
    } else if (!line.startsWith('#')) {
      if (pending == null) return const [];
      final uri = base.resolve(line);
      if (uri.scheme == 'https' &&
          uri.host.isNotEmpty &&
          uri.userInfo.isEmpty) {
        variants.add(HlsVariant(
            uri: uri, width: width, height: height, bandwidth: bandwidth));
      }
      pending = null;
    }
  }
  return List.unmodifiable(variants);
}

/// Highest declared height of an episode playlist, or null when the address
/// is not a master playlist / cannot be fetched. Media playlists report no
/// resolution metadata, so this only answers for master playlists.
Future<int?> probeEpisodeHeight(String url,
    {http.Client? client,
    Map<String, String> headers = const {},
    Duration timeout = const Duration(seconds: 10)}) async {
  final uri = SourceEndpoint.parseHttps(url);
  if (!RegExp(r'\.m3u8$', caseSensitive: false).hasMatch(uri.path)) return null;
  final ownsClient = client == null;
  final httpClient = client ?? http.Client();
  try {
    final response = await httpClient
        .get(uri, headers: headers)
        .timeout(timeout);
    if (response.statusCode != 200 ||
        response.bodyBytes.length > 2 * 1024 * 1024) {
      return null;
    }
    final variants = parseMasterVariants(utf8.decode(response.bodyBytes), uri);
    if (variants.isEmpty) return null;
    return variants
        .map((variant) => variant.height)
        .reduce((a, b) => a > b ? a : b);
  } on FormatException {
    return null;
  } on http.ClientException {
    return null;
  } catch (_) {
    return null;
  } finally {
    if (ownsClient) httpClient.close();
  }
}

/// Resolves the variant playlist closest to [targetHeight] for download.
/// Returns null when the address has no variants or cannot be fetched.
Future<String?> variantUrlForHeight(String url, int targetHeight,
    {http.Client? client,
    Map<String, String> headers = const {},
    Duration timeout = const Duration(seconds: 10)}) async {
  if (targetHeight <= 0) return null;
  final uri = SourceEndpoint.parseHttps(url);
  if (!RegExp(r'\.m3u8$', caseSensitive: false).hasMatch(uri.path)) return null;
  final ownsClient = client == null;
  final httpClient = client ?? http.Client();
  try {
    final response = await httpClient
        .get(uri, headers: headers)
        .timeout(timeout);
    if (response.statusCode != 200 ||
        response.bodyBytes.length > 2 * 1024 * 1024) {
      return null;
    }
    final variants = parseMasterVariants(utf8.decode(response.bodyBytes), uri)
        .where((variant) => variant.height > 0)
        .toList();
    if (variants.length < 2) return null;
    variants.sort((a, b) => (a.height - targetHeight)
        .abs()
        .compareTo((b.height - targetHeight).abs()));
    return variants.first.uri.toString();
  } catch (_) {
    return null;
  } finally {
    if (ownsClient) httpClient.close();
  }
}

/// Returns the choice whose probed height strictly exceeds the current
/// entry's height, or null. Unknown heights count as zero; ties keep the
/// current entry to avoid pointless reloads.
MediaEntry? highestHeightChoice(Iterable<MediaEntry> choices,
    Map<String, int?> heights, String currentId) {
  var bestHeight = heights[currentId] ?? 0;
  MediaEntry? best;
  for (final choice in choices) {
    final height = heights[choice.id] ?? 0;
    if (height > bestHeight) {
      bestHeight = height;
      best = choice;
    }
  }
  return best;
}

final _episodeHeightCache = <String, int?>{};

String? _firstPlaylistUrl(MediaEntry entry) {
  for (final line in entry.lines.values) {
    for (final episode in line) {
      final uri = Uri.tryParse(episode.url);
      if (uri != null &&
          uri.scheme == 'https' &&
          RegExp(r'\.m3u8$', caseSensitive: false).hasMatch(uri.path)) {
        return episode.url;
      }
    }
  }
  return null;
}

/// Probes each entry's first playlist once and caches the result per entry id.
/// At most three fetches run concurrently; failures cache as null.
Future<Map<String, int?>> probeEntryHeights(Iterable<MediaEntry> entries,
    {http.Client? client}) async {
  final result = <String, int?>{};
  final pending = [
    for (final entry in entries)
      if (!_episodeHeightCache.containsKey(entry.id)) entry,
  ];
  final ownsClient = client == null;
  final httpClient = client ?? http.Client();
  try {
    for (var start = 0; start < pending.length; start += 3) {
      await Future.wait(pending.skip(start).take(3).map((entry) async {
        final url = _firstPlaylistUrl(entry);
        _episodeHeightCache[entry.id] =
            url == null ? null : await probeEpisodeHeight(url, client: httpClient);
      }));
    }
  } finally {
    if (ownsClient) httpClient.close();
  }
  for (final entry in entries) {
    result[entry.id] = _episodeHeightCache[entry.id];
  }
  return result;
}
