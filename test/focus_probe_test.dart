import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:shared_preferences_platform_interface/shared_preferences_async_platform_interface.dart';
import 'package:youying/catalog.dart';
import 'package:youying/library.dart';
import 'package:youying/main.dart';
import 'package:youying/player.dart';

final class _MemoryWrites extends SharedPreferencesAsyncPlatform {
  @override
  dynamic noSuchMethod(Invocation invocation) {
    if (invocation.memberName == #setString ||
        invocation.memberName == #setBool) {
      return Future<void>.value();
    }
    throw StateError('Unexpected preference access: ${invocation.memberName}');
  }
}

const _episodes = [
  Episode(name: '第1集', url: 'https://example.com/1.mp4'),
  Episode(name: '第2集', url: 'https://example.com/2.mp4'),
];
const _entry = MediaEntry(
    id: 'test:movie',
    title: '测试剧集',
    source: 'test',
    lines: {'主线路': _episodes});

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final messenger =
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
  final calls = <MethodCall>[];
  late Library library;
  var nextTextureId = 1;

  setUp(() {
    SharedPreferencesAsyncPlatform.instance = _MemoryWrites();
    library = Library(SharedPreferencesAsync());
    calls.clear();
    nextTextureId = 1;
    messenger.setMockMethodCallHandler(MediaController.methods, (call) async {
      calls.add(call);
      return null;
    });
    messenger.setMockMethodCallHandler(
        const MethodChannel('flutter_player_av/events'), (_) async => null);
    messenger.setMockMethodCallHandler(SystemChannels.platform_views,
        (call) async {
      if (call.method == 'create') return nextTextureId++;
      if (call.method == 'resize') {
        final dimensions = call.arguments as Map;
        return {'width': dimensions['width'], 'height': dimensions['height']};
      }
      return null;
    });
    messenger.setMockMethodCallHandler(
        SystemChannels.platform, (_) async => null);
  });

  tearDown(() {
    messenger.setMockMethodCallHandler(MediaController.methods, null);
    messenger.setMockMethodCallHandler(
        const MethodChannel('flutter_player_av/events'), null);
    messenger.setMockMethodCallHandler(SystemChannels.platform_views, null);
    messenger.setMockMethodCallHandler(SystemChannels.platform, null);
    playerFullscreenViewport.value = false;
  });

  bool focusedInside(bool Function(Widget) match) {
    final node = FocusManager.instance.primaryFocus;
    var found = false;
    node?.context?.visitAncestorElements((el) {
      if (match(el.widget)) found = true;
      return true;
    });
    return found;
  }

  bool onIconButton(String tooltip) =>
      focusedInside((w) => w is IconButton && w.tooltip == tooltip);

  testWidgets('fullscreen remote traversal reaches every overlay control',
      (tester) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(900, 420);
    addTearDown(tester.view.resetDevicePixelRatio);
    addTearDown(tester.view.resetPhysicalSize);
    await tester.pumpWidget(MaterialApp(
        builder: (_, child) => PhoneViewport(
            child: MediaQuery.withClampedTextScaling(
                minScaleFactor: 1, maxScaleFactor: 1, child: child!)),
        home: Scaffold(
            body: SingleChildScrollView(
                child: PlayerPage(
                    entry: _entry, library: library, embedded: true)))));
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('全屏'));
    await tester.pumpAndSettle();
    expect(FocusManager.instance.primaryFocus?.debugLabel, 'video-surface');

    // OK enters button mode on the play button.
    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    await tester.pump();
    expect(onIconButton('播放'), true);

    // → walks the bottom row: next-episode, quality menu, exit button.
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowRight);
    await tester.pump();
    expect(onIconButton('播放下一集'), true);
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowRight);
    await tester.pump();
    expect(FocusManager.instance.primaryFocus?.debugLabel,
        isNot('video-surface'));
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowRight);
    await tester.pump();
    expect(onIconButton('退出全屏'), true);

    // ↑ from the bottom-right reaches the top bar; a second ↑ exits back
    // to surface mode where arrows seek instead of traversing.
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowUp);
    await tester.pump();
    expect(focusedInside((w) => w is IconButton), true);
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowUp);
    await tester.pump();
    expect(FocusManager.instance.primaryFocus?.debugLabel, 'video-surface');
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowLeft);
    await tester.pump();
    expect(FocusManager.instance.primaryFocus?.debugLabel, 'video-surface');

    // Leave fullscreen so teardown doesn't unmount nodes with pending
    // focus requests.
    await tester.binding.handlePopRoute();
    await tester.pumpAndSettle();
    expect(FocusManager.instance.primaryFocus?.debugLabel,
        'embedded-surface');
  });
}
