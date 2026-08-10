import 'package:flutter_test/flutter_test.dart';
import 'package:plateq_mobile/src/core/app_state.dart';
import 'package:plateq_mobile/src/core/domain.dart';

void main() {
  test('imports new vehicles and updates existing rows by plate', () {
    final state = AppState();
    final initialCount = state.vehicles.length;

    final summary = state.importVehiclesFromCsv('''
"plate","customer_name","customer_id","phone","brand","model","colour","year","finance_company","outstanding_amount","reference","priority","status","remark"
"ZZZ100","Nur Aina","CUST-900","+60 12-000 0000","Proton","X70","Blue","2024","Maybank","12345.50","REF-900","HIGH","FLAGGED","new imported case"
"ANN7569","Updated Ahmad","CUST-001","+60 12-345 6789","Perodua","Bezza","White","2021","CIMB Bank","15000","CIMB001","MEDIUM","ACTIVE","updated case"
"BADROW","","","","","","","","","","","","",""
''');

    expect(summary.imported, 1);
    expect(summary.updated, 1);
    expect(summary.skipped, 1);
    expect(state.vehicles.length, initialCount + 1);

    final imported =
        state.vehicles.firstWhere((item) => item.plate == 'ZZZ100');
    expect(imported.customerName, 'Nur Aina');
    expect(imported.priority, VehiclePriority.high);
    expect(imported.status, VehicleStatus.flagged);
    expect(imported.outstandingAmount, 12345.50);

    final updated =
        state.vehicles.firstWhere((item) => item.plate == 'ANN7569');
    expect(updated.customerName, 'Updated Ahmad');
    expect(updated.priority, VehiclePriority.medium);
  });
}
