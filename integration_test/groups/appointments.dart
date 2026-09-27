import 'dart:typed_data';

import 'package:apexo/features/appointments/appointments_store.dart';
import 'package:apexo/services/localization/locale.dart' show txt;
import 'package:apexo/services/login.dart' show login;
import 'package:apexo/widget_keys.dart';
import 'package:fluent_ui/fluent_ui.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart' show Mock;
import 'package:plugin_platform_interface/plugin_platform_interface.dart'
    show MockPlatformInterfaceMixin;
import 'package:printing/printing.dart'
    show LayoutCallback, OutputType, Printer;
// `PrintingPlatform` is **not** exported by `package:printing/printing.dart`:
// the platform seam only exists in its src, and it is the seam a fake print path
// needs (`Printing.layoutPdf` calls `PrintingPlatform.instance.layoutPdf`).
// ignore: implementation_imports
import 'package:printing/src/interface.dart' show PrintingPlatform;
import 'package:pdf/pdf.dart' show PdfPageFormat;
import '../support/e2e.dart';
import '../support/fixtures.dart';
import '../support/remote_rows.dart';
import '../support/store_ext.dart';
import 'package:apexo/features/appointments/appointment_model.dart';

/// Booking an appointment and what follows from it: the day it lands on, the
/// day's count, the patient's history, and taking it away again.
void registerAppointmentsTests() {
  group('appointments', () {
    testWidgets('01: the new-appointment panel opens from the calendar',
        (tester) async {
      await E2E.signIn(tester);
      await Fixtures.openCalendar(tester);
      await Fixtures.selectDay(tester, Fixtures.tomorrow());
      await Fixtures.openNewAppointmentPanel(tester);

      expect(find.byKey(WK.fieldPatient), findsOneWidget);
      expect(find.byKey(WK.fieldAppointmentDate), findsOneWidget);
      expect(find.byKey(WK.fieldAppointmentTime), findsOneWidget);
      expect(find.byKey(WK.panelSave), findsOneWidget);
      await Fixtures.closePanel(tester);
    });

    testWidgets('02: an appointment can be booked for a patient',
        (tester) async {
      await E2E.signIn(tester);
      final patient = await Fixtures.createPatient(tester);

      await Fixtures.createAppointment(tester, patientName: patient);

      // Back on the calendar, the day now carries a tile with that patient. The
      // agenda is lazy and the day is long in a full run, so the tile is opened
      // (which scrolls the list until it exists) rather than just counted.
      await Fixtures.selectDay(tester, Fixtures.tomorrow());
      await Fixtures.openAppointmentTile(tester, patient: patient);
      expect(find.byKey(WK.calendarAppointmentTile), findsWidgets,
          reason: 'the booked appointment has no tile on its day');
      expect(find.text(patient), findsWidgets,
          reason: 'the tile does not name the patient');
      await Fixtures.closePanel(tester);
    });

    testWidgets("03: the appointment shows on its day and not on another",
        (tester) async {
      await E2E.signIn(tester);
      final patient = await Fixtures.createPatient(tester);
      await Fixtures.createAppointment(tester, patientName: patient);

      await Fixtures.openCalendar(tester);
      await Fixtures.selectDay(tester, Fixtures.tomorrow());
      expect(find.text(patient), findsWidgets);

      // Two days later the patient has nothing booked.
      final other = Fixtures.tomorrow().add(const Duration(days: 1));
      await Fixtures.selectDay(tester, other);
      await E2E.settle(tester, frames: 8);
      expect(find.text(patient), findsNothing,
          reason: 'the appointment is showing on a day it was not booked for');
    });

    testWidgets("04: the day's count includes the new appointment",
        (tester) async {
      await E2E.signIn(tester);
      final patient = await Fixtures.createPatient(tester);

      await Fixtures.openCalendar(tester);
      final day = Fixtures.tomorrow();
      await Fixtures.selectDay(tester, day);
      // The tests share one database, so the day may already carry a booking
      // from an earlier test: the count has to *go up*, not start at zero.
      final before = Fixtures.dayCount(tester, day) ?? 0;

      await Fixtures.createAppointment(tester, patientName: patient);
      await Fixtures.openCalendar(tester);
      expect(Fixtures.dayCount(tester, day), before + 1,
          reason: "the day's count did not go up");
    });

    testWidgets("05: the patient's history lists the appointment",
        (tester) async {
      await E2E.signIn(tester);
      final patient = await Fixtures.createPatient(tester);
      await Fixtures.createAppointment(tester, patientName: patient);

      await Fixtures.openPatients(tester);
      await Fixtures.openPatient(tester, patient);
      await Fixtures.openPanelTab(tester, 'appointments');

      // The history renders the appointment as a card (the calendar's tile is a
      // different widget, on a different screen).
      expect(find.byKey(WK.acSideIcons), findsWidgets,
          reason: "the patient's appointments tab does not list the visit");
      expect(find.text(txt('noAppointmentsFound')), findsNothing);
      await Fixtures.closePanel(tester);
    });

    testWidgets('06: the panel shows the appointment on its tabs',
        (tester) async {
      await E2E.signIn(tester);
      final patient = await Fixtures.createPatient(tester);
      await Fixtures.createAppointment(tester,
          patientName: patient, preOpNotes: 'e2e pre-op');

      await Fixtures.openCalendar(tester);
      await Fixtures.selectDay(tester, Fixtures.tomorrow());
      await Fixtures.openAppointmentTile(tester, patient: patient);

      // The panel's three tabs, and the notes the appointment was booked with.
      for (final title in ['appointment', 'operativeDetails', 'gallery']) {
        expect(Fixtures.tabIcon(title), findsWidgets,
            reason: 'the panel has no "$title" tab');
      }
      expect(Fixtures.fieldText(tester, WK.fieldAppointmentPreOpNotes),
          'e2e pre-op');

      await Fixtures.closePanel(tester);
    });

    testWidgets('07: a price is stored with the appointment', (tester) async {
      await E2E.signIn(tester);
      final patient = await Fixtures.createPatient(tester);
      await Fixtures.createAppointment(tester,
          patientName: patient, price: '50');

      await Fixtures.openCalendar(tester);
      await Fixtures.selectDay(tester, Fixtures.tomorrow());
      await Fixtures.openAppointmentTile(tester, patient: patient);
      // The price is entered on the operative-details tab.
      await Fixtures.openPanelTab(tester, 'operativeDetails');

      final price = Fixtures.fieldText(tester, WK.fieldAppointmentPrice);
      expect(price.contains('50'), isTrue,
          reason: 'the price came back as "$price"');
      // The price is also the payment until the payment is edited by hand.
      expect(Fixtures.fieldText(tester, WK.fieldAppointmentPayment), price,
          reason: 'the paid amount does not follow the price');
      await Fixtures.closePanel(tester);
    });

    testWidgets('08: operative details save', (tester) async {
      await E2E.signIn(tester);
      final patient = await Fixtures.createPatient(tester);
      await Fixtures.createAppointment(tester, patientName: patient);

      await Fixtures.openCalendar(tester);
      await Fixtures.selectDay(tester, Fixtures.tomorrow());
      await Fixtures.openAppointmentTile(tester, patient: patient);
      await Fixtures.openPanelTab(tester, 'operativeDetails');

      await tester.enterText(
          find.byKey(WK.fieldAppointmentPostOpNotes), 'e2e post-op');
      await E2E.settle(tester);
      await Fixtures.save(tester);
      await Fixtures.closePanel(tester);

      await Fixtures.openAppointmentTile(tester, patient: patient);
      await Fixtures.openPanelTab(tester, 'operativeDetails');
      expect(Fixtures.fieldText(tester, WK.fieldAppointmentPostOpNotes),
          'e2e post-op');
      await Fixtures.closePanel(tester);
    });

    testWidgets('09: a saved panel reports nothing left to save',
        (tester) async {
      await E2E.signIn(tester);
      final patient = await Fixtures.createPatient(tester);
      await Fixtures.createAppointment(tester, patientName: patient);

      await Fixtures.openCalendar(tester);
      await Fixtures.selectDay(tester, Fixtures.tomorrow());
      await Fixtures.openAppointmentTile(tester, patient: patient);

      // Reopening a stored record must not claim unsaved work.
      await Fixtures.waitForSaveState(tester, expectChanges: false);
      await Fixtures.closePanel(tester);
    });

    testWidgets('10: archiving takes the appointment off the calendar',
        (tester) async {
      await E2E.signIn(tester);
      final patient = await Fixtures.createPatient(tester);
      await Fixtures.createAppointment(tester, patientName: patient);

      await Fixtures.openCalendar(tester);
      await Fixtures.selectDay(tester, Fixtures.tomorrow());
      await Fixtures.openAppointmentTile(tester, patient: patient);
      await E2E.tap(tester, find.byKey(WK.panelArchive),
          description: 'the archive button');
      await Fixtures.confirmFlyout(tester);
      await Fixtures.closePanel(tester);

      await Fixtures.openCalendar(tester);
      await Fixtures.selectDay(tester, Fixtures.tomorrow());
      expect(find.text(patient), findsNothing,
          reason: 'the archived appointment is still on the calendar');
    });

    testWidgets('11: deleting from the panel and closing does not warn',
        (tester) async {
      await E2E.signIn(tester);
      final patient = await Fixtures.createPatient(tester);
      await Fixtures.createAppointment(tester,
          patientName: patient, preOpNotes: 'e2e to delete');

      await Fixtures.openCalendar(tester);
      await Fixtures.selectDay(tester, Fixtures.tomorrow());
      await Fixtures.openAppointmentTile(tester, patient: patient);
      // Edit it, so there are pending edits when the archive lands.
      await tester.enterText(
          find.byKey(WK.fieldAppointmentPreOpNotes), 'e2e edited then deleted');
      await E2E.settle(tester);
      await E2E.tap(tester, find.byKey(WK.panelArchive),
          description: 'the archive button');
      await Fixtures.confirmFlyout(tester);

      // Archiving persists by itself, so closing must not ask about work that is
      // already stored (regression, 2026-09-19).
      await Fixtures.closePanel(tester, allowPrompt: false);
      expect(find.byType(FlyoutContent), findsNothing,
          reason: 'closing after a delete asked about unsaved changes');
    });
    testWidgets("12: the history flyout lists the patient's earlier visits",
        (tester) async {
      await E2E.signIn(tester);
      final patient = await Fixtures.createPatient(tester);
      // Two visits, both within the calendar's visible fortnight (a past day can
      // fall outside the two weeks it opens on) — the second is the one opened.
      await Fixtures.createAppointment(tester,
          patientName: patient, day: DateTime.now());
      await Fixtures.createAppointment(tester,
          patientName: patient, day: Fixtures.tomorrow());

      await Fixtures.openAppointmentTile(tester, patient: patient);
      await Fixtures.openAppointmentHistory(tester);

      // The flyout titles itself with the number of *other* visits.
      expect(
          find.textContaining('${txt('otherAppointments')} (1)'), findsWidgets,
          reason:
              "the history flyout does not list the patient's earlier visit");
    });

    testWidgets("13: a previous visit's notes can be copied into this one",
        (tester) async {
      // The panel *shows* the patient's earlier dental notes (an
      // `AppointmentExtraNotes` expander, read-only), but there is no action that
      // copies them into this appointment's draft — see §6.2.
      expect(true, isTrue);
    }, skip: true);

    testWidgets('14: prescriptions can be added and removed', (tester) async {
      await E2E.signIn(tester);

      // The prescriptions field offers the clinic's **existing** prescriptions as
      // suggestions, and a value that does not exist yet has nothing to click
      // (§6.2), so the clinic is given one first — on a patient of its own, so
      // the appointment under test stays the only tile for its own.
      final seededPatient = await Fixtures.createPatient(tester);
      final seededId = await Fixtures.patientIdOf(seededPatient);
      const seededRx = 'e2e ibuprofen 400';
      const seedAppointment = 'e2erxseed000001';
      appointments.setAll([
        Appointment.fromJson({
          'id': seedAppointment,
          'patientID': seededId,
          'operatorsIDs': [login.currentAccountID],
          'date': dateToWire(Fixtures.tomorrow()),
          'prescriptions': [seededRx],
          'price': 0,
        }),
      ]);
      addTearDown(() => _handBackAppointment(seedAppointment));

      final patient = await Fixtures.createPatient(tester);
      await Fixtures.createAppointment(tester, patientName: patient);
      await Fixtures.openCalendar(tester);
      await Fixtures.selectDay(tester, Fixtures.tomorrow());
      await Fixtures.openAppointmentTile(tester, patient: patient);

      // The field is on the operative-details tab, low in a long scrollable.
      await Fixtures.openPanelTab(tester, 'operativeDetails');
      await tester.ensureVisible(find.byKey(WK.fieldAppointmentPrescriptions));
      await E2E.settle(tester, frames: 5);

      final chip = find.byKey(const Key('${seededRx}_clear'));
      expect(chip, findsNothing, reason: 'the appointment already has it');

      await Fixtures.pickTag(
          tester, WK.fieldAppointmentPrescriptions, seededRx);
      expect(chip, findsOneWidget,
          reason: 'picking the prescription did not add it to the panel');
      await Fixtures.save(tester);
      await Fixtures.closePanel(tester);

      // It is in the record: reopening reads it back out of the store.
      await Fixtures.openAppointmentTile(tester, patient: patient);
      await Fixtures.openPanelTab(tester, 'operativeDetails');
      await tester.ensureVisible(find.byKey(WK.fieldAppointmentPrescriptions));
      await E2E.settle(tester, frames: 5);
      expect(chip, findsOneWidget,
          reason: 'the prescription did not survive a save');
      expect(find.text(seededRx), findsWidgets);

      // …and it can be taken off again, through the chip's own delete button.
      await E2E.tap(tester, chip,
          description: 'the prescription\'s remove button');
      await Fixtures.save(tester);
      await Fixtures.closePanel(tester);

      await Fixtures.openAppointmentTile(tester, patient: patient);
      await Fixtures.openPanelTab(tester, 'operativeDetails');
      await tester.ensureVisible(find.byKey(WK.fieldAppointmentPrescriptions));
      await E2E.settle(tester, frames: 5);
      expect(chip, findsNothing,
          reason: 'the removed prescription is still on the appointment');
      await Fixtures.closePanel(tester);
    });

    testWidgets('15: printing produces the prescription', (tester) async {
      await E2E.signIn(tester);
      final patient = await Fixtures.createPatient(tester);
      final patientId = await Fixtures.patientIdOf(patient);
      const rx = 'e2e amoxicillin 500';
      const appointmentId = 'e2eprint0000001';
      appointments.setAll([
        Appointment.fromJson({
          'id': appointmentId,
          'patientID': patientId,
          'operatorsIDs': [login.currentAccountID],
          'date': dateToWire(Fixtures.tomorrow()),
          'prescriptions': [rx],
          'price': 0,
        }),
      ]);
      addTearDown(() => _handBackAppointment(appointmentId));

      // A printer is where a widget test cannot go, so the *platform* is faked:
      // what is asserted is the document the app laid out and handed over — the
      // whole path (the clinic's footer and phone settings, the QR code, the
      // PDF, the call) really runs.
      final printer = _FakePrintingPlatform();
      final previous = PrintingPlatform.instance;
      PrintingPlatform.instance = printer;
      addTearDown(() => PrintingPlatform.instance = previous);

      await Fixtures.openCalendar(tester);
      await Fixtures.selectDay(tester, Fixtures.tomorrow());
      await Fixtures.openAppointmentTile(tester, patient: patient);
      await Fixtures.openPanelTab(tester, 'operativeDetails');
      final printButton = find.byIcon(FluentIcons.print);
      await tester.ensureVisible(printButton);
      await E2E.settle(tester, frames: 5);
      await E2E.tap(tester, printButton,
          description: 'the print prescription button');

      final deadline = DateTime.now().add(const Duration(seconds: 60));
      while (printer.calls == 0 && DateTime.now().isBefore(deadline)) {
        await E2E.settle(tester, frames: 10);
      }
      expect(printer.calls, 1,
          reason: 'the print button never reached the print path');
      expect(String.fromCharCodes(printer.pdf.take(4)), '%PDF',
          reason: 'the print path was handed something that is not a PDF');
      expect(printer.pdf.length, greaterThan(1000), reason: 'the PDF is empty');
      await Fixtures.closePanel(tester);
    });
  });
}

/// Gives one seeded appointment back — **server first**, or the next sync pulls
/// it in again (`todo.md` §6.2).
Future<void> _handBackAppointment(String id) async {
  await RemoteRows.delete(id);
  appointments.purge(id);
  await RemoteRows.delete(id);
}

/// A print platform that lays the document out and keeps it, instead of sending
/// it to a printer.
///
/// `PrintingPlatform.instance` is token-verified, and
/// `MockPlatformInterfaceMixin` is what lets a test double be installed there
/// (the same mechanism the plugin's own tests use).
class _FakePrintingPlatform extends Mock
    with MockPlatformInterfaceMixin
    implements PrintingPlatform {
  int calls = 0;
  Uint8List pdf = Uint8List(0);

  @override
  Future<bool> layoutPdf(
    Printer? printer,
    LayoutCallback onLayout,
    String name,
    PdfPageFormat format,
    bool dynamicLayout,
    bool usePrinterSettings,
    OutputType outputType,
    bool forceCustomPrintPaper,
  ) async {
    calls++;
    pdf = await onLayout(format);
    return true;
  }
}
