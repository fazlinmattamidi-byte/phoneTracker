import 'dart:convert';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:plateq_mobile/src/anpr/special_series.dart' as special_series;
import 'package:plateq_mobile/src/core/app_state.dart';
import 'package:plateq_mobile/src/core/domain.dart';
import 'package:plateq_mobile/src/core/localization.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const authChannel = MethodChannel('plateq.auth/session');
  const storageChannel = MethodChannel('plateq.app/storage');

  tearDown(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(authChannel, null);
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(storageChannel, null);
    special_series.resetRuntimeSpecialSeriesPrefixes();
  });

  test('AppState restores and persists the local repository', () async {
    final writes = <Map<String, Object?>>[];
    final storedRepository = jsonEncode(<String, Object?>{
      'version': 1,
      'vehicles': <Map<String, Object?>>[
        <String, Object?>{
          'id': 'veh-local',
          'plate': 'abc 1234',
          'customerName': 'Stored Customer',
          'customerId': 'CUST-LOCAL',
          'phone': '+60 11-222 3333',
          'brand': 'Proton',
          'model': 'Saga',
          'colour': 'White',
          'year': 2024,
          'financeCompany': 'Stored Bank',
          'outstandingAmount': 12345.50,
          'reference': 'LOCAL-1',
          'priority': 'HIGH',
          'status': 'FLAGGED',
          'remark': 'Hydrated from local storage',
          'createdDate': '2026-08-01T00:00:00Z',
          'updatedDate': '2026-08-02T00:00:00Z',
        },
      ],
      'users': <Map<String, Object?>>[
        <String, Object?>{
          'id': 'usr-local',
          'name': 'Stored Admin',
          'email': 'stored@example.com',
          'phone': '+60 12-000 0000',
          'role': 'ADMIN',
          'status': 'ACTIVE',
          'avatar': 'SA',
          'lastLogin': '2026-08-03T00:00:00Z',
          'createdBy': 'test',
        },
      ],
      'history': <Map<String, Object?>>[
        <String, Object?>{
          'id': 'hist-local',
          'type': 'SYSTEM',
          'action': 'Stored Action',
          'details': 'Stored details',
          'userRole': 'ADMIN',
          'timestamp': '2026-08-04T00:00:00Z',
        },
      ],
      'settings': <String, Object?>{
        'detectionConfidence': 0.55,
        'ocrConfidence': 0.72,
        'soundAlerts': false,
        'autoRefreshRate': 45,
        'consensusVotes': 4,
        'maxTracks': 5,
        'maxOcrConcurrency': 2,
        'enableSpecialSeries': false,
        'developerMode': true,
        'datasetMode': true,
      },
      'language': 'BM',
      'themeChoice': 'LIGHT',
      'selectedCameraId': 'native-wide',
      'runtimeSpecialSeriesPrefixes': <String>['RX', 'MADANI'],
    });

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
      switch (call.method) {
        case 'readJson':
          return storedRepository;
        case 'writeJson':
          final args = Map<String, Object?>.from(call.arguments as Map);
          writes.add(args);
          return true;
        case 'clearJson':
          return true;
      }
      return null;
    });

    final state = AppState();
    await state.restoreSession();

    expect(state.vehicles, hasLength(1));
    expect(state.vehicles.single.plate, 'ABC1234');
    expect(state.vehicles.single.status, VehicleStatus.flagged);
    expect(state.users.single.email, 'stored@example.com');
    expect(state.history.single.action, 'Stored Action');
    expect(state.settings.ocrConfidence, 0.72);
    expect(state.language, AppLanguage.bm);
    expect(state.themeChoice, AppThemeChoice.light);
    expect(state.selectedCameraId, 'native-wide');
    expect(state.runtimeSpecialSeriesPrefixes, <String>['RX', 'MADANI']);
    expect(special_series.findSpecialSeriesPrefix('RX88'), 'RX');

    state.updateSettings(state.settings.copyWith(soundAlerts: true));
    await Future<void>.delayed(Duration.zero);
    await Future<void>.delayed(Duration.zero);

    expect(writes, isNotEmpty);
    final saved = jsonDecode(writes.last['json']! as String) as Map;
    expect(writes.last['key'], 'localRepositoryV1');
    expect(saved['version'], 1);
    expect(saved['language'], 'BM');
    expect(saved['selectedCameraId'], 'native-wide');
    expect(saved['runtimeSpecialSeriesPrefixes'], <String>['RX', 'MADANI']);
    expect((saved['settings'] as Map)['soundAlerts'], true);
    expect(((saved['vehicles'] as List).single as Map)['plate'], 'ABC1234');
  });
}
