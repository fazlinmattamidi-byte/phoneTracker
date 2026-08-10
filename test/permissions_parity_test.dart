import 'package:flutter_test/flutter_test.dart';
import 'package:plateq_mobile/src/core/app_state.dart';
import 'package:plateq_mobile/src/core/domain.dart';

void main() {
  test('keeps user accounts read-only for management permissions', () {
    final state = AppState()..loginAsRole(Role.user);

    expect(state.canEdit, isFalse);
    expect(state.canManageVehicles, isFalse);
    expect(state.canManageSystem, isFalse);
  });

  test('allows admin roles to manage vehicles', () {
    final admin = AppState()..loginAsRole(Role.admin);
    final superAdmin = AppState()..loginAsRole(Role.superAdmin);

    expect(admin.canManageVehicles, isTrue);
    expect(superAdmin.canManageVehicles, isTrue);
    expect(admin.canManageSystem, isFalse);
    expect(superAdmin.canManageSystem, isTrue);
  });
}
