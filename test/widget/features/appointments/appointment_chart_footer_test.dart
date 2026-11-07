@Tags(['serial'])
library;

import 'package:apexo/common_widgets/audio_recorder.dart';
import 'package:apexo/common_widgets/dental_chart_voice_action.dart';
import 'package:apexo/features/appointments/appointment_chart_footer.dart';
import 'package:apexo/features/appointments/appointment_model.dart';
import 'package:apexo/features/appointments/appointment_session.dart';
import 'package:apexo/features/appointments/appointment_sessions.dart';
import 'package:apexo/features/appointments/open_appointment.dart';
import 'package:apexo/features/patients/patients_store.dart';
import 'package:apexo/features/appointments/appointment_windows.dart';
import 'package:apexo/features/appointments/appointments_store.dart';
import 'package:apexo/features/settings/settings_model.dart';
import 'package:apexo/features/settings/settings_stores.dart';
import 'package:apexo/services/ai_services/dental_history.dart';
import 'package:apexo/services/login.dart';
import 'package:apexo/services/network.dart';
import 'package:apexo/services/perm.dart';
import 'package:apexo/ui/workspace/panels_manager.dart';
import 'package:apexo/shared/dental_chart/dental_chart_window_spec.dart';
import 'package:apexo/ui/workspace/standalone_window_card.dart';
import 'package:apexo/widget_keys.dart';
import 'package:apexo/ui/workspace/windows_manager.dart';
import 'package:fluent_ui/fluent_ui.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../../helpers/model_factory.dart';
import '../../../helpers/pump_app.dart';

