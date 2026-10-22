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

  static int? ordinal(String name) =>
      int.tryParse(RegExp(r'^(?:第|ep)?0*(\d+)(?:集|话|期)?$', caseSensitive: false)
              .firstMatch(name.trim())
              ?.group(1) ??
          '');

  static Episode? onLine(
      List<Episode> target, Episode? current, List<Episode> previous) {
    if (target.isEmpty) return null;
    if (current != null) {
      for (final episode in target) {
        if (episode.name.trim() == current.name.trim() ||
            (ordinal(current.name) != null &&
                ordinal(episode.name) == ordinal(current.name))) {
          return episode;
        }
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
    this.posterFallbacks = const [],
    this.backdrop = '',
    this.description = '',
    this.category = '',
    this.categoryId = '',
    this.year = '',
    this.area = '',
    this.actors = '',
    this.director = '',
    this.language = '',
    this.duration = '',
    this.remarks = '',
    this.genres = '',
    this.rating,
    this.popularity,
    this.updatedAtMs,
    this.lines = const {},
  });

  final String id;
  final String title;
  final String source;
  final String? remoteId;
  final String poster;
  final List<String> posterFallbacks;
  final String backdrop;
  final String description;
  final String category;
  final String categoryId;
  final String year;
  final String area;
  final String actors;
  final String director;
  final String language;
  final String duration;
  final String remarks;
  final String genres;
  final double? rating;
  final int? popularity;
  final int? updatedAtMs;
  final Map<String, List<Episode>> lines;

  bool get playable => lines.values.any((episodes) => episodes.isNotEmpty);

  List<String> get posterCandidates =>
      catalogImageUrls([poster, ...posterFallbacks]);

  MediaEntry withArtworkFrom(Iterable<MediaEntry> variants) {
    final fallbacks = catalogImageUrls([
      ...posterFallbacks,
      for (final entry in variants) ...entry.posterCandidates,
    ])
      ..remove(catalogImageUrls([poster]).firstOrNull);
    final backdrops = catalogImageUrls([
      backdrop,
      for (final entry in variants) entry.backdrop,
    ]);
    if (fallbacks.isEmpty && (backdrops.firstOrNull ?? '') == backdrop) {
      return this;
    }
    return MediaEntry.fromJson({
      ...toJson(),
      'posterFallbacks': fallbacks,
      'backdrop': backdrops.firstOrNull ?? '',
    });
  }

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
        backdrop: catalogImageUrls([
              (item['vod_pic_slide'] ?? '').toString(),
              (item['backdrop'] ?? '').toString(),
            ]).firstOrNull ??
            '',
        description:
            cleanCatalogText(item['vod_content'] ?? item['description']),
        category: cleanCatalogText(item['type_name']),
        categoryId: (item['type_id'] ?? '').toString(),
        year: cleanCatalogText(item['vod_year']),
        area: cleanCatalogText(item['vod_area']),
        actors: cleanCatalogText(item['vod_actor']),
        director: cleanCatalogText(item['vod_director']),
        language: cleanCatalogText(item['vod_lang']),
        duration: cleanCatalogText(item['vod_duration']),
        remarks: cleanCatalogText(item['vod_remarks']),
        genres: cleanCatalogText(item['vod_class']),
        rating: catalogRating(item['vod_douban_score']) ??
            catalogRating(item['vod_score']),
        popularity: catalogCount(item['vod_hits']),
        updatedAtMs:
            catalogDate(item['vod_time']) ?? catalogDate(item['vod_time_add']),
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
        'posterFallbacks': posterFallbacks,
        'backdrop': backdrop,
        'description': description,
        'category': category,
        'categoryId': categoryId,
        'year': year,
        'area': area,
        'actors': actors,
        'director': director,
        'language': language,
        'duration': duration,
        'remarks': remarks,
        'genres': genres,
        'rating': rating,
        'popularity': popularity,
        'updatedAtMs': updatedAtMs,
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
      posterFallbacks: value['posterFallbacks'] is List
          ? catalogImageUrls(
              (value['posterFallbacks'] as List).whereType<String>())
          : const [],
      backdrop: value['backdrop']?.toString() ?? '',
      description: value['description']?.toString() ?? '',
      category: value['category']?.toString() ?? '',
      categoryId: value['categoryId']?.toString() ?? '',
      year: value['year']?.toString() ?? '',
      area: value['area']?.toString() ?? '',
      actors: value['actors']?.toString() ?? '',
      director: value['director']?.toString() ?? '',
      language: value['language']?.toString() ?? '',
      duration: value['duration']?.toString() ?? '',
      remarks: value['remarks']?.toString() ?? '',
      genres: value['genres']?.toString() ?? '',
      rating: catalogRating(value['rating']),
      popularity: catalogCount(value['popularity']),
      updatedAtMs: catalogCount(value['updatedAtMs']),
      lines: lines,
    );
  }

  static String encodeList(Iterable<MediaEntry> items) =>
      jsonEncode(items.map((item) => item.toJson()).toList());
}

