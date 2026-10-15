import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:shared_preferences_platform_interface/shared_preferences_async_platform_interface.dart';
import 'package:youying/catalog.dart';
import 'package:youying/directory.dart';
import 'package:youying/library.dart';
import 'package:youying/source_presets.dart';

final class _NoStorage extends SharedPreferencesAsyncPlatform {
  @override
  dynamic noSuchMethod(Invocation invocation) => throw StateError('No writes');
}

void main() {
  test('public directory search and detail return actual source data',
      () async {
    SharedPreferencesAsyncPlatform.instance = _NoStorage();
    final library = Library(SharedPreferencesAsync())
      ..sources = sourcePresets.map((p) => p.source).toList();
    final probe = CatalogClient();
    addTearDown(probe.dispose);
    try {
      final categories = await probe.categories(library.sources.first);
      debugPrint('First provider categories: ${categories.length}');
    } catch (failure) {
      debugPrint('First provider diagnostic: $failure');
    }
    final controller = DirectoryController(library);
    addTearDown(controller.dispose);
    await controller.refresh();
    debugPrint('Category failures: ${controller.sourceIssues.keys.join(', ')}');
    for (final label in ['电影', '电视剧', '综艺', '动漫']) {
      await controller.loadLabel(label);
      final feed = controller.feedFor(label)!;
      debugPrint(
          '$label: ${feed.entries.length} works, ${feed.rawEntries.length} source records; ${feed.issues.length} failed partitions');
      expect(feed.entries, isNotEmpty,
          reason: '$label must contain actual source entries');
      expect(
          feed.entries.every(
              (entry) => library.sources.any((s) => s.name == entry.source)),
          true);
    }
    debugPrint(
        'Unavailable category providers: ${controller.sourceIssues.keys.join(', ')}');
    final results = <MediaEntry>[];
    var searchFailures = 0;
    for (var start = 0; start < library.sources.length; start += 3) {
      await Future.wait(library.sources.skip(start).take(3).map((source) async {
        try {
          results.addAll(await probe.search(source, '三体'));
        } catch (_) {
          searchFailures++;
        }
      }));
    }
    final groups = groupCatalog(results, query: '三体');
    expect(groups, isNotEmpty);
    final selected = groups.first.primary;
    expect(selected.title.contains('三体'), true);
    final source = library.sources.firstWhere((s) => s.name == selected.source);
    final detail = await probe.detail(source, selected);
    expect(detail.remoteId, selected.remoteId);
    expect(detail.playable, true);
    debugPrint(
        'Search: ${results.length} source records, ${groups.length} works; $searchFailures failed providers');
    debugPrint(
        'Selected detail: ${detail.lines.length} supported-URL playlists (media playback not tested)');
  },
      skip: !const bool.fromEnvironment('YOUYING_LIVE_SOURCES'),
      timeout: const Timeout(Duration(minutes: 4)));
}
