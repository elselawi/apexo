@Tags(['serial'])
library;

import 'package:apexo/common_widgets/appointment_card.dart';
import 'package:apexo/common_widgets/item_title.dart';
import 'package:apexo/features/appointments/appointments_store.dart';
import 'package:apexo/features/patients/open_patient_panel.dart';
import 'package:apexo/services/login.dart';
import 'package:apexo/services/perm.dart';
import 'package:apexo/features/patients/patient_model.dart';
import 'package:apexo/features/patients/patients_screen.dart';
import 'package:apexo/features/patients/patients_store.dart';
import 'package:apexo/services/localization/locale.dart';
import 'package:apexo/widget_keys.dart';
import 'package:fluent_ui/fluent_ui.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../helpers/model_factory.dart';
import '../../helpers/pump_app.dart';

void main() {
  testWidgets('appointment saves refresh patient table and payment summary',
      (tester) async {
    final previousPatients = patients.docs.values.toList();
    final previousAppointments = appointments.docs.values.toList();
    final previousPermissions = login.savedPermissions;
    patients.observableMap.clear();
    appointments.observableMap.clear();
    login.savedPermissions = Perm.full;
    addTearDown(() {
      patients.observableMap.clear();
      patients.setAll(previousPatients);
      appointments.observableMap.clear();
      appointments.setAll(previousAppointments);
      login.savedPermissions = previousPermissions;
    });
    final patient = testPatient(id: 'payment-patient');
    patients.set(patient);
    final appointment = testAppointment(
      id: 'payment-appointment',
      patientID: patient.id,
      date: DateTime.now().subtract(const Duration(days: 1)),
      isDone: true,
      price: 123.45,
      paid: 12.34,
    );
    appointments.set(appointment);

    await tester.binding.setSurfaceSize(const Size(3200, 1080));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await pumpApexoApp(
      tester,
      Row(children: [
        const Expanded(child: PatientsScreen()),
        Expanded(
          child: SingleChildScrollView(
            child: PatientAppointments(
              patient.copy(false),
              readOnly: true,
              hide: AppointmentSections.values
                  .where((section) =>
                      section != AppointmentSections.paymentSummary)
                  .toList(),
            ),
          ),
        ),
      ]),
    );

    Finder paidPill(String amount) => find.byWidgetPredicate((widget) =>
        widget is PaymentPill &&
        widget.title == txt('paid') &&
        widget.amount == amount);
    Finder tablePaid(double amount) => find.byWidgetPredicate((widget) =>
        widget is ClickableBottomLabel &&
        widget.label.title == txt('paid') &&
        widget.label.value == amount);
    expect(paidPill('12.34'), findsOneWidget);
    expect(tablePaid(12.34), findsOneWidget);

    appointments.set(appointment.copy(false)..paid = 67.89);
    await tester.pumpAndSettle();

    expect(paidPill('67.89'), findsOneWidget);
    expect(tablePaid(67.89), findsOneWidget);
    expect(tablePaid(12.34), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('patients use detailed table rows without a view toggle',
      (tester) async {
    final previous = patients.docs.values.toList();
    patients.observableMap.clear();
    addTearDown(() {
      patients.observableMap.clear();
      patients.setAll(previous);
    });
    patients.set(Patient.fromJson({
      'id': 'patient-table-test',
      'title': 'Table Patient',
      'tags': ['Follow-up'],
    }));

    await tester.binding.setSurfaceSize(const Size(1920, 1080));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await pumpApexoApp(tester, const PatientsScreen());

    final title = find.byWidgetPredicate((widget) =>
        widget is ItemTitle && widget.item.title == 'Table Patient');
    expect(title, findsOneWidget);
    expect(find.descendant(of: title, matching: find.byType(CircleAvatar)),
        findsOneWidget);
    expect(find.text('Follow-up'), findsWidgets);
    expect(find.byKey(WK.listSearch), findsOneWidget);
    expect(find.byKey(WK.btnNewPatient), findsOneWidget);
    expect(find.byType(GridView), findsNothing);
    expect(find.byKey(const Key('dataTableListView')), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('long pressing a patient row opens its context menu',
      (tester) async {
    final previous = patients.docs.values.toList();
    patients.observableMap.clear();
    addTearDown(() {
      patients.observableMap.clear();
      patients.setAll(previous);
    });
    patients.set(Patient.fromJson({
      'id': 'patient-menu-test',
      'title': 'Menu Patient',
      'email': 'menu@patient.test',
    }));

    await tester.binding.setSurfaceSize(const Size(1920, 1080));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await pumpApexoApp(tester, const PatientsScreen());

    final title = find.byWidgetPredicate(
        (widget) => widget is ItemTitle && widget.item.title == 'Menu Patient');

    expect(find.byType(MenuFlyout), findsNothing);

    await tester.longPress(title);
    await tester.pumpAndSettle();

    Finder item(String key) => find.descendant(
          of: find.byType(MenuFlyout),
          matching: find.text(txt(key)),
        );
    // One item per patient tab, then the ways to reach the patient.
    expect(item("patientDetails"), findsWidgets);
    expect(item("dentalNotes"), findsWidgets);
    expect(item("patientPage"), findsWidgets);
    expect(item("sendEmail"), findsWidgets);
    expect(tester.takeException(), isNull);
  });
}
