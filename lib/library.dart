import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'catalog.dart';
import 'download.dart';
import 'offline_downloads.dart';
import 'source_presets.dart';

/// Rewritten optional adapter: `ac=videolist&wd=` is a commonly used JSON
/// dialect, not an endpoint or network request observed from the original APK.
class CatalogClient {
  CatalogClient({http.Client? client}) : _client = client ?? http.Client();
  final http.Client _client;

  Future<List<MediaEntry>> search(SourceEndpoint source, String query) async {
    if (!source.enabled || query.trim().isEmpty) return [];
    return _request(source, {'ac': 'videolist', 'wd': query.trim()});
  }

  Future<MediaEntry> detail(SourceEndpoint source, MediaEntry entry) async {
    if (!source.enabled) throw const FormatException('该源已停用');
    final id = entry.remoteId;
    if (id == null || id.isEmpty || entry.source != source.name) {
      throw const FormatException('缺少该源的资源 ID');
    }
    final results = await _request(source, {'ac': 'detail', 'ids': id});
    return results
        .firstWhere((item) => item.remoteId == id,
            orElse: () => throw const FormatException('详情没有返回对应资源'))
        .withArtworkFrom([entry]);
  }

  Future<List<MediaEntry>> _request(
          SourceEndpoint source, Map<String, String> parameters) async =>
      MediaEntry.parseResponse(await _json(source, parameters), source.name);

  Future<List<CatalogCategory>> categories(SourceEndpoint source) async =>
      CatalogCategory.parse(await _json(source, {'ac': 'list', 'pg': '1'}));

  Future<CatalogListing> browse(SourceEndpoint source,
      {String? categoryId, int page = 1}) async {
    if (page < 1) throw const FormatException('页码无效');
    return CatalogListing.parse(
        await _json(source, {
          'ac': 'videolist',
          'pg': '$page',
          if (categoryId != null && categoryId.isNotEmpty) 't': categoryId,
        }),
        source.name,
        page);
  }

  Future<Object?> _json(
      SourceEndpoint source, Map<String, String> parameters) async {
    if (!source.enabled) throw const FormatException('该源已停用');
    final endpoint = SourceEndpoint.parseHttps(source.url);
    final uri = endpoint.replace(queryParameters: {
      ...(Map.of(endpoint.queryParameters)
        ..removeWhere(
            (key, _) => const {'ac', 'wd', 'ids', 'pg', 't'}.contains(key))),
      ...parameters,
    });
    final request = http.Request('GET', uri)..followRedirects = false;
    final response = await _client.send(request).timeout(
          const Duration(seconds: 15),
        );
    if (response.statusCode != 200) {
      await response.stream.listen(null).cancel();
      throw HttpException('HTTP ${response.statusCode}', uri: uri);
    }
    final bytes = <int>[];
    await for (final chunk
        in response.stream.timeout(const Duration(seconds: 15))) {
      if (bytes.length + chunk.length > 2 * 1024 * 1024) {
        throw const FormatException('响应超过 2MB 上限');
      }
      bytes.addAll(chunk);
    }
    return jsonDecode(utf8.decode(bytes));
  }

  void dispose() => _client.close();
}

class WatchProgress {
  const WatchProgress(
      {this.positionMs = 0, this.durationMs = 0, this.completed = false});
  final int positionMs;
  final int durationMs;
  final bool completed;
  int? get percent => completed
      ? 100
      : durationMs > 0
          ? (positionMs * 100 ~/ durationMs).clamp(0, 99)
          : positionMs == 0
              ? 0
              : null;
  static String time(int ms) {
    final seconds = ms ~/ 1000;
    return '${seconds ~/ 60}:${(seconds % 60).toString().padLeft(2, '0')}';
  }

  String get label => completed
      ? '已看完 · 100%'
      : positionMs == 0
          ? '未观看 · 0%'
          : durationMs > 0
              ? '已观看 $percent% · ${time(positionMs)} / ${time(durationMs)}'
              : '已观看 ${time(positionMs)} · 比例待更新';
  Map<String, Object> toJson() =>
      {'position': positionMs, 'duration': durationMs, 'completed': completed};
}

