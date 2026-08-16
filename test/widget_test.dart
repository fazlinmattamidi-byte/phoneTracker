import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:plateq_mobile/src/core/app_state.dart';
import 'package:plateq_mobile/src/core/domain.dart';
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

    expect(find.text('NAVIGATION MENU'), findsOneWidget);
    expect(find.text('Dashboard'), findsOneWidget);
    expect(find.byType(NavigationRail), findsNothing);
    expect(find.byType(NavigationBar), findsNothing);
  });

  testWidgets('PlateQ phone layout hides extra pills and toggles light mode',
      (WidgetTester tester) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(const PlateQMobileApp());
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.text('Sign In Now'));
    await tester.pump();
    await tester.tap(find.text('Sign In Now'));
    await tester.pumpAndSettle();

    var app = tester.widget<MaterialApp>(find.byType(MaterialApp));
    expect(app.theme?.brightness, Brightness.dark);
    await tester.tap(find.byIcon(Icons.light_mode_outlined));
    await tester.pumpAndSettle();
    app = tester.widget<MaterialApp>(find.byType(MaterialApp));
    expect(app.theme?.brightness, Brightness.light);

    final state = AppScope.of(tester.element(find.byType(PlateQShell)));
    state.go(AppSection.search);
    await tester.pumpAndSettle();
    expect(find.text(state.t('searchTitle').toUpperCase()), findsOneWidget);
    expect(find.text(state.t('customerName').toUpperCase()), findsNothing);
    expect(find.text(state.t('financeCompany').toUpperCase()), findsNothing);

    state.go(AppSection.scanner);
    await tester.pumpAndSettle();
    expect(find.textContaining('Runtime:'), findsNothing);
    expect(find.textContaining('Detector:'), findsNothing);
  });

  testWidgets('PlateQ phone filters stay paired and long pages scroll',
      (WidgetTester tester) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(const PlateQMobileApp());
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.text('Sign In Now'));
    await tester.pump();
    await tester.tap(find.text('Sign In Now'));
    await tester.pumpAndSettle();

    final state = AppScope.of(tester.element(find.byType(PlateQShell)));
    state.go(AppSection.vehicles);
    await tester.pumpAndSettle();

    final statusField = find.byWidgetPredicate(
        (widget) => widget is TrackDropdownField<VehicleStatus?>);
    final priorityField = find.byWidgetPredicate(
        (widget) => widget is TrackDropdownField<VehiclePriority?>);
    expect(statusField, findsOneWidget);
    expect(priorityField, findsOneWidget);
    final statusTop = tester.getTopLeft(statusField).dy;
    final priorityTop = tester.getTopLeft(priorityField).dy;
    expect((statusTop - priorityTop).abs(), lessThan(2));

    state.go(AppSection.settings);
    await tester.pumpAndSettle();
    expect(find.text(state.t('soundAlertSetting')), findsOneWidget);
    expect(find.text(state.t('detectionConfidenceThreshold')), findsNothing);
    expect(find.text(state.t('ocrConfidenceThreshold')), findsNothing);
    expect(find.text('Auto Refresh Rate'), findsNothing);
    expect(find.text('Consensus Votes'), findsNothing);
    expect(find.text('Max Active Tracks'), findsNothing);
    expect(find.text('Max OCR Concurrency'), findsNothing);
    expect(find.text('Runtime Special Prefixes'), findsNothing);
    expect(find.text('Developer Mode'), findsNothing);
    expect(find.text('Dataset Mode'), findsNothing);

    final admin = seedUsers.firstWhere((user) => user.role == Role.admin);
    state.loginAs(admin);
    state.go(AppSection.settings);
    await tester.pumpAndSettle();
    expect(find.text(state.t('soundAlertSetting')), findsOneWidget);
    expect(find.text(state.t('detectionConfidenceThreshold')), findsNothing);
    expect(find.text('Developer Mode'), findsNothing);
    expect(find.text('Dataset Mode'), findsNothing);

    state.go(AppSection.profile);
    await tester.pumpAndSettle();
    await tester.scrollUntilVisible(
      find.text(state.t('changePassword').toUpperCase()),
      300,
      scrollable: find.byType(Scrollable).first,
    );
    expect(find.text(state.t('changePassword').toUpperCase()), findsOneWidget);
  });
}