List<String> catalogImageUrls(Iterable<String> values) => values
    .map((value) => value.trim().replaceAll('&amp;', '&'))
    .where((value) {
      final uri = Uri.tryParse(value);
      return uri != null &&
          uri.scheme == 'https' &&
          uri.host.isNotEmpty &&
          uri.userInfo.isEmpty;
    })
    .toSet()
    .toList();

String cleanCatalogText(Object? value) => (value ?? '')
    .toString()
    .replaceAll(RegExp(r'<[^>]*>'), '')
    .replaceAll('&nbsp;', ' ')
    .replaceAll('&amp;', '&')
    .replaceAll('&quot;', '"')
    .replaceAll(RegExp(r'\s+'), ' ')
    .trim();

double? catalogRating(Object? value) {
  final number = double.tryParse('$value');
  return number != null && number.isFinite && number > 0 && number <= 10
      ? number
      : null;
}

int? catalogCount(Object? value) {
  final number = int.tryParse('$value');
  return number != null && number > 0 ? number : null;
}

int? catalogDate(Object? value) {
  final number = catalogCount(value);
  final date = number == null
      ? DateTime.tryParse('$value')
      : number > 0 && number < 100000000000000
          ? DateTime.fromMillisecondsSinceEpoch(
              number < 100000000000 ? number * 1000 : number)
          : null;
  return date != null && date.year >= 1900 && date.year <= 2200
      ? date.millisecondsSinceEpoch
      : null;
}

String catalogKind(String category) {
  if ((category.contains('漫剧') && !category.contains('动漫')) ||
      (category.toUpperCase().contains('AI') && category.contains('短剧'))) {
    return 'AI短剧';
  }
  if (category.contains('短剧') || category.contains('爽剧')) return '短剧';
  if (category.contains('综艺')) return '综艺';
  if (category == '动画片' || category.endsWith('片') || category == '电影') {
    return '电影';
  }
  if (category.contains('动漫') || category == '动画') return '动漫';
  if (category.endsWith('剧')) return '电视剧';
  return category;
}

String catalogTitle(String title) =>
    cleanCatalogText(title).replaceAll(RegExp(r'\s+'), '').toLowerCase();

String catalogIdentity(MediaEntry entry) {
  final kind = catalogKind(entry.category);
  if (entry.year.isEmpty || kind.isEmpty) return 'id:${entry.id}';
  return jsonEncode([catalogTitle(entry.title), entry.year, kind]);
}

class CatalogGroup {
  CatalogGroup(this.entries);
  final List<MediaEntry> entries;
  MediaEntry get primary => entries
      .firstWhere((entry) => entry.playable, orElse: () => entries.first)
      .withArtworkFrom(entries);
}