class Library extends ChangeNotifier {
  Library(this._preferences, {OfflineDownloads? offline})
      : offline = offline ?? OfflineDownloads() {
    this.offline.addListener(notifyListeners);
  }

  final OfflineDownloads offline;

  final SharedPreferencesAsync _preferences;
  List<SourceEndpoint> sources = [];
  List<SourceEndpoint> get enabledSources =>
      sources.where((source) => source.enabled).toList();
  final Map<String, MediaEntry> favorites = {};
  final Map<String, MediaEntry> history = {};
  List<MediaEntry> get recentEntries {
    final seen = <String>{};
    return history.values
        .toList()
        .reversed
        .where((entry) => seen.add(catalogIdentity(entry)))
        .toList();
  }

  final Map<String, int> positionsMs = {};
  final Map<String, WatchProgress> _watchProgress = {};
  final Map<String, String> _lastEpisodes = {};
  Future<void>? _playbackWrites;
  bool _disposed = false;
  static const maxSearchHistory = 20;
  List<String> _searchHistory = [];
  List<String> get searchHistory => List.unmodifiable(_searchHistory);
  Future<void> _searchWrites = Future<void>.value();
  bool autoPlayNext = true;
  final Map<String, String> downloads = {};

  static Future<Library> open() async {
    final library = Library(SharedPreferencesAsync());
    await library.load();
    unawaited(library.offline.initialize());
    return library;
  }

  Future<void> load() async {
    final sourceText = await _preferences.getString('sources');
    final favoriteText = await _preferences.getString('favorites');
    final historyText = await _preferences.getString('history');
    final positionText = await _preferences.getString('positions');
    final downloadsText = await _preferences.getString('downloads');
    final searchText = await _preferences.getString('search_history');
    final watchText = await _preferences.getString('watch_progress');
    autoPlayNext = await _preferences.getBool('auto_play_next') ?? true;
    try {
      final seen = <String>{};
      _searchHistory = searchText == null
          ? []
          : (jsonDecode(searchText) as List)
              .whereType<String>()
              .map((query) => query.trim())
              .where(
                  (query) => query.isNotEmpty && seen.add(query.toLowerCase()))
              .take(maxSearchHistory)
              .toList();
    } on FormatException {
      _searchHistory = [];
    } on TypeError {
      _searchHistory = [];
    }
    var validSources = true;
    // Malformed previous state is ignored without overwriting the saved data.
    try {
      if (sourceText != null) {
        sources = (jsonDecode(sourceText) as List)
            .map(SourceEndpoint.fromJson)
            .toList();
      }
    } on FormatException {
      sources = [];
      validSources = false;
    } on TypeError {
      sources = [];
      validSources = false;
    }
    if (validSources &&
        await _preferences.getBool('public_sources_initialized_v2') != true) {
      final hadInitialPresets =
          await _preferences.getBool('public_sources_initialized_v1') == true;
      final merged = sources
          .where((source) => !retiredSourcePresetUrls.contains(source.url))
          .toList();
      for (final preset in sourcePresets) {
        if (hadInitialPresets && preset.introducedIn == 1) continue;
        if (!merged.any((source) =>
            source.name == preset.source.name ||
            source.url == preset.source.url)) {
          merged.add(preset.source);
        }
      }
      await _preferences.setString('sources',
          jsonEncode(merged.map((source) => source.toJson()).toList()));
      await _preferences.setBool('public_sources_initialized_v1', true);
      await _preferences.setBool('public_sources_initialized_v2', true);
      sources = merged;
    }
    for (final (text, output) in [
      (favoriteText, favorites),
      (historyText, history)
    ]) {
      try {
        if (text != null) {
          for (final item in jsonDecode(text) as List) {
            final entry = MediaEntry.fromJson(item);
            output[entry.id] = entry;
          }
        }
      } on FormatException {
        output.clear();
      } on TypeError {
        output.clear();
      }
    }
    try {
      if (positionText != null) {
        final data = jsonDecode(positionText) as Map;
        for (final item in data.entries) {
          if (item.key is String && item.value is int && item.value >= 0) {
            positionsMs[item.key as String] = item.value as int;
          }
        }
      }
      if (downloadsText != null) {
        final data = jsonDecode(downloadsText) as Map;
        for (final item in data.entries) {
          if (item.key is String && item.value is String) {
            downloads[item.key as String] = item.value as String;
          }
        }
      }
    } on FormatException {
      positionsMs.clear();
      downloads.clear();
    } on TypeError {
      positionsMs.clear();
      downloads.clear();
    }
    _watchProgress.clear();
    _lastEpisodes.clear();
    try {
      if (watchText != null) {
        final data = jsonDecode(watchText) as Map;
        for (final item in (data['episodes'] as Map).entries) {
          final value = item.value as Map;
          final position = value['position'];
          final duration = value['duration'];
          if (item.key is String &&
              position is int &&
              position >= 0 &&
              duration is int &&
              duration >= 0) {
            _watchProgress[item.key as String] = WatchProgress(
                positionMs: position,
                durationMs: duration,
                completed: value['completed'] == true);
          }
        }
        for (final item in (data['lastEpisodes'] as Map).entries) {
          if (item.key is String && item.value is String) {
            _lastEpisodes[item.key as String] = item.value as String;
          }
        }
      }
    } on FormatException {
      _watchProgress.clear();
      _lastEpisodes.clear();
    } on TypeError {
      _watchProgress.clear();
      _lastEpisodes.clear();
    }
    notifyListeners();
  }

