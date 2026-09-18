import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:adaptive_music_example/main.dart';

void main() {
  testWidgets('lab exposes playlist and DSP controls without loading audio', (
    tester,
  ) async {
    await tester.pumpWidget(const MusicLabApp(autoLoad: false));
    expect(find.text('Adaptive Music Lab'), findsOneWidget);
    expect(find.text('High-shelf'), findsOneWidget);
    expect(find.text('Smooth controls'), findsOneWidget);
    expect(find.text('Open audio'), findsOneWidget);
    await tester.ensureVisible(find.text('High-shelf'));
    await tester.tap(find.text('High-shelf'));
    await tester.pump();
    expect(find.text('Treble gain'), findsOneWidget);
    expect(find.text('-6.0 dB'), findsOneWidget);
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump();
  });
  testWidgets('lab fits a narrow phone without layout overflow', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(const MusicLabApp(autoLoad: false));
    expect(tester.takeException(), isNull);
    await tester.drag(find.byType(Scrollable).first, const Offset(0, -650));
    await tester.pump();
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump();
  });
}
