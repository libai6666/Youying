import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:shared_preferences_platform_interface/shared_preferences_async_platform_interface.dart';
import 'package:youying/library.dart';
import 'package:youying/main.dart';

final class _UnusedPreferencesBackend extends SharedPreferencesAsyncPlatform {
  @override
  dynamic noSuchMethod(Invocation invocation) =>
      throw StateError('No persistence should be used by the initial-view test');
}

void main() {
  setUp(() => SharedPreferencesAsyncPlatform.instance = _UnusedPreferencesBackend());

  testWidgets('initial view discloses unknown sources and makes no automatic search', (tester) async {
    final library = Library(SharedPreferencesAsync());
    await tester.pumpWidget(MaterialApp(home: HomePage(library: library)));
    expect(find.text('恢复状态：部分'), findsOneWidget);
    expect(library.sources, isEmpty);
    expect(find.text('手动播放直链'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('source configuration dialog can be cancelled without changing state', (tester) async {
    final library = Library(SharedPreferencesAsync());
    await tester.pumpWidget(MaterialApp(home: HomePage(library: library)));
    await tester.tap(find.text('设置'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('添加源'));
    await tester.pumpAndSettle();
    expect(find.text('添加你信任的源'), findsOneWidget);
    await tester.tap(find.text('取消'));
    await tester.pumpAndSettle();
    expect(library.sources, isEmpty);
    expect(tester.takeException(), isNull);
  });
}