Set<String> _catalogCast(String actors) => actors
    .split(RegExp(r'[,，、/|;；]+'))
    .map(catalogTitle)
    .where((name) => name.isNotEmpty && name != '未知')
    .toSet();

String _catalogYear(String year) =>
    RegExp(r'^(?:19|20|21)\d{2}(?:年)?$').hasMatch(year.trim())
        ? year.trim().substring(0, 4)
        : '';

bool sameCatalogVersion(MediaEntry a, MediaEntry b) {
  if (a.id == b.id) return true;
  final title = catalogTitle(a.title);
  final kind = catalogKind(a.category);
  if (title.isEmpty ||
      title != catalogTitle(b.title) ||
      kind.isEmpty ||
      kind != catalogKind(b.category)) {
    return false;
  }
  final year = _catalogYear(a.year);
  if (year.isEmpty || year != _catalogYear(b.year)) return false;
  final language = catalogTitle(a.language);
  final otherLanguage = catalogTitle(b.language);
  if (language.isNotEmpty &&
      otherLanguage.isNotEmpty &&
      language != otherLanguage) {
    return false;
  }
  final director = catalogTitle(a.director);
  final otherDirector = catalogTitle(b.director);
  if (director.isNotEmpty &&
      otherDirector.isNotEmpty &&
      director != otherDirector) {
    return false;
  }
  final actors = _catalogCast(a.actors);
  final otherActors = _catalogCast(b.actors);
  final shared = actors.intersection(otherActors);
  if (actors.isNotEmpty && otherActors.isNotEmpty && shared.isEmpty) {
    return false;
  }
  return true;
}

List<CatalogGroup> groupCatalog(Iterable<MediaEntry> entries,
    {String query = ''}) {
  final buckets = <String, List<CatalogGroup>>{};
  final result = <CatalogGroup>[];
  final seen = <String>{};
  for (final entry in entries) {
    if (!seen.add(entry.id)) continue;
    final key = jsonEncode([
      catalogTitle(entry.title),
      catalogKind(entry.category),
    ]);
    final bucket = buckets.putIfAbsent(key, () => []);
    CatalogGroup? match;
    for (final group in bucket) {
      if (group.entries.every((other) => sameCatalogVersion(other, entry))) {
        match = group;
        break;
      }
    }
    if (match == null) {
      match = CatalogGroup([]);
      bucket.add(match);
      result.add(match);
    }
    match.entries.add(entry);
  }
  if (query.trim().isNotEmpty) {
    final keyword = catalogTitle(query);
    int rank(CatalogGroup group) {
      final title = catalogTitle(group.primary.title);
      if (title == keyword) return 0;
      if (title.startsWith(keyword)) return 1;
      if (title.contains(keyword)) return 2;
      return 3;
    }

    final order = {for (var i = 0; i < result.length; i++) result[i]: i};
    result.sort((a, b) {
      final compared = rank(a).compareTo(rank(b));
      return compared != 0 ? compared : order[a]!.compareTo(order[b]!);
    });
  }
  return result;
}

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
  const CatalogListing(this.entries,
      {this.page = 1, this.pageCount = 1, this.total = 0});
  final List<MediaEntry> entries;
  final int page;
  final int pageCount;

  /// Server-reported category size, or 0 when absent.
  final int total;
  bool get hasMore => entries.isNotEmpty && page < pageCount;

  factory CatalogListing.parse(
      Object? value, String source, int requestedPage) {
    final entries = MediaEntry.parseResponse(value, source);
    final pages = value is Map
        ? int.tryParse((value['pagecount'] ?? '').toString()) ?? requestedPage
        : requestedPage;
    final total = value is Map
        ? int.tryParse((value['total'] ?? '').toString()) ?? 0
        : 0;
    return CatalogListing(entries,
        page: requestedPage,
        pageCount: pages < requestedPage ? requestedPage : pages,
        total: total);
  }
}
