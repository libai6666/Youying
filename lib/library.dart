import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'catalog.dart';

/// Rewritten optional adapter: `ac=videolist&wd=` is a commonly used JSON
/// dialect, not an endpoint or network request observed from the original APK.
class CatalogClient {
  CatalogClient({http.Client? client}) : _client = client ?? http.Client();
  final http.Client _client;

  Future<List<MediaEntry>> search(SourceEndpoint source, String query) async {
    if (query.trim().isEmpty) return [];
    final endpoint = SourceEndpoint.parseHttps(source.url);
    final uri = endpoint.replace(queryParameters: {
      ...endpoint.queryParameters,
      'ac': 'videolist',
      'wd': query.trim(),
    });
    final request = http.Request('GET', uri)..followRedirects = false;
    final response = await _client.send(request).timeout(
          const Duration(seconds: 15),
        );
    if (response.statusCode != 200) {
      throw HttpException('HTTP ${response.statusCode}', uri: uri);
    }
    final bytes = <int>[];
    await for (final chunk in response.stream.timeout(const Duration(seconds: 15))) {
      if (bytes.length + chunk.length > 2 * 1024 * 1024) {
        throw const FormatException('响应超过 2MB 上限');
      }
      bytes.addAll(chunk);
    }
    return MediaEntry.parseResponse(jsonDecode(utf8.decode(bytes)), source.name);
  }

  void dispose() => _client.close();
}

class Library extends ChangeNotifier {
  Library(this._preferences);

  final SharedPreferencesAsync _preferences;
  List<SourceEndpoint> sources = [];
  final Map<String, MediaEntry> favorites = {};
  final Map<String, MediaEntry> history = {};
  final Map<String, int> positionsMs = {};
  final Map<String, String> downloads = {};

  static Future<Library> open() async {
    final library = Library(SharedPreferencesAsync());
    await library.load();
    return library;
  }

  Future<void> load() async {
    final sourceText = await _preferences.getString('sources');
    final favoriteText = await _preferences.getString('favorites');
    final historyText = await _preferences.getString('history');
    final positionText = await _preferences.getString('positions');
    final downloadsText = await _preferences.getString('downloads');
    // Malformed previous state is ignored without claiming source data exists.
    try {
      if (sourceText != null) {
        sources = (jsonDecode(sourceText) as List)
            .map(SourceEndpoint.fromJson)
            .toList();
      }
    } on FormatException {
      sources = [];
    } on TypeError {
      sources = [];
    }
    for (final (text, output) in [(favoriteText, favorites), (historyText, history)]) {
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
    notifyListeners();
  }

  Future<void> addSource(SourceEndpoint source) async {
    SourceEndpoint.parseHttps(source.url);
    if (source.name.trim().isEmpty) throw const FormatException('源名称不能为空');
    sources = [...sources.where((s) => s.name != source.name), source];
    await _preferences.setString('sources', jsonEncode(sources.map((s) => s.toJson()).toList()));
    notifyListeners();
  }

  Future<void> removeSource(SourceEndpoint source) async {
    sources = sources.where((s) => s.name != source.name).toList();
    await _preferences.setString('sources', jsonEncode(sources.map((s) => s.toJson()).toList()));
    notifyListeners();
  }

  Future<void> toggleFavorite(MediaEntry entry) async {
    if (favorites.containsKey(entry.id)) {
      favorites.remove(entry.id);
    } else {
      favorites[entry.id] = entry;
    }
    await _preferences.setString('favorites', MediaEntry.encodeList(favorites.values));
    notifyListeners();
  }

  static String episodeKey(String id, Episode episode) => jsonEncode([id, episode.url]);

  int resumePosition(String id, Episode episode) => positionsMs[episodeKey(id, episode)] ?? 0;

  String? downloadedFile(String id, Episode episode) => downloads[episodeKey(id, episode)];

  Future<void> recordPlay(MediaEntry entry, {Episode? episode, int? position}) async {
    history.remove(entry.id);
    history[entry.id] = entry;
    if (episode != null && position != null && position >= 0) {
      positionsMs[episodeKey(entry.id, episode)] = position;
    }
    await _preferences.setString('history', MediaEntry.encodeList(history.values));
    await _preferences.setString('positions', jsonEncode(positionsMs));
    notifyListeners();
  }

  /// Foreground-only direct MP4/WebM download. HLS, DASH, DRM and the
  /// original background curl_task protocol have not been recovered.
  Future<String> download(Episode episode, String id) async {
    final url = SourceEndpoint.parseHttps(episode.url);
    final ext = url.path.toLowerCase().endsWith('.mp4')
        ? '.mp4'
        : url.path.toLowerCase().endsWith('.webm')
            ? '.webm'
            : null;
    if (ext == null) throw const FormatException('只支持直接 MP4/WebM 文件，暂不支持分片与 DRM');
    final dir = await getApplicationDocumentsDirectory();
    final key = episodeKey(id, episode);
    final safeName = sha256.convert(utf8.encode(key)).toString();
    final file = File('${dir.path}/$safeName$ext');
    final temp = File('${file.path}.partial');
    final client = http.Client();
    try {
      final request = http.Request('GET', url)..followRedirects = false;
      final response = await client.send(request).timeout(
            const Duration(seconds: 20),
          );
      if (response.statusCode != 200 || response.contentLength == null) {
        throw HttpException('下载失败: HTTP ${response.statusCode} 或未知长度');
      }
      // Bound storage use and reject indefinite streams.
      if (response.contentLength! > 2 * 1024 * 1024 * 1024) {
        throw const FormatException('文件超过 2GB 限制');
      }
      var received = 0;
      final sink = temp.openWrite();
      try {
        await for (final chunk in response.stream.timeout(const Duration(seconds: 30))) {
          received += chunk.length;
          if (received > response.contentLength! || received > 2 * 1024 * 1024 * 1024) {
            throw const FormatException('下载大小不符');
          }
          sink.add(chunk);
        }
        await sink.flush();
      } finally {
        await sink.close();
      }
      if (received != response.contentLength) throw const FormatException('下载未完成');
      await temp.rename(file.path);
      downloads[key] = file.path;
      await _preferences.setString('downloads', jsonEncode(downloads));
      notifyListeners();
      return file.path;
    } finally {
      client.close();
      if (await temp.exists()) await temp.delete();
    }
  }
}
