import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:youying/main.dart';

void main() {
  for (final width in [320.0, 390.0, 1280.0]) {
    testWidgets('phone viewport respects $width logical pixel window',
        (tester) async {
      tester.view.physicalSize = Size(width, 900);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      late Size logicalSize;
      await tester.pumpWidget(MaterialApp(
        builder: (_, child) => PhoneViewport(child: child!),
        home: Builder(builder: (context) {
          logicalSize = MediaQuery.sizeOf(context);
          return const Scaffold(body: SizedBox.expand(key: Key('content')));
        }),
      ));
      expect(tester.getSize(find.byKey(const Key('content'))).width,
          width > 480 ? 480 : width);
      expect(logicalSize.width, width > 480 ? 480 : width);
      expect(tester.takeException(), isNull);
    });
  }
}
