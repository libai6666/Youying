import 'dart:async';
import 'dart:collection';
import 'dart:convert';

import 'catalog.dart';
import 'library.dart';

Set<String> _cast(String names) => names
    .split(RegExp(r'[,，、/]+'))
    .map(catalogTitle)
    .where((name) =>
        name.isNotEmpty && !const {'未知', '不详', '内详', '-'}.contains(name))
    .toSet();

bool matchingArtwork(MediaEntry work, MediaEntry candidate) {
  if (catalogTitle(work.title) != catalogTitle(candidate.title) ||
      catalogTitle(work.title).isEmpty ||
      catalogKind(work.category).isEmpty ||
      catalogKind(work.category) != catalogKind(candidate.category)) {
    return false;
  }
  final sharedActors = _cast(work.actors).intersection(_cast(candidate.actors));
  if (work.director.isNotEmpty &&
      candidate.director.isNotEmpty &&
      catalogTitle(work.director) != catalogTitle(candidate.director)) {
    return false;
  }
  if (work.actors.isNotEmpty &&
      candidate.actors.isNotEmpty &&
      sharedActors.isEmpty) {
    return false;
  }
  if (work.year.isNotEmpty && work.year == candidate.year) return true;
  final sameDirector = work.director.isNotEmpty &&
      catalogTitle(work.director) == catalogTitle(candidate.director);
  return sharedActors.length >= 2 || (sameDirector && sharedActors.isNotEmpty);
}

class _ArtworkCache {
  _ArtworkCache(this.result, this.expires);
  final Future<List<String>> result;
  final DateTime expires;
}

class ArtworkResolver {
  ArtworkResolver(this.client, this.sources);
  final CatalogClient client;
  final List<SourceEndpoint> Function() sources;
  final Map<String, _ArtworkCache> _cache = {};
  final Queue<Completer<void>> _waiting = Queue();
  final Set<Completer<List<MediaEntry>>> _searches = {};
  int _active = 0;
  int _pending = 0;
  bool _disposed = false;

  Future<List<String>> find(MediaEntry entry) {
    if (_disposed ||
        entry.title.trim().isEmpty ||
        catalogKind(entry.category).isEmpty) {
      return Future.value([]);
    }
    final enabled = sources().where((s) => s.enabled).toList();
    final key = jsonEncode([
      entry.id,
      entry.title,
      entry.year,
      entry.category,
      entry.actors,
      entry.director,
      for (final s in enabled) [s.name, s.url],
    ]);
    final cached = _cache[key];
    if (cached != null && DateTime.now().isBefore(cached.expires)) {
      return cached.result;
    }
    if (_pending >= 16) return Future.value([]);
    _pending++;
    final result = _lookup(entry, enabled).then((urls) {
      if (!_disposed) {
        _cache[key] = _ArtworkCache(
            Future.value(urls),
            DateTime.now().add(urls.isEmpty
                ? const Duration(minutes: 2)
                : const Duration(minutes: 10)));
      }
      return urls;
    }).whenComplete(() => _pending--);
    if (_cache.length >= 64) _cache.remove(_cache.keys.first);
    _cache[key] =
        _ArtworkCache(result, DateTime.now().add(const Duration(minutes: 2)));
    return result;
  }

  Future<List<String>> _lookup(
      MediaEntry entry, List<SourceEndpoint> enabled) async {
    if (_active >= 2) {
      final wait = Completer<void>();
      _waiting.add(wait);
      await wait.future;
    } else {
      _active++;
    }
    try {
      final urls = <String>[];
      for (final source in enabled) {
        if (_disposed) break;
        if (source.name == entry.source) continue;
        try {
          final matches = await _search(source, entry.title);
          for (final other in matches.take(30)) {
            if (!matchingArtwork(entry, other)) continue;
            for (final url in other.posterCandidates) {
              if (!entry.posterCandidates.contains(url) &&
                  !urls.contains(url)) {
                urls.add(url);
              }
            }
          }
          if (urls.length >= 8) break;
        } catch (_) {
          // A broken source must not hide artwork found on another source.
        }
      }
      return urls;
    } finally {
      if (!_disposed) {
        if (_waiting.isEmpty) {
          _active--;
        } else {
          _waiting.removeFirst().complete();
        }
      }
    }
  }

  Future<List<MediaEntry>> _search(SourceEndpoint source, String title) {
    final result = Completer<List<MediaEntry>>();
    _searches.add(result);
    Future.sync(() => client.search(source, title)).then((entries) {
      if (!result.isCompleted) result.complete(entries);
    }, onError: (Object _) {
      if (!result.isCompleted) result.complete([]);
    });
    return result.future.whenComplete(() {
      _searches.remove(result);
    });
  }

  void dispose() {
    _disposed = true;
    for (final search in _searches.toList()) {
      if (!search.isCompleted) search.complete([]);
    }
    for (final wait in _waiting.toList()) {
      if (!wait.isCompleted) wait.complete();
    }
    _waiting.clear();
    _cache.clear();
  }
}
