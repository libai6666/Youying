import 'dart:convert';

Map<String, String> parseHeaders(String text) {
  if (text.trim().isEmpty) return {};
  final value = jsonDecode(text);
  if (value is! Map) throw const FormatException('请求头必须是 JSON 对象');
  final headers = <String, String>{};
  final token = RegExp(r"^[!#$%&'*+.^_`|~0-9A-Za-z-]+$");
  for (final entry in value.entries) {
    if (entry.key is! String ||
        entry.value is! String ||
        !token.hasMatch(entry.key as String) ||
        (entry.value as String).contains(RegExp(r'[\r\n]'))) {
      throw const FormatException('请求头字段无效');
    }
    headers[entry.key as String] = entry.value as String;
  }
  return headers;
}

/// All types in this file are independently rewritten. They are NOT decompiled Dart.
/// `vod_name` is observed in the verified AOT String cluster. The JSON adapter
/// below is an explicitly opt-in compatibility adapter, not a recovered API.
class SourceEndpoint {
  const SourceEndpoint(
      {required this.name, required this.url, this.enabled = true});

  final String name;
  final String url;
  final bool enabled;

  SourceEndpoint withEnabled(bool value) =>
      SourceEndpoint(name: name, url: url, enabled: value);

  static Uri parseHttps(String input) {
    final uri = Uri.tryParse(input.trim());
    if (uri == null ||
        uri.scheme != 'https' ||
        uri.host.isEmpty ||
        uri.userInfo.isNotEmpty) {
      throw const FormatException('请填写不含用户名或密码的 HTTPS 地址');
    }
    return uri;
  }

  Map<String, Object> toJson() =>
      {'name': name, 'url': url, 'enabled': enabled};

  factory SourceEndpoint.fromJson(Object? input) {
    if (input is! Map) throw const FormatException('无效的源配置');
    final name = input['name'];
    final url = input['url'];
    if (name is! String || name.trim().isEmpty || url is! String) {
      throw const FormatException('无效的源配置');
    }
    parseHttps(url);
    if (input['enabled'] != null && input['enabled'] is! bool) {
      throw const FormatException('源启用状态无效');
    }
    return SourceEndpoint(
        name: name.trim(),
        url: url.trim(),
        enabled: input['enabled'] as bool? ?? true);
  }
}

class Episode {
  const Episode({required this.name, required this.url});
  final String name;
  final String url;

  static Episode? onLine(
      List<Episode> target, Episode? current, List<Episode> previous) {
    if (target.isEmpty) return null;
    if (current != null) {
      for (final episode in target) {
        if (episode.name.trim() == current.name.trim()) return episode;
      }
      final index =
          previous.indexWhere((episode) => episode.url == current.url);
      if (index >= 0 && index < target.length) return target[index];
    }
    return target.first;
  }
}

class MediaEntry {
  const MediaEntry({
    required this.id,
    required this.title,
    required this.source,
    this.remoteId,
    this.poster = '',
    this.description = '',
    this.category = '',
    this.categoryId = '',
    this.year = '',
    this.area = '',
    this.actors = '',
    this.remarks = '',
    this.lines = const {},
  });

  final String id;
  final String title;
  final String source;
  final String? remoteId;
  final String poster;
  final String description;
  final String category;
  final String categoryId;
  final String year;
  final String area;
  final String actors;
  final String remarks;
  final Map<String, List<Episode>> lines;

  bool get playable => lines.values.any((episodes) => episodes.isNotEmpty);

  static List<MediaEntry> parseResponse(Object? value, String source) {
    // Common JSON-list dialect, NOT evidence of the APK's upstream protocol.
    Object? entries = value;
    if (entries is Map) {
      entries = entries['list'] ?? entries['data'];
      if (entries is Map) entries = entries['list'] ?? entries['items'];
    }
    if (entries is! List) throw const FormatException('返回的 JSON 没有列表');
    final output = <MediaEntry>[];
    for (final item in entries) {
      if (item is! Map) continue;
      final title = (item['vod_name'] ?? item['title'])?.toString().trim();
      if (title == null || title.isEmpty) continue;
      final itemId = (item['vod_id'] ?? item['id'] ?? title).toString();
      final lines = <String, List<Episode>>{};
      final rawLines = (item['vod_play_url'] ?? item['play_url'])?.toString();
      if (rawLines != null) {
        final names = (item['vod_play_from'] ?? '').toString().split(r'$$$');
        final groups = rawLines.split(r'$$$');
        for (var i = 0; i < groups.length; i++) {
          final episodes = <Episode>[];
          for (final part in groups[i].split('#')) {
            final sep = part.indexOf(r'$');
            final label = sep < 0 ? '播放' : part.substring(0, sep).trim();
            final link = (sep < 0 ? part : part.substring(sep + 1)).trim();
            final uri = Uri.tryParse(link);
            if (uri == null ||
                uri.scheme != 'https' ||
                uri.host.isEmpty ||
                uri.userInfo.isNotEmpty ||
                !RegExp(r'\.(m3u8|mp4|webm|mpd)$', caseSensitive: false)
                    .hasMatch(uri.path)) {
              continue;
            }
            episodes
                .add(Episode(name: label.isEmpty ? '播放' : label, url: link));
          }
          if (episodes.isNotEmpty) {
            final named = i < names.length ? names[i].trim() : '';
            final label = named.isEmpty ? '线路 ${i + 1}' : named;
            lines[lines.containsKey(label) ? '$label (${i + 1})' : label] =
                episodes;
          }
        }
      }
      output.add(MediaEntry(
        id: '$source:$itemId',
        title: title,
        source: source,
        remoteId: (item['vod_id'] ?? item['id'])?.toString(),
        poster: (item['vod_pic'] ?? item['poster'] ?? '').toString(),
        description:
            cleanCatalogText(item['vod_content'] ?? item['description']),
        category: cleanCatalogText(item['type_name']),
        categoryId: (item['type_id'] ?? '').toString(),
        year: cleanCatalogText(item['vod_year']),
        area: cleanCatalogText(item['vod_area']),
        actors: cleanCatalogText(item['vod_actor']),
        remarks: cleanCatalogText(item['vod_remarks']),
        lines: lines,
      ));
    }
    return output;
  }

