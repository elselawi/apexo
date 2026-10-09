import 'package:apexo/app/panels/panel_screen.dart' show PanelScreen;
import 'package:apexo/app/panels/panels_manager.dart';
import 'package:apexo/common_widgets/appointment_card.dart' show PaymentPill;
import 'package:apexo/common_widgets/audio_recorder.dart'
    show AudioRecorderButton;
import 'package:apexo/services/localization/locale.dart' show txt;
import 'package:apexo/widget_keys.dart';
import 'package:flutter/widgets.dart' show Column, Key;
import 'package:apexo/features/patients/patients_store.dart';
import 'package:apexo/features/appointments/appointments_store.dart';
import 'package:apexo/services/login.dart';
import 'package:apexo/utils/constants.dart' show publicCollectionName;
import 'package:pocketbase/pocketbase.dart';
import 'package:flutter_test/flutter_test.dart';
import '../support/e2e.dart';
import '../support/fixtures.dart';

/// The patient panel: its four tabs, the teeth chart, and the totals the
/// appointments on the other tabs feed.
void registerPatientPanelTests() {
  group('patient_panel', () {
    testWidgets('01: every tab renders', (tester) async {
      await E2E.signIn(tester);
      final patient = await Fixtures.createPatient(tester);
      await Fixtures.openPatient(tester, patient);

      // patientDetails is the tab the panel opens on.
      expect(find.byKey(WK.fieldPatientName), findsOneWidget);

      await Fixtures.openPanelTab(tester, 'dentalNotes');
      expect(find.byKey(WK.tooth('11', selected: false)), findsOneWidget,
          reason: 'the dental-notes tab has no teeth chart');

      await Fixtures.openPanelTab(tester, 'appointments');
      expect(find.text(txt('noAppointmentsFound')), findsWidgets,
          reason: 'a patient who was just created already has a history');

      await Fixtures.openPanelTab(tester, 'patientPage');
      expect(find.text(txt('generateQRLink')), findsWidgets,
          reason: 'the patient-page tab has no way to make a link');

      await Fixtures.closePanel(tester);
    });

    testWidgets("02: the appointments tab lists this patient's visits only",
        (tester) async {
      await E2E.signIn(tester);
      final mine = await Fixtures.createPatient(tester);
      final other = await Fixtures.createPatient(tester);
      await Fixtures.createAppointment(tester, patientName: mine);
      await Fixtures.createAppointment(tester, patientName: mine);
      await Fixtures.createAppointment(tester, patientName: other);

      await Fixtures.openPatients(tester);
      await Fixtures.openPatient(tester, mine);
      await Fixtures.openPanelTab(tester, 'appointments');

      // One card per visit, and only this patient's.
      expect(find.byKey(WK.acSideIcons), findsNWidgets(2),
          reason: "the history is not exactly this patient's two visits");
      expect(
        find.descendant(
          of: find.byType(PanelScreen),
          matching: find.text(other),
        ),
        findsNothing,
        reason: "another patient's visit is listed in this panel",
      );

      await Fixtures.closePanel(tester);
    });

    testWidgets('03: the summary bills the visits that are completed',
        (tester) async {
      await E2E.signIn(tester);
      final patient = await Fixtures.createPatient(tester);
      // Today is drawn at 00:00, so a visit booked for today has already
      // happened — and giving it a price marks it done, which is what the
      // patient's totals count (`PatientAppointmentBundle.done`).
      await Fixtures.createAppointment(tester,
          patientName: patient, day: DateTime.now(), price: '50');
      // A visit still to come, also priced: not billed yet.
      await Fixtures.createAppointment(tester,
          patientName: patient, price: '30');

      await Fixtures.openPatients(tester);
      await Fixtures.openPatient(tester, patient);
      await Fixtures.openPanelTab(tester, 'appointments');

      // The summary's own pills, not every amount on screen: each visit's card
      // shows its own figures, and only the summary carries `cost`.
      final summaryTitle = find.textContaining(txt('paymentSummary'));
      await E2E.waitFor(tester, summaryTitle,
          description: 'the payment summary');
      final pills = tester
          .widgetList<PaymentPill>(find.descendant(
            of: find
                .ancestor(of: summaryTitle, matching: find.byType(Column))
                .first,
            matching: find.byType(PaymentPill),
          ))
          .toList();
      expect(pills.length, 3, reason: 'the history has no payment summary');
      expect(pills[0].title, txt('cost'));
      expect(pills[0].amount, '50.00',
          reason: 'the cost counts a visit that has not happened yet');
      expect(pills[1].title, txt('paid'));
      expect(pills[1].amount, '50.00',
          reason: 'the paid total does not follow the completed visit');
      expect(pills[2].title, txt('fullyPaid'),
          reason: 'a visit that was paid in full is not reported as such');

      await Fixtures.closePanel(tester);
    });

    testWidgets("04: the patient's notes save and reload", (tester) async {
      await E2E.signIn(tester);
      final patient = await Fixtures.createPatient(tester);
      await Fixtures.openPatient(tester, patient);

      await Fixtures.enterField(tester, WK.fieldPatientNotes, 'e2e note');
      await Fixtures.save(tester);
      await Fixtures.closePanel(tester);

      await Fixtures.openPatient(tester, patient);
      expect(Fixtures.fieldText(tester, WK.fieldPatientNotes), 'e2e note');
      await Fixtures.closePanel(tester);
    });

    testWidgets('05: a tooth condition is stored and comes back',
        (tester) async {
      await E2E.signIn(tester);
      final patient = await Fixtures.createPatient(tester);
      await Fixtures.openPatient(tester, patient);
      await Fixtures.openPanelTab(tester, 'dentalNotes');

      await Fixtures.setToothCondition(tester, '11', 'filling');
      expect(find.byKey(WK.tooth('11', selected: true)), findsOneWidget,
          reason: 'the tooth does not show the condition that was just set');

      await Fixtures.save(tester);
      await Fixtures.closePanel(tester);

      await Fixtures.openPatient(tester, patient);
      await Fixtures.openPanelTab(tester, 'dentalNotes');
      expect(find.byKey(WK.tooth('11', selected: true)), findsOneWidget,
          reason: 'the tooth came back without its condition');
      await Fixtures.closePanel(tester);
    });

    testWidgets('06: work done on an appointment shows in the chart as history',
        (tester) async {
      await E2E.signIn(tester);
      final patient = await Fixtures.createPatient(tester);
      await Fixtures.createAppointment(tester, patientName: patient);

      // Record a treatment on the appointment's own chart.
      await Fixtures.openCalendar(tester);
      await Fixtures.selectDay(tester, Fixtures.tomorrow());
      await Fixtures.openAppointmentTile(tester, patient: patient);
      await Fixtures.openPanelTab(tester, 'operativeDetails');
      await Fixtures.setToothCondition(tester, '36', 'filling');
      await Fixtures.save(tester);
      await Fixtures.closePanel(tester);

      // The patient's chart carries it as history: the tooth is marked from
      // another record, which is what the chart draws as an "old" note.
      await Fixtures.openPatients(tester);
      await Fixtures.openPatient(tester, patient);
      await Fixtures.openPanelTab(tester, 'dentalNotes');

      expect(find.text(txt('extraNotesFromAppointments')), findsWidgets,
          reason: 'the chart does not show what the appointment recorded');
      expect(find.byKey(WK.tooth('36', selected: false)), findsOneWidget,
          reason: 'the tooth is drawn as the patient\'s own condition instead '
              'of as history');

      await Fixtures.closePanel(tester);
    });

    testWidgets('07: the patient page link is generated', (tester) async {
      await E2E.signIn(tester);
      final patient = await Fixtures.createPatient(tester);
      await Fixtures.openPatient(tester, patient);
      await Fixtures.openPanelTab(tester, 'patientPage');

      // `txt()` is rendered by `Txt`, which is a `Text` that builds another
      // `Text` — so a label finder matches twice and the tap has to take one.
      await E2E.tapFirst(tester, find.text(txt('generateQRLink')),
          description: 'the generate-link button');
      await E2E.waitFor(tester, find.text(txt('patientCanUseTheFollowing')),
          description: 'the generated link',
          timeout: const Duration(seconds: 30));
      // Printing and the QR block only appear once the patient has a link.
      expect(find.text(txt('printQR')), findsWidgets,
          reason: 'the link was generated but cannot be used');

      // Generating the link changed the record; the panel is left dirty on
      // purpose here (the test is about the button, not about saving).
      await Fixtures.closePanel(tester);
    });

    testWidgets('08: revoking patient-page access takes the link down',
        (tester) async {
      await E2E.signIn(tester);
      final name = await Fixtures.createPatient(tester);
      await Fixtures.createAppointment(tester,
          patientName: name, day: DateTime.now());
      final patient =
          patients.docs.values.singleWhere((row) => row.title == name);
      await appointments.waitUntilChangesAreProcessed();
      final anonymous = PocketBase(login.url);
      Future<int> portalCount() async =>
          (await anonymous.collection(publicCollectionName).getList(
                  query: {'pid': patient.id}, filter: 'pid="${patient.id}"'))
              .totalItems;
      expect(await portalCount(), greaterThan(0));
      await Fixtures.openPatients(tester);
      await Fixtures.openPatient(tester, name);
      await Fixtures.openPanelTab(tester, 'patientPage');
      await E2E.tap(tester, find.byKey(const Key('patientPortalAccess')),
          description: 'the patient-page access switch');
      await patients.waitUntilChangesAreProcessed();
      expect(patients.get(patient.id)!.portalAccessRevoked, isTrue);
      expect(await portalCount(), 0);
      await E2E.tap(tester, find.byKey(const Key('patientPortalAccess')),
          description: 'restore patient-page access');
      await patients.waitUntilChangesAreProcessed();
      expect(await portalCount(), greaterThan(0));
      await Fixtures.closePanel(tester);
    });

    // Voice autofill is the AI path: the microphone appears in the tab's footer
    // only while the AI services are switched on (`globalSettings
    // .aiServicesEnabled`) and there is a connection, and the harness has no
    // audio input at all. It is `ai_services` work (todo.md §3.1).
    testWidgets('09: voice autofill fills the dental notes', (tester) async {
      await E2E.signIn(tester);
      final patient = await Fixtures.createPatient(tester);
      await Fixtures.openPatient(tester, patient);
      await Fixtures.openPanelTab(tester, 'dentalNotes');

      await E2E.tap(tester, find.byType(AudioRecorderButton),
          description: 'the dictation button');
      await Fixtures.save(tester);
      await Fixtures.closePanel(tester);
    }, skip: true);

    testWidgets('10: the panel can be minimised and restored', (tester) async {
      await E2E.signIn(tester);
      addTearDown(() async {
        PanelsManager.minimize(false);
        await Fixtures.fullSize(tester);
      });
      final patient = await Fixtures.createPatient(tester);
      await Fixtures.openPatient(tester, patient);

      await Fixtures.sizeTo(tester, width: 680, height: 900);
      final panel = find.byType(PanelScreen);
      final expandedHeight = tester.getSize(panel).height;
      expect(find.byKey(WK.panelMinimize), findsOneWidget,
          reason: 'the compact panel has no minimise button');

      await E2E.tap(tester, find.byKey(WK.panelMinimize),
          description: 'the minimise button');
      await E2E.settle(tester, frames: 10);
      expect(PanelsManager.minimize(), isTrue,
          reason: 'minimising the panel did not register');
      expect(tester.getSize(panel).height, lessThan(expandedHeight / 2),
          reason: 'minimising did not collapse the panel');

      await E2E.tap(tester, find.byKey(WK.panelMinimize),
          description: 'the restore button');
      await E2E.settle(tester, frames: 10);
      expect(PanelsManager.minimize(), isFalse);
      expect(tester.getSize(panel).height, greaterThan(expandedHeight / 2),
          reason: 'restoring did not expand the panel again');
      await Fixtures.closePanel(tester);
    });
  });
}
