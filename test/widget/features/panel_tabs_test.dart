import 'dart:async';

import 'package:apexo/app/panels/panels_manager.dart';
import 'package:apexo/features/appointments/open_appointment_panel.dart';
import 'package:apexo/features/expenses/open_expense_panel.dart';
import 'package:apexo/features/patients/open_patient_panel.dart';
import 'package:apexo/features/patients/patient_model.dart';
import 'package:apexo/services/login.dart';
import 'package:apexo/services/localization/locale.dart';
import 'package:apexo/services/perm.dart';
import 'package:fluent_ui/fluent_ui.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../helpers/model_factory.dart';
import '../../helpers/pump_app.dart';

/// A row's context menu offers one item per tab of the panel it opens, and both
/// the menu and the panel read the same list (`patientTabs`, `appointmentTabs`,
/// `expenseTabs`). These tests open the real panels and compare the tab strip
/// they build with that list, so a tab cannot be added to one side and silently
/// missing from the other.
void main() {
  late List<int> originalPerms;

  setUp(() {
    originalPerms = login.savedPermissions;
    // Full permissions so the conditional tabs (appointments, post-op) exist
    // and are covered by the comparison.
    login.savedPermissions = Perm.full;
    PanelsManager.closeAll();
  });

  tearDown(() {
    PanelsManager.closeAll();
    login.savedPermissions = originalPerms;
  });

  /// The titles the open panel put in its strip, in order.
  List<String> stripOf(String itemId) {
    final panel = PanelsManager.active().firstWhere(
      (panel) => panel.itemId == itemId || panel.identifier == itemId,
      orElse: () => fail('no open panel for $itemId'),
    );
    return panel.tabs.map((tab) => tab.title).toList();
  }

  testWidgets('the patient panel builds the tabs its context menu offers',
      (tester) async {
    final patient = Patient.fromJson({
      'id': 'tabs-patient',
      'title': 'Tabs Patient',
    });

    await pumpApexoApp(tester, const SizedBox.shrink());
    unawaited(openPatient(patient));
    await tester.pumpAndSettle();

    expect(
      stripOf('tabs-patient'),
      patientTabs().map((tab) => tab.titleKey).toList(),
    );
  });

  testWidgets('the appointment panel builds the tabs its context menu offers',
      (tester) async {
    final appointment = testAppointment(id: 'tabs-appointment');

    await pumpApexoApp(tester, const SizedBox.shrink());
    openAppointment(appointment);
    await tester.pumpAndSettle();

    expect(
      stripOf('tabs-appointment'),
      appointmentTabs(appointment).map((tab) => tab.titleKey).toList(),
    );
  });

  testWidgets('the orders panel builds the tabs its context menu offers',
      (tester) async {
    final order = testExpense(id: 'tabs-order');

    await pumpApexoApp(tester, const SizedBox.shrink());
    unawaited(openExpenses([order], 'Tabs Supplier', 'tabs-supplier'));
    await tester.pumpAndSettle();

    expect(
      stripOf('Tabs Supplier'),
      expenseTabs().map((tab) => tab.titleKey).toList(),
    );
  });

  testWidgets('an archived order panel shows only its own tab', (tester) async {
    final order = testExpense(id: 'tabs-archived-order');

    await pumpApexoApp(tester, const SizedBox.shrink());
    unawaited(openExpenses([order], 'Tabs Archived', 'tabs-supplier', true));
    await tester.pumpAndSettle();

    expect(
      stripOf('Tabs Archived'),
      expenseTabs(singleArchived: true).map((tab) => tab.titleKey).toList(),
    );
  });

  // The menus label their items with `txt(tab.titleKey)`, which the audit tool
  // cannot check statically — so check it here.
  test('every tab title key exists in the dictionary', () {
    final keys = [
      ...PatientTab.values.map((tab) => tab.titleKey),
      ...AppointmentTab.values.map((tab) => tab.titleKey),
      ...ExpenseTab.values.map((tab) => tab.titleKey),
    ];
    for (final key in keys) {
      expect(locale.s.dictionary.containsKey(key), isTrue, reason: key);
    }
  });
}