  Future<void> addSource(SourceEndpoint source) async {
    SourceEndpoint.parseHttps(source.url);
    if (source.name.trim().isEmpty) throw const FormatException('源名称不能为空');
    await _saveSources(
        [...sources.where((s) => s.name != source.name), source]);
  }

  Future<void> setAutoPlayNext(bool value) async {
    await _preferences.setBool('auto_play_next', value);
    autoPlayNext = value;
    notifyListeners();
  }

  Future<void> _editSearchHistory(List<String> Function(List<String>) edit) {
    final operation = _searchWrites.then((_) async {
      final next = edit(_searchHistory);
      await _preferences.setString('search_history', jsonEncode(next));
      _searchHistory = next;
      notifyListeners();
    });
    _searchWrites = operation.catchError((Object _) {});
    return operation;
  }

  Future<void> recordSearch(String value) {
    final query = value.trim();
    if (query.isEmpty) return Future<void>.value();
    return _editSearchHistory((history) => [
          query,
          ...history.where((item) => item.toLowerCase() != query.toLowerCase()),
        ].take(maxSearchHistory).toList());
  }

  Future<void> removeSearch(String query) => _editSearchHistory(
      (history) => history.where((item) => item != query).toList());

  Future<void> clearSearchHistory() => _editSearchHistory((_) => []);

  Future<void> _saveSources(List<SourceEndpoint> next) async {
    await _preferences.setString(
        'sources', jsonEncode(next.map((s) => s.toJson()).toList()));
    sources = next;
    notifyListeners();
  }

  Future<void> removeSource(SourceEndpoint source) async {
    await _saveSources(sources.where((s) => s.name != source.name).toList());
  }

  Future<void> setSourceEnabled(SourceEndpoint source, bool enabled) async {
    await _saveSources([
      for (final item in sources)
        if (item.name == source.name && item.url == source.url)
          item.withEnabled(enabled)
        else
          item,
    ]);
  }

  bool isFavorite(MediaEntry entry) => favorites.values.any((saved) =>
      saved.id == entry.id || catalogIdentity(saved) == catalogIdentity(entry));

  Future<void> toggleFavorite(MediaEntry entry) async {
    if (isFavorite(entry)) {
      favorites.removeWhere((_, saved) =>
          saved.id == entry.id ||
          catalogIdentity(saved) == catalogIdentity(entry));
    } else {
      favorites[entry.id] = entry;
    }
    await _preferences.setString(
        'favorites', MediaEntry.encodeList(favorites.values));
    notifyListeners();
  }

