import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gamepad/net.dart';
import 'package:gamepad/pages/pad_page.dart';
import 'package:gamepad/pages/pair_page.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  Future<void> setLandscape(WidgetTester tester, Size logical) async {
    tester.view.devicePixelRatio = 2.75;
    tester.view.physicalSize = logical * 2.75;
    addTearDown(() {
      tester.view.resetPhysicalSize();
      tester.view.resetDevicePixelRatio();
    });
  }

  testWidgets('pair page fits 873x393', (tester) async {
    await setLandscape(tester, const Size(873, 393));
    await tester.pumpWidget(
      MaterialApp(
        theme: ThemeData.dark(),
        home: PairPage(onPaired: (_) {}),
      ),
    );
    await tester.pump();
    expect(find.text('PhonePad'), findsOneWidget);
    expect(find.text('Pair'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('pair page fits 640x360', (tester) async {
    await setLandscape(tester, const Size(640, 360));
    await tester.pumpWidget(
      MaterialApp(
        theme: ThemeData.dark(),
        home: PairPage(onPaired: (_) {}),
      ),
    );
    await tester.pump();
    expect(tester.takeException(), isNull);
  });

  testWidgets('pad page fits 873x393', (tester) async {
    SharedPreferences.setMockInitialValues(<String, Object>{});
    await setLandscape(tester, const Size(873, 393));
    await tester.pumpWidget(
      MaterialApp(
        theme: ThemeData.dark(),
        home: PadPage(
          session: const PairSession(
            ip: '192.0.2.1',
            token: '0123456789abcdef',
          ),
          onUnpair: () {},
        ),
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 150));
    expect(find.text('GAMEPAD'), findsOneWidget);
    expect(find.text('TURBO'), findsOneWidget);
    expect(find.text('LAYOUT'), findsOneWidget);
    expect(find.text('PS'), findsOneWidget);
    expect(tester.takeException(), isNull);

    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump();
  });

  testWidgets('pad page fits 640x360', (tester) async {
    SharedPreferences.setMockInitialValues(<String, Object>{});
    await setLandscape(tester, const Size(640, 360));
    await tester.pumpWidget(
      MaterialApp(
        theme: ThemeData.dark(),
        home: PadPage(
          session: const PairSession(
            ip: '192.0.2.1',
            token: '0123456789abcdef',
          ),
          onUnpair: () {},
        ),
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 150));
    expect(tester.takeException(), isNull);

    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump();
  });
}