void main() {
  late bool online;
  late List<int> permissions;
  late List<Setting> settings;
  late List<Appointment> visits;

  setUp(() {
    online = network.isOnline();
    permissions = List.of(login.savedPermissions);
    settings = globalSettings.docs.values.toList();
    visits = appointments.docs.values.toList();
    login.savedPermissions = Perm.full;
    network.isOnline(false);
    PanelsManager.closeAll();
    WindowsManager.closeAll();
  });

  tearDown(() {
    PanelsManager.closeAll();
    WindowsManager.closeAll();
    globalSettings.observableMap.clear();
    globalSettings.setAll(settings);
    appointments.observableMap.clear();
    appointments.setAll(visits);
    login.savedPermissions = permissions;
    network.isOnline(online);
  });

  for (final enabled in [false, true]) {
    for (final connected in [false, true]) {
      testWidgets('visit voice requires AI $enabled and network $connected',
          (tester) async {
        globalSettings.set(Setting.fromJson(
            {'id': 'ai_services_ena', 'value': enabled ? '1' : '0'}));
        network.isOnline(connected);
        final visit = testAppointment(id: 'voice-visit');
        appointments.set(visit);
        // Dictation lives in the post-op record at the foot of the chart.
        await pumpApexoApp(
            tester,
            Align(
                alignment: Alignment.topCenter,
                child: SizedBox(
                    width: 900, child: AppointmentOperativeForm(visit))));
        expect(find.byType(AudioRecorderButton),
            enabled && connected ? findsOneWidget : findsNothing);
        network.isOnline(false);
        await tester.pumpAndSettle();
        expect(find.byType(AudioRecorderButton), findsNothing);
        // Standalone, the footer is the way to the visit's other windows, as
        // attachments.
        final session = appointmentDentalChart(visit);
        expect(session.footer, isNotNull);
        await pumpApexoApp(
            tester,
            Align(
                alignment: Alignment.topCenter,
                child: SizedBox(width: 600, child: session.footer!(session))));
        for (final id in ['operative', 'labwork', 'gallery']) {
          expect(find.byKey(ValueKey('chart-tool-appointment:${visit.id}-$id')),
              findsOneWidget);
        }
        expect(find.byType(AppointmentChartFooter), findsOneWidget);
        expect(tester.takeException(), isNull);
      });
    }
  }

  testWidgets('the chart dock keeps the existing operative permission gate',
      (tester) async {
    login.savedPermissions = List.of(Perm.full)..[Perm.postOp] = 0;
    final visit = testAppointment(id: 'restricted-tools');
    appointments.set(visit);
    final session = appointmentDentalChart(visit);
    await pumpApexoApp(tester, session.footer!(session));
    expect(find.byKey(ValueKey('chart-tool-appointment:${visit.id}-operative')),
        findsNothing);
    expect(find.byKey(ValueKey('chart-tool-appointment:${visit.id}-labwork')),
        findsOneWidget);
    expect(find.byKey(ValueKey('chart-tool-appointment:${visit.id}-gallery')),
        findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  for (final field in [
    WK.fieldAppointmentPostOpNotes,
    WK.fieldAppointmentPrice,
    WK.fieldAppointmentPayment,
  ]) {
    testWidgets('the first edit of $field publishes the updated draft',
        (tester) async {
      final visit = testAppointment(id: 'first-edit-$field');
      appointments.set(visit);
      final session = AppointmentSession(visit);
      addTearDown(session.dispose);
      await pumpApexoApp(
        tester,
        Align(
          alignment: Alignment.topCenter,
          child: SizedBox(
            width: 600,
            child: AppointmentOperativeForm(
              session.item,
              onEdited: session.refreshDirty,
            ),
          ),
        ),
      );

      await tester.enterText(find.descendant(
        of: find.byKey(field),
        matching: find.byType(EditableText),
      ), '10');

      expect(session.hasUnsavedChanges(), isTrue);
      expect(session.item.isDone, isTrue);
      expect(tester.takeException(), isNull);
    });
  }

  for (final band in [false, true]) {
    testWidgets('the first pre-op edit publishes the draft (band: $band)',
        (tester) async {
      final visit = testAppointment(id: 'first-preop-$band');
      appointments.set(visit);
      final session = AppointmentSession(visit);
      addTearDown(session.dispose);
      await pumpApexoApp(
        tester,
        Align(
          alignment: Alignment.topCenter,
          child: SizedBox(
            width: 560,
            child: band
                ? AppointmentBandDetails(session.item,
                    onEdited: session.refreshDirty)
                : AppointmentDetailsForm(session.item,
                    onEdited: session.refreshDirty),
          ),
        ),
      );
      expect(tester.takeException(), isNull);

      await tester.enterText(find.descendant(
        of: find.byKey(WK.fieldAppointmentPreOpNotes),
        matching: find.byType(EditableText),
      ), 'First note');

      expect(session.hasUnsavedChanges(), isTrue);
      expect(session.item.preOpNotes, 'First note');
      expect(tester.takeException(), isNull);
    });
  }

  testWidgets('editing an existing lab order publishes the updated draft',
      (tester) async {
    final visit = testAppointment(id: 'edited-lab-order', hasLabwork: true);
    appointments.set(visit);
    final session = AppointmentSession(visit);
    addTearDown(session.dispose);
    await pumpApexoApp(
      tester,
      Align(
        alignment: Alignment.topCenter,
        child: SizedBox(
          width: 560,
          child: AppointmentLabworkSection(
            appointment: session.item,
            onEdited: session.refreshDirty,
          ),
        ),
      ),
    );

    await tester.enterText(find.descendant(
      of: find.byKey(WK.fieldLabworkOrderNotes),
      matching: find.byType(EditableText),
    ), 'Review margins');

    expect(session.hasUnsavedChanges(), isTrue);
    expect(session.item.labworkNotes, 'Review margins');
    expect(tester.takeException(), isNull);
  });

  testWidgets('an attached chart keeps post-op fields behind their permission',
      (tester) async {
    login.savedPermissions = List.of(Perm.full)..[Perm.postOp] = 0;
    final patient = testPatient(id: 'restricted-footer-patient');
    patients.set(patient);
    addTearDown(() => patients.observableMap.remove(patient.id));
    final visit = testAppointment(
      id: 'restricted-footer-visit',
      patientID: patient.id,
      postOpNotes: 'Restricted clinical note',
    );
    appointments.set(visit);
    await openAppointment(visit);
    final session = appointmentSessions.get(visit.id)!;
    addTearDown(() => appointmentSessions.dispose(visit.id));
    await pumpApexoApp(
      tester,
      Align(
        alignment: Alignment.topCenter,
        child: SizedBox(
          width: 600,
          child: AppointmentChartFooter(
            appointment: session.item,
            session: session.chart,
            attached: true,
          ),
        ),
      ),
    );

    expect(find.byType(AppointmentOperativeForm), findsNothing);
    expect(find.byKey(WK.visitChartAttachments), findsOneWidget);
    expect(find.text('Restricted clinical note'), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('post-op notes and prescriptions share a row, then stack narrow',
      (tester) async {
    tester.view.physicalSize = const Size(1200, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final visit = testAppointment(
      id: 'responsive-operative',
      postOpNotes: 'Filling placed.',
      prescriptions: ['Amoxicillin'],
    );
    appointments.set(visit);

    Future<void> pumpAt(double width) => pumpApexoApp(
          tester,
          Align(
            alignment: Alignment.topCenter,
            child: SizedBox(
              width: width,
              child: AppointmentOperativeForm(visit),
            ),
          ),
        );

    await pumpAt(900);
    var notes = tester.getRect(find.byKey(WK.fieldAppointmentPostOpNotes));
    var prescriptions =
        tester.getRect(find.byKey(WK.fieldAppointmentPrescriptions));
    expect(notes.top, closeTo(prescriptions.top, 1),
        reason: 'a wide chart puts the two free-text fields on one row');
    expect(tester.takeException(), isNull);

    await pumpAt(380);
    notes = tester.getRect(find.byKey(WK.fieldAppointmentPostOpNotes));
    prescriptions =
        tester.getRect(find.byKey(WK.fieldAppointmentPrescriptions));
    expect(prescriptions.top, greaterThan(notes.bottom - 1),
        reason: 'a phone-width chart gives each field its own line');
    expect(tester.takeException(), isNull);
  });

  for (final height in [96.0, 181.0]) {
    testWidgets('visit tools fit a window dragged down to $height pixels',
        (tester) async {
      tester.view.physicalSize = const Size(1200, 800);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      globalSettings
          .set(Setting.fromJson({'id': 'ai_services_ena', 'value': '1'}));
      network.isOnline(true);
      final visit = testAppointment(id: 'short-tools-visit');
      appointments.set(visit);
      final session = appointmentDentalChart(visit, onSave: () async {});
      final floating = WindowsManager.showStandalone(dentalChartWindow(session),
          scope: session.id,
          onSave: session.save,
          hasChanges: () => session.hasChanges);
      await pumpApexoApp(
          tester,
          Align(
              alignment: Alignment.topCenter,
              child: SizedBox(
                  width: 960,
                  height: height,
                  child: StandaloneWindowCard(
                      floating: floating, compact: false))));
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      await tester.ensureVisible(find.byKey(WK.windowSave));
      await tester.pumpAndSettle();
      expect(find.byKey(WK.windowSave).hitTestable(), findsOneWidget);
      expect(tester.takeException(), isNull);
    });
  }

  test('chart dictation edits only its visit draft until that chart is saved',
      () async {
    globalSettings
        .set(Setting.fromJson({'id': 'ai_services_ena', 'value': '1'}));
    network.isOnline(true);
    final stored =
        testAppointment(id: 'dictated-visit', teeth: {'11': 'filling'});
    appointments.set(stored);
    final draft = Appointment.fromJson(stored.toJson());
    final session = appointmentDentalChart(draft, onSave: () async {
      appointments.set(Appointment.fromJson(draft.toJson()));
    });
    final action =
        dentalHistoryVoiceAction(transcribe: (bytes, filename) async {
      expect(bytes, [1, 2, 3]);
      expect(filename, 'audio/m4a');
      return DentalHistoryData(
          teeth: {'26': 'crown'}, teethExtraNotes: {'26': 'Review crown'});
    });
    final button = action!(session) as AudioRecorderButton;
    await button.onRecordingComplete([1, 2, 3], 'audio/m4a');
    expect(session.teeth, {'11': 'filling', '26': 'crown'});
    expect(session.extraNotes['26'], 'Review crown');
    expect(session.hasChanges, isTrue);
    expect(appointments.get(stored.id)!.teeth, {'11': 'filling'});
    await session.save();
    expect(appointments.get(stored.id)!.teeth['26'], 'crown');
    expect(session.hasChanges, isFalse);
  });
}