  static String episodeKey(String id, Episode episode) =>
      jsonEncode([id, episode.url]);

  int resumePosition(String id, Episode episode) =>
      _watchProgress[episodeKey(id, episode)]?.positionMs ??
      positionsMs[episodeKey(id, episode)] ??
      0;

  WatchProgress watchProgress(String id, Episode episode) =>
      _watchProgress[episodeKey(id, episode)] ??
      WatchProgress(positionMs: resumePosition(id, episode));

  Episode? lastWatchedEpisode(MediaEntry entry) {
    final episodes = entry.lines.values.expand((line) => line).toList();
    for (final episode in episodes) {
      if (episode.url == _lastEpisodes[entry.id]) return episode;
    }
    for (final episode in episodes) {
      if (resumePosition(entry.id, episode) > 0) return episode;
    }
    return null;
  }

  String watchSummary(MediaEntry entry) {
    final episode = lastWatchedEpisode(entry);
    return [
      entry.source,
      if (episode != null) episode.name,
      if (episode != null) watchProgress(entry.id, episode).label else '暂无分集进度'
    ].join(' · ');
  }

  String? downloadedFile(String id, Episode episode) {
    final task = offline.find(id, episode);
    return task?.completed == true
        ? 'media3:${task!.id}'
        : downloads[episodeKey(id, episode)];
  }

  @override
  void dispose() {
    _disposed = true;
    offline.removeListener(notifyListeners);
    offline.dispose();
    super.dispose();
  }

  Future<void> recordPlay(MediaEntry entry,
      {Episode? episode, int? position, int? duration, bool? completed}) {
    history.remove(entry.id);
    history[entry.id] = entry;
    if (episode != null) {
      final key = episodeKey(entry.id, episode);
      final previous = watchProgress(entry.id, episode);
      final total =
          duration != null && duration > 0 ? duration : previous.durationMs;
      final finished = completed ?? previous.completed;
      final current = finished && total > 0
          ? total
          : position != null && position >= 0
              ? position
              : previous.positionMs;
      positionsMs[key] = current;
      _watchProgress[key] = WatchProgress(
          positionMs: current, durationMs: total, completed: finished);
      _lastEpisodes[entry.id] = episode.url;
    }
    final historyText = MediaEntry.encodeList(history.values);
    final positionText = jsonEncode(positionsMs);
    final watchText = jsonEncode({
      'episodes': {
        for (final item in _watchProgress.entries) item.key: item.value.toJson()
      },
      'lastEpisodes': _lastEpisodes
    });
    Future<void> persist() async {
      await _preferences.setString('history', historyText);
      await _preferences.setString('positions', positionText);
      await _preferences.setString('watch_progress', watchText);
      if (!_disposed) notifyListeners();
    }

    final operation = _playbackWrites?.then((_) => persist()) ?? persist();
    _playbackWrites = operation.catchError((Object _) {});
    return operation;
  }

  final Set<String> _activeDownloads = {};

  Future<String> download(
    Episode episode,
    String id, {
    Map<String, String> headers = const {},
    void Function(int received, int? total)? onProgress,
  }) async {
    final key = episodeKey(id, episode);
    if (!_activeDownloads.add(key)) {
      throw const FormatException('该集正在下载');
    }
    try {
      final dir = await getApplicationDocumentsDirectory();
      final safeName = sha256.convert(utf8.encode(key)).toString();
      final destination = Directory('${dir.path}/$safeName');
      final existing = downloads[key];
      if (existing != null && await File(existing).exists()) return existing;
      final downloader = MediaDownloader();
      try {
        final path = await downloader.download(episode.url, destination,
            headers: headers, onProgress: onProgress);
        final next = {...downloads, key: path};
        await _preferences.setString('downloads', jsonEncode(next));
        downloads[key] = path;
        notifyListeners();
        return path;
      } finally {
        downloader.close();
      }
    } finally {
      _activeDownloads.remove(key);
    }
  }
}
