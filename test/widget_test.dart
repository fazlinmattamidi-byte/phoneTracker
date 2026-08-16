import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:plateq_mobile/src/mobile_app.dart';

void main() {
  const authChannel = MethodChannel('plateq.auth/session');
  const storageChannel = MethodChannel('plateq.app/storage');

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
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(storageChannel, (MethodCall call) async {
      return switch (call.method) {
        'readJson' => null,
        'writeJson' => true,
        'clearJson' => true,
        _ => null,
      };
    });
  });

  tearDown(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(authChannel, null);
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(storageChannel, null);
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

    expect(find.text('TOTAL VEHICLES'), findsOneWidget);
    expect(find.text('Home'), findsOneWidget);
    expect(find.byType(NavigationBar), findsNothing);
  });

  testWidgets('PlateQ mobile app uses web sidebar on wide layouts',
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

    expect(find.text('MENU'), findsOneWidget);
    expect(find.text('Dashboard'), findsOneWidget);
    expect(find.byType(NavigationRail), findsNothing);
    expect(find.byType(NavigationBar), findsNothing);
  });
}
