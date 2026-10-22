import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:shared_preferences_platform_interface/shared_preferences_async_platform_interface.dart';
import 'package:youying/main.dart';
import 'package:youying/ui_locale.dart';

import 'home_test.dart' show PreviewCatalog, previewLibrary;

final class _EmptyPreferences extends SharedPreferencesAsyncPlatform {
  @override
  Future<String?> getString(
          String key, SharedPreferencesOptions options) async =>
      key == 'sources' ? '[]' : null;
  @override
  Future<bool?> getBool(String key, SharedPreferencesOptions options) async =>
      true;
  @override
  Future<void> setString(
      String key, String value, SharedPreferencesOptions options) async {}
  @override
  Future<void> setBool(
      String key, bool value, SharedPreferencesOptions options) async {}
  @override
  dynamic noSuchMethod(Invocation invocation) =>
      throw StateError('Unexpected storage call');
}

void main() {
  setUp(() => SharedPreferencesAsyncPlatform.instance = _EmptyPreferences());

  testWidgets(
      'app follows system language changes and preserves system font scaling',
      (tester) async {
    tester.platformDispatcher.localesTestValue = const [Locale('en', 'US')];
    tester.platformDispatcher.textScaleFactorTestValue = 1.8;
    addTearDown(tester.platformDispatcher.clearLocalesTestValue);
    addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
    await tester.pumpWidget(const YouyingApp());
    await tester.pumpAndSettle();
    expect(find.text('Home'), findsWidgets);
    expect(find.text('Rankings'), findsOneWidget);
    expect(find.text('No sources enabled'), findsWidgets);
    final context = tester.element(find.text('No sources enabled').first);
    expect(MediaQuery.textScalerOf(context).scale(10), closeTo(18, .01));
    expect(Localizations.localeOf(context).languageCode, 'en');
    tester.platformDispatcher.localesTestValue = const [Locale('zh', 'CN')];
    await tester.pumpAndSettle();
    expect(find.text('首页'), findsWidgets);
    expect(find.text('没有启用的内容源'), findsWidgets);
    expect(find.text('Home'), findsNothing);
    expect(tester.takeException(), isNull);
  });

  for (final locale in ['zh', 'en']) {
    for (final width in [320.0, 390.0, 1280.0]) {
      for (final scale in [1.0, 1.4, 2.0]) {
        testWidgets('five columns at $width / $scale / $locale',
            (tester) async {
          tester.view.physicalSize = Size(width, 844);
          tester.view.devicePixelRatio = 1;
          addTearDown(tester.view.resetPhysicalSize);
          addTearDown(tester.view.resetDevicePixelRatio);
          final client = PreviewCatalog();
          addTearDown(client.dispose);
          final library = previewLibrary()..history.clear();
          addTearDown(library.dispose);
          await tester.pumpWidget(MaterialApp(
            locale: Locale(locale),
            supportedLocales: appLocales,
            localizationsDelegates: appLocalizationsDelegates,
            theme: youyingTheme(),
            builder: (context, child) => PhoneViewport(
                child: MediaQuery(
              data: MediaQuery.of(context)
                  .copyWith(textScaler: TextScaler.linear(scale)),
              child: child!,
            )),
            home: HomePage(library: library, browseClient: client),
          ));
          await tester.pumpAndSettle();
          await tester
              .ensureVisible(find.text(locale == 'en' ? 'Movies' : '电影'));
          await tester.pumpAndSettle();
          await tester.tap(find.text(locale == 'en' ? 'Movies' : '电影'));
          await tester.pumpAndSettle();
          final positions = [
            for (var i = 1; i <= 10; i++)
              tester.getTopLeft(find.text('影片示例 $i').first)
          ];
          expect(positions.take(5).map((p) => p.dy).toSet(), hasLength(1));
          expect(positions[5].dy, greaterThan(positions.first.dy));
          expect(positions.skip(5).map((p) => p.dy).toSet(), hasLength(1));
          for (var i = 1; i < 5; i++) {
            expect(positions[i].dx, greaterThan(positions[i - 1].dx));
          }
          expect(find.text('影片示例 1'), findsOneWidget);
          expect(tester.takeException(), isNull);
          await tester.tap(find.text(locale == 'en' ? 'Rankings' : '排行榜'));
          await tester.pumpAndSettle();
          expect(tester.takeException(), isNull);
          await tester.tap(find.text(locale == 'en' ? 'Me' : '我的'));
          await tester.pumpAndSettle();
          expect(tester.takeException(), isNull);
        });
      }
    }
  }
}
