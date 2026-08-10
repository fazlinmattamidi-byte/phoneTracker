import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:plateq_mobile/src/mobile_app.dart';

void main() {
  const authChannel = MethodChannel('plateq.auth/session');

  setUp(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(authChannel, (MethodCall call) async {
      return switch (call.method) {
        'getSession' => null,
        'saveSession' => null,
        'clearSession' => null,
        _ => null,
      };
    });
  });

  tearDown(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(authChannel, null);
  });

  testWidgets('PlateQ mobile app signs in to the dashboard shell',
      (WidgetTester tester) async {
    await tester.pumpWidget(const PlateQMobileApp());
    await tester.pumpAndSettle();

    expect(find.text('TRACK'), findsOneWidget);
    expect(find.text('Login to Track'), findsOneWidget);

    await tester.ensureVisible(find.text('Sign In Now'));
    await tester.pump();
    await tester.tap(find.text('Sign In Now'));
    await tester.pumpAndSettle();

    expect(find.text('Dashboard'), findsOneWidget);
    expect(find.byType(NavigationBar), findsOneWidget);
  });

  testWidgets('PlateQ mobile app uses navigation rail on wide layouts',
      (WidgetTester tester) async {
    tester.view.physicalSize = const Size(1200, 800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(const PlateQMobileApp());
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.text('Sign In Now'));
    await tester.pump();
    await tester.tap(find.text('Sign In Now'));
    await tester.pumpAndSettle();

    expect(find.byType(NavigationRail), findsOneWidget);
    expect(find.byType(NavigationBar), findsNothing);
  });
}