  Map<String, Object?> toJson() => {
        'id': id,
        'title': title,
        'source': source,
        'remoteId': remoteId,
        'poster': poster,
        'description': description,
        'category': category,
        'categoryId': categoryId,
        'year': year,
        'area': area,
        'actors': actors,
        'remarks': remarks,
        'lines': lines.map((key, episodes) => MapEntry(
              key,
              episodes.map((e) => {'name': e.name, 'url': e.url}).toList(),
            )),
      };

  factory MediaEntry.fromJson(Object? value) {
    if (value is! Map) throw const FormatException('无效的收藏');
    final rawLines = value['lines'];
    final lines = <String, List<Episode>>{};
    if (rawLines is Map) {
      for (final pair in rawLines.entries) {
        if (pair.key is! String || pair.value is! List) continue;
        final episodes = <Episode>[];
        for (final entry in pair.value as List) {
          if (entry is Map &&
              entry['name'] is String &&
              entry['url'] is String) {
            episodes.add(Episode(
                name: entry['name'] as String, url: entry['url'] as String));
          }
        }
        lines[pair.key as String] = episodes;
      }
    }
    return MediaEntry(
      id: value['id'].toString(),
      title: value['title'].toString(),
      source: value['source'].toString(),
      remoteId: value['remoteId']?.toString(),
      poster: value['poster']?.toString() ?? '',
      description: value['description']?.toString() ?? '',
      category: value['category']?.toString() ?? '',
      categoryId: value['categoryId']?.toString() ?? '',
      year: value['year']?.toString() ?? '',
      area: value['area']?.toString() ?? '',
      actors: value['actors']?.toString() ?? '',
      remarks: value['remarks']?.toString() ?? '',
      lines: lines,
    );
  }

  static String encodeList(Iterable<MediaEntry> items) =>
      jsonEncode(items.map((item) => item.toJson()).toList());
}

String cleanCatalogText(Object? value) => (value ?? '')
    .toString()
    .replaceAll(RegExp(r'<[^>]*>'), '')
    .replaceAll('&nbsp;', ' ')
    .replaceAll('&amp;', '&')
    .replaceAll('&quot;', '"')
    .replaceAll(RegExp(r'\s+'), ' ')
    .trim();

class CatalogCategory {
  const CatalogCategory(this.id, this.name, {this.parentId = '0'});
  final String id;
  final String name;
  final String parentId;

  static List<CatalogCategory> parse(Object? value) {
    if (value is! Map || value['class'] is! List) return [];
    final result = <CatalogCategory>[];
    for (final row in value['class'] as List) {
      if (row is! Map) continue;
      final id = row['type_id']?.toString() ?? '';
      final name = cleanCatalogText(row['type_name']);
      if (id.isEmpty || name.isEmpty || result.any((c) => c.id == id)) continue;
      result.add(CatalogCategory(id, name,
          parentId: (row['type_pid'] ?? '0').toString()));
    }
    return result;
  }
}

class CatalogListing {
  const CatalogListing(this.entries, {this.page = 1, this.pageCount = 1});
  final List<MediaEntry> entries;
  final int page;
  final int pageCount;
  bool get hasMore => entries.isNotEmpty && page < pageCount;

  factory CatalogListing.parse(
      Object? value, String source, int requestedPage) {
    final entries = MediaEntry.parseResponse(value, source);
    final pages = value is Map
        ? int.tryParse((value['pagecount'] ?? '').toString()) ?? requestedPage
        : requestedPage;
    return CatalogListing(entries,
        page: requestedPage,
        pageCount: pages < requestedPage ? requestedPage : pages);
  }
}
