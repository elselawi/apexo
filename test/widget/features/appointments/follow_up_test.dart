@Tags(['serial'])
library;

import 'package:apexo/features/appointments/appointment_model.dart';
import 'package:apexo/features/appointments/appointment_sessions.dart';
import 'package:apexo/features/appointments/appointment_session.dart';
import 'package:apexo/features/appointments/appointments_store.dart';
import 'package:apexo/features/appointments/appointment_windows.dart';
import 'package:apexo/features/appointments/calendar_widget.dart';
import 'package:apexo/features/appointments/events_agenda_widget.dart';
import 'package:apexo/features/appointments/events_timeline_widget.dart';
import 'package:apexo/features/appointments/follow_up_band.dart';
import 'package:apexo/features/appointments/follow_up_card.dart';
import 'package:apexo/features/appointments/follow_up_field.dart';
import 'package:apexo/features/appointments/follow_up_scheduling.dart';
import 'package:apexo/features/appointments/new_appointment_dialog.dart';
import 'package:apexo/common_widgets/date_time_picker.dart';
import 'package:apexo/features/patients/patient_follow_up_bar.dart';
import 'package:apexo/features/patients/patient_model.dart';
import 'package:apexo/features/patients/open_patient_panel.dart';
import 'package:apexo/features/patients/patients_store.dart';
import 'package:apexo/features/settings/settings_stores.dart'
    show DF, globalSettings;
import 'package:apexo/services/localization/locale.dart';
import 'package:apexo/services/login.dart';
import 'package:apexo/services/perm.dart';
import 'package:apexo/widget_keys.dart';
import 'package:fluent_ui/fluent_ui.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:table_calendar/table_calendar.dart';

import '../../../helpers/model_factory.dart';
import '../../../helpers/pump_app.dart';

void main() {
  late List<Appointment> originalAppointments;
  late List<Patient> originalPatients;
  late List<int> originalPerms;
  late bool originalFollowUps;

  setUp(() {
    originalAppointments = appointments.docs.values.toList();
    originalPatients = patients.docs.values.toList();
    originalPerms = login.savedPermissions;
    originalFollowUps = globalSettings.followUpsEnabled;
    login.savedPermissions = Perm.full;
    // Follow-ups are an optional feature; these tests are what it does when on.
    globalSettings.followUpsEnabled = true;
    appointmentSessions.clear();
    appointments.observableMap.clear();
    patients.observableMap.clear();
  });

  tearDown(() {
    appointmentSessions.clear();
    appointments.observableMap.clear();
    appointments.setAll(originalAppointments);
    patients.observableMap.clear();
    patients.setAll(originalPatients);
    login.savedPermissions = originalPerms;
    globalSettings.followUpsEnabled = originalFollowUps;
  });

  Future<void> pumpField(
    WidgetTester tester,
    String patientID, {
    required DateTime anchor,
  }) {
    return pumpApexoApp(
      tester,
      Center(
        child: SizedBox(
          width: 700,
          height: 200,
          child: SingleChildScrollView(
            child: FollowUpField(patientID: patientID, anchor: anchor),
          ),
        ),
      ),
    );
  }

  testWidgets('the field follows patient updates received from the store',
      (tester) async {
    patients.set(testPatient(id: 'synced-patient'));
    await pumpField(tester, 'synced-patient', anchor: DateTime(2026, 3, 10));

    patients.set(Patient.fromJson(patients.get('synced-patient')!.toJson())
      ..followUpDate = DateTime(2026, 4, 12));
    await tester.pumpAndSettle();

    final picker = tester
        .widget<DateTimePicker>(find.byKey(WK.fieldAppointmentFollowUpDate));
    expect(picker.initValue, DateTime(2026, 4, 12));
  });

  testWidgets('follow-up surfaces do not edit without scheduling permission',
      (tester) async {
    final patient = testPatient(id: 'read-only-patient');
    patients.set(patient);
    appointments.set(testAppointment(
      patientID: patient.id,
      isDone: true,
    ));
    login.savedPermissions = Perm.full..[Perm.appointments] = 0;

    await pumpField(tester, patient.id, anchor: DateTime(2026, 3, 10));
    expect(
        tester
            .widget<HoverButton>(find.byKey(WK.followUpPreset('1w')))
            .onPressed,
        isNull);

    await pumpApexoApp(
        tester,
        Center(
            child: SizedBox(
          width: 620,
          child: FollowUpSummaryCard(patientID: patient.id),
        )));
    expect(find.byKey(WK.followUpSummarySet), findsNothing);

    patients.set(Patient.fromJson(patient.toJson())
      ..followUpDate = DateTime(2026, 3, 20));
    await tester.pumpAndSettle();
    expect(find.byKey(WK.followUpRemove), findsNothing);

    await pumpApexoApp(
        tester,
        Center(
            child: SizedBox(
          width: 700,
          child: FollowUpBand(
            followUps: [
              FollowUpDue(patient: patient, date: DateTime(2026, 3, 20))
            ],
            draggable: true,
            onBook: (_, {at}) {},
          ),
        )));
    expect(find.byType(Draggable<FollowUpDue>), findsNothing);
    await tester.tap(find.byKey(WK.followUpsBandToggle));
    await tester.pumpAndSettle();
    expect(tester.widget<IconButton>(find.byKey(WK.followUpRemove)).onPressed,
        isNull);
    expect(find.byIcon(WindowsIcons.subscription_add), findsNothing);
  });

  testWidgets('the day band separates overdue follow-ups from that day',
      (tester) async {
    final today = dayOnly(DateTime.now());
    final selectedDay = today.add(const Duration(days: 3));
    final overdue = testPatient(id: 'overdue-patient', name: 'Overdue Patient');
    final due = testPatient(id: 'due-patient', name: 'Due Patient');
    patients.setAll([overdue, due]);
    setFollowUp(overdue.id, today.subtract(const Duration(days: 2)));
    setFollowUp(due.id, selectedDay);

    final followUps = followUpsOn(selectedDay);
    expect(
      followUps.map((followUp) => followUp.patient.id),
      containsAll([overdue.id, due.id]),
    );

    await pumpApexoApp(
      tester,
      Center(
        child: SizedBox(
          width: 700,
          child: FollowUpBand(followUps: followUps),
        ),
      ),
    );
    await tester.tap(find.byKey(WK.followUpsBandToggle));
    await tester.pumpAndSettle();

    final divider = find.byKey(WK.followUpsOverdueDivider);
    final dueRow = find.byKey(WK.followUpRow(due.id));
    final overdueRow = find.byKey(WK.followUpRow(overdue.id));
    expect(divider, findsOneWidget);
    expect(
      tester.getTopLeft(dueRow).dy,
      lessThan(tester.getTopLeft(divider).dy),
    );
    expect(
      tester.getTopLeft(overdueRow).dy,
      greaterThan(tester.getTopLeft(divider).dy),
    );
  });

  testWidgets('operative Save also persists its staged follow-up',
      (tester) async {
    final patient = testPatient(id: 'operative-follow-up');
    patients.set(patient);
    final visit = testAppointment(
      id: 'operative-follow-up-visit',
      patientID: patient.id,
    );
    appointments.set(visit);
    final session = AppointmentSession(visit);
    addTearDown(session.dispose);

    await pumpApexoApp(
      tester,
      Center(
        child: SizedBox(
          width: 700,
          child: AppointmentOperativeForm(
            session.item,
            followUpDraft: session.followUpDraft,
            onEdited: session.refreshDirty,
          ),
        ),
      ),
    );

    await tester.tap(find.byKey(WK.followUpPreset('1w')));
    await tester.pumpAndSettle();
    await tester.enterText(find.byKey(WK.fieldFollowUpNote), 'Crown recheck');
    await tester.pumpAndSettle();

    expect(session.hasUnsavedChanges(), isTrue);
    expect(patients.get(patient.id)!.followUpDay, isNull);
    expect(patients.get(patient.id)!.followUpNote, isEmpty);

    await session.save();
    await tester.pumpAndSettle();

    expect(
      patients.get(patient.id)!.followUpDay,
      kFollowUpPresets.first.from(dayOnly(visit.date)),
    );
    expect(patients.get(patient.id)!.followUpNote, 'Crown recheck');
    expect(session.hasUnsavedChanges(), isFalse);
    expect(find.byKey(WK.followUpSave), findsNothing);
  });

  testWidgets('a row with nothing of its own keeps the other row\'s draft',
      (tester) async {
    final patient = testPatient(id: 'two-rows');
    patients.set(patient);
    // The operative window and the chart's post-op card share one visit's draft.
    final draft = FollowUpDraft();
    Widget row() => SizedBox(
          width: 400,
          child: FollowUpField(
            patientID: patient.id,
            anchor: DateTime.now(),
            draft: draft,
          ),
        );

    await pumpApexoApp(
      tester,
      Center(child: Column(children: [row(), row()])),
    );

    await tester.tap(find.byKey(WK.followUpPreset('1w')).first);
    await tester.pumpAndSettle();
    expect(draft.isDirty, isTrue);

    // The promise changes under both rows: a sync, another window, the phone.
    setFollowUp(
      patient.id,
      dayOnly(DateTime.now()).add(const Duration(days: 30)),
    );
    await tester.pumpAndSettle();

    expect(draft.isDirty, isTrue,
        reason: 'a row that changed nothing must not take the draft back');
  });

  testWidgets('both visit rows share edits and cancel the same draft',
      (tester) async {
    final patient = testPatient(id: 'shared-follow-up');
    patients.set(patient);
    final originalDay = DateTime(2026, 1, 1);
    final chosenDay = DateTime(2026, 2, 1);
    setFollowUp(patient.id, originalDay, note: 'Original');
    final visit = testAppointment(id: 'shared-visit', patientID: patient.id);
    appointments.set(visit);
    final session = AppointmentSession(visit);
    addTearDown(session.dispose);

    Widget row() => SizedBox(
          width: 400,
          child: FollowUpField(
            patientID: patient.id,
            anchor: visit.date,
            draft: session.followUpDraft,
          ),
        );
    await pumpApexoApp(tester, Center(child: Column(children: [row(), row()])));
    tester
        .widget<DateTimePicker>(
            find.byKey(WK.fieldAppointmentFollowUpDate).first)
        .onChange(chosenDay);
    await tester.pumpAndSettle();
    expect(
      tester
          .widget<DateTimePicker>(
              find.byKey(WK.fieldAppointmentFollowUpDate).last)
          .initValue,
      chosenDay,
    );
    await tester.enterText(find.byKey(WK.fieldFollowUpNote).last, 'Review');
    await tester.pumpAndSettle();
    await session.save();
    await tester.pumpAndSettle();
    expect(patients.get(patient.id)!.followUpDay, chosenDay);
    expect(patients.get(patient.id)!.followUpNote, 'Review');
    expect(session.hasPendingEdits, isFalse);

    await tester.enterText(find.byKey(WK.fieldFollowUpNote).first, 'Cancelled');
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(WK.followUpCancel).last);
    await tester.pumpAndSettle();
    expect(session.hasPendingEdits, isFalse);
    expect(session.followUpDraft.isDirty, isFalse);
    for (final field in tester.widgetList<EditableText>(find.descendant(
      of: find.byKey(WK.fieldFollowUpNote),
      matching: find.byType(EditableText),
    ))) {
      expect(field.controller.text, 'Review');
    }
  });

  testWidgets('booking an overdue follow-up from a past day starts today',
      (tester) async {
    final today = dayOnly(DateTime.now());
    final dueDay = DateTime(today.year, today.month, today.day - 2);
    final patient = testPatient(id: 'past-calendar-follow-up');
    patients.set(patient);
    setFollowUp(patient.id, dueDay);
    DateTime? bookedAt;

    await pumpApexoApp(
      tester,
      SizedBox(
        width: 900,
        height: 650,
        child: WeekAgendaCalendar<Appointment>(
          items: const [],
          startDay: StartingDayOfWeek.monday,
          initiallySelectedDay: dueDay.millisecondsSinceEpoch,
          onAddNew: (_) {},
          onSetTime: (_) {},
          onSelect: (_, __) {},
          followUpsOnDay: followUpsOn,
          onBookFollowUp: (_, {at}) => bookedAt = at,
        ),
      ),
    );
    await tester.tap(find.byKey(WK.followUpsBandToggle));
    await tester.pumpAndSettle();
    await tester.tap(find.byIcon(WindowsIcons.subscription_add));
    expect(bookedAt, today);
    await tester.pumpAndSettle();
  });

  testWidgets('a newly opened visit row restores the shared follow-up draft',
      (tester) async {
    final patient = testPatient(id: 'reopened-follow-up');
    patients.set(patient);
    final draft = FollowUpDraft();
    final showSecond = ValueNotifier(false);
    addTearDown(showSecond.dispose);
    final anchor = DateTime(2026, 3, 10);

    Widget row() => SizedBox(
          width: 400,
          child: FollowUpField(
            patientID: patient.id,
            anchor: anchor,
            draft: draft,
          ),
        );
    await pumpApexoApp(
      tester,
      Center(
        child: ValueListenableBuilder<bool>(
          valueListenable: showSecond,
          builder: (_, visible, __) =>
              Column(children: [row(), if (visible) row()]),
        ),
      ),
    );
    await tester.tap(find.byKey(WK.followUpPreset('1w')));
    await tester.pumpAndSettle();
    await tester.enterText(find.byKey(WK.fieldFollowUpNote), 'Bring X-ray');
    await tester.pumpAndSettle();
    showSecond.value = true;
    await tester.pumpAndSettle();

    expect(find.byKey(WK.fieldFollowUpNote), findsNWidgets(2));
    for (final field in tester.widgetList<EditableText>(find.descendant(
      of: find.byKey(WK.fieldFollowUpNote),
      matching: find.byType(EditableText),
    ))) {
      expect(field.controller.text, 'Bring X-ray');
    }
    expect(
      tester
          .widget<DateTimePicker>(
              find.byKey(WK.fieldAppointmentFollowUpDate).last)
          .initValue,
      kFollowUpPresets.first.from(anchor),
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets('history books the live follow-up rather than its stale draft',
      (tester) async {
    final stalePatient = testPatient(id: 'stale-history');
    patients.set(Patient.fromJson(stalePatient.toJson()));
    appointments.set(testAppointment(patientID: stalePatient.id, isDone: true));
    await pumpApexoApp(
        tester,
        Center(
            child: SizedBox(
          width: 620,
          height: 600,
          child:
              SingleChildScrollView(child: PatientAppointments(stalePatient)),
        )));

    setFollowUp(
      stalePatient.id,
      dayOnly(DateTime.now()).add(const Duration(days: 40)),
      note: 'Crown preparation',
    );
    await tester.pumpAndSettle();
    expect(stalePatient.followUpDay, isNull);
    await tester.tap(find.byKey(WK.bookFollowUp));
    await tester.pumpAndSettle();

    final dialog =
        tester.widget<NewAppointmentDialog>(find.byType(NewAppointmentDialog));
    expect(dialog.day, dayOnly(DateTime.now()).add(const Duration(days: 40)));
    expect(dialog.patientID, stalePatient.id);
    expect(dialog.initialPreOpNotes, 'Crown preparation');
    await tester.tap(find.byIcon(WindowsIcons.cancel));
    await tester.pumpAndSettle();
  });

  testWidgets('a late promise is booked from today, not from its own day',
      (tester) async {
    final patient = testPatient(id: 'late-booking');
    patients.set(patient);
    appointments.set(testAppointment(patientID: patient.id, isDone: true));

    await pumpApexoApp(
        tester,
        Center(
            child: SizedBox(
          width: 620,
          height: 600,
          child: SingleChildScrollView(child: PatientAppointments(patient)),
        )));

    final late = dayOnly(DateTime.now()).subtract(const Duration(days: 9));
    setFollowUp(patient.id, late);
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(WK.bookFollowUp));
    await tester.pumpAndSettle();

    final dialog =
        tester.widget<NewAppointmentDialog>(find.byType(NewAppointmentDialog));
    expect(dialog.day, dayOnly(DateTime.now()),
        reason: 'a visit booked into the past keeps nothing');
    await tester.tap(find.byIcon(WindowsIcons.cancel));
    await tester.pumpAndSettle();
  });

  testWidgets('a preset stages the day, and Save writes it', (tester) async {
    patients.set(testPatient(id: 'field-patient', name: 'Field Patient'));

    await pumpField(tester, 'field-patient', anchor: DateTime(2026, 3, 10, 11));
    expect(find.byKey(WK.fieldAppointmentFollowUp), findsOneWidget);
    expect(find.byKey(WK.followUpPreset('1w')), findsOneWidget);
    expect(find.byKey(WK.followUpPreset('10d')), findsOneWidget);

    await tester.tap(find.byKey(WK.followUpPreset('1w')));
    await tester.pumpAndSettle();

    expect(patients.get('field-patient')!.followUpDay, isNull,
        reason: 'choosing a day is a draft until it is saved');
    expect(find.byKey(WK.fieldAppointmentFollowUpDate), findsOneWidget);

    await tester.tap(find.byKey(WK.followUpSave));
    await tester.pumpAndSettle();

    expect(patients.get('field-patient')!.followUpDay, DateTime(2026, 3, 17),
        reason: 'a week after the visit, stored on the patient');
    expect(find.byKey(WK.followUpSave), findsNothing,
        reason: 'a saved draft has nothing left to keep');
  });

  testWidgets('every preset explains the day it would pick', (tester) async {
    patients.set(testPatient(id: 'tooltip-patient'));

    await pumpField(tester, 'tooltip-patient',
        anchor: DateTime(2026, 3, 10, 11));

    for (final preset in kFollowUpPresets) {
      final tooltip = tester.widget<Tooltip>(
        find
            .ancestor(
              of: find.byKey(WK.followUpPreset(preset.label)),
              matching: find.byType(Tooltip),
            )
            .first,
      );
      expect(
        tooltip.message,
        DF.commonDate(preset.from(DateTime(2026, 3, 10))).replaceAll('📅 ', ''),
        reason: '${preset.label} says which day it means',
      );
    }
  });

  testWidgets('the intervals spell themselves out when the row is wide',
      (tester) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(1400, 900);
    addTearDown(tester.view.reset);
    patients.set(testPatient(id: 'width-patient'));

    Future<void> pumpAt(double width) => pumpApexoApp(
          tester,
          Center(
            child: SizedBox(
              width: width,
              height: 320,
              child: SingleChildScrollView(
                child: FollowUpField(
                  patientID: 'width-patient',
                  anchor: DateTime(2026, 3, 10),
                ),
              ),
            ),
          ),
        );

    await pumpAt(1200);
    expect(find.text('10 days'), findsOneWidget,
        reason: 'a row wide enough says what "10d" would have abbreviated');
    expect(find.text('2 weeks'), findsOneWidget);
    expect(find.text('10d'), findsNothing);

    await pumpAt(320);
    expect(find.text('10d'), findsOneWidget,
        reason: 'a row too narrow for the words keeps the abbreviations');
    expect(find.text('2w'), findsOneWidget);
    expect(find.text('10 days'), findsNothing);
  });

  testWidgets('a chosen day replaces the presets, and Delete takes it back',
      (tester) async {
    patients.set(testPatient(id: 'chosen-patient')
      ..followUpDate = DateTime(2026, 3, 24));

    await pumpField(tester, 'chosen-patient', anchor: DateTime(2026, 3, 10));
    expect(find.byKey(WK.fieldAppointmentFollowUpDate), findsOneWidget);
    expect(find.byKey(WK.clearFollowUp), findsOneWidget);
    expect(find.byKey(WK.followUpPreset('1w')), findsNothing,
        reason: 'the presets have done their job once a day is chosen');
    expect(find.text(txt('delete')), findsWidgets,
        reason: 'taking a promise back is a delete, as on the visit band');

    await tester.tap(find.byKey(WK.clearFollowUp));
    await tester.pumpAndSettle();

    expect(patients.get('chosen-patient')!.followUpDay, isNull);
    expect(find.byKey(WK.followUpPreset('1w')), findsOneWidget,
        reason: 'with no day, the intervals are back');
    expect(find.byKey(WK.clearFollowUp), findsNothing,
        reason: 'with no promise, there is nothing to take back');
  });

  testWidgets('the patient\'s row opens into a draft, not a promise',
      (tester) async {
    patients.set(testPatient(id: 'bar-patient', name: 'Bar Patient'));
    appointments.set(testAppointment(
      id: 'bar-visit',
      patientID: 'bar-patient',
      date: DateTime(2026, 3, 1),
      isDone: true,
    ));

    await pumpApexoApp(
      tester,
      const Center(
        child: SizedBox(
          width: 420,
          child: PatientFollowUpBar(patientID: 'bar-patient'),
        ),
      ),
    );

    expect(find.byKey(WK.patientFollowUpSet), findsOneWidget);
    expect(find.byKey(WK.fieldAppointmentFollowUp), findsNothing);

    await tester.tap(find.byKey(WK.patientFollowUpSet));
    await tester.pumpAndSettle();

    final expected = kFollowUpPresets.first.from(DateTime.now());
    expect(patients.get('bar-patient')!.followUpDay, isNull,
        reason: 'opening the row promises nothing yet');
    expect(find.byKey(WK.fieldAppointmentFollowUp), findsOneWidget);
    expect(find.byType(DateTimePicker), findsNothing,
        reason: 'opening the row chooses no day: the intervals are offered, '
            'and the dentist decides');
    expect(find.byKey(WK.followUpPreset('1w')), findsOneWidget);

    await tester.tap(find.byKey(WK.followUpPreset('1w')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(WK.followUpSave));
    await tester.pumpAndSettle();

    expect(patients.get('bar-patient')!.followUpDay, expected,
        reason: 'the day chosen is the day stored');

    await tester.tap(find.byKey(WK.clearFollowUp));
    await tester.pumpAndSettle();

    expect(patients.get('bar-patient')!.followUpDay, isNull);
    expect(find.byKey(WK.patientFollowUpSet), findsOneWidget,
        reason: 'taking the promise back folds the row again');
    expect(find.byKey(WK.fieldAppointmentFollowUp), findsNothing);
  });

  testWidgets('an opened row with nothing chosen can be folded again',
      (tester) async {
    patients.set(testPatient(id: 'collapse-patient'));
    appointments.set(testAppointment(
      id: 'collapse-visit',
      patientID: 'collapse-patient',
      date: DateTime(2026, 3, 1),
      isDone: true,
    ));

    await pumpApexoApp(
      tester,
      const Center(
        child: SizedBox(
          width: 420,
          child: PatientFollowUpBar(patientID: 'collapse-patient'),
        ),
      ),
    );

    await tester.tap(find.byKey(WK.patientFollowUpSet));
    await tester.pumpAndSettle();
    expect(find.byKey(WK.fieldAppointmentFollowUp), findsOneWidget);

    // Nothing chosen, so nothing to cancel: the row's own handle folds it.
    await tester.tap(find.byKey(WK.followUpCollapse));
    await tester.pumpAndSettle();

    expect(find.byKey(WK.fieldAppointmentFollowUp), findsNothing);
    expect(find.byKey(WK.patientFollowUpSet), findsOneWidget);
    expect(patients.get('collapse-patient')!.followUpDay, isNull);
  });

  testWidgets('no follow-up row for a patient who has never been seen',
      (tester) async {
    patients.set(testPatient(id: 'fresh-patient', name: 'Fresh Patient'));

    await pumpApexoApp(
      tester,
      const Center(
        child: SizedBox(
          width: 420,
          child: PatientFollowUpBar(patientID: 'fresh-patient'),
        ),
      ),
    );

    expect(find.byKey(WK.patientFollowUpSet), findsNothing,
        reason: 'nothing done, nothing to come back from');
    expect(find.byKey(WK.patientFollowUpBar), findsNothing);
  });

  testWidgets('the visit field and the patient row are one promise',
      (tester) async {
    patients.set(testPatient(id: 'live-patient', name: 'Live Patient'));
    appointments.set(testAppointment(
      id: 'live-visit',
      patientID: 'live-patient',
      date: DateTime(2026, 3, 1),
      isDone: true,
    ));

    await pumpApexoApp(
      tester,
      Center(
        child: SizedBox(
          width: 700,
          height: 420,
          child: SingleChildScrollView(
            child: Column(
              children: [
                FollowUpField(
                  patientID: 'live-patient',
                  anchor: DateTime(2026, 3, 10),
                ),
                const PatientFollowUpBar(patientID: 'live-patient'),
              ],
            ),
          ),
        ),
      ),
    );

    expect(find.byKey(WK.patientFollowUpSet), findsOneWidget,
        reason: 'the patient has no promise yet, so their row is a button');

    // The visit sets it…
    await tester.tap(find.byKey(WK.followUpPreset('2w')).first);
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(WK.followUpSave));
    await tester.pumpAndSettle();

    expect(patients.get('live-patient')!.followUpDay, DateTime(2026, 3, 24));
    expect(find.byKey(WK.patientFollowUpSet), findsNothing,
        reason: 'the patient\'s row unfolded with the visit\'s promise');

    // …and the patient's own row takes it back.
    await tester.tap(find.byKey(WK.clearFollowUp).last);
    await tester.pumpAndSettle();

    expect(patients.get('live-patient')!.followUpDay, isNull);
    expect(find.byKey(WK.patientFollowUpSet), findsOneWidget,
        reason: 'the patient\'s row folded again');
  });

  testWidgets('removing another follow-up preserves the remaining face state',
      (tester) async {
    final first = testPatient(id: 'first-face');
    final second = testPatient(id: 'second-face');
    Future<void> pumpBand(List<Patient> people) => pumpApexoApp(
          tester,
          Center(
              child: SizedBox(
            width: 700,
            child: FollowUpBand(followUps: [
              for (final patient in people)
                FollowUpDue(patient: patient, date: DateTime(2026, 3, 20)),
            ]),
          )),
        );

    await pumpBand([first, second]);
    final face = find.byKey(WK.followUpAvatar(second.id));
    final state = tester.state(face);
    await pumpBand([second]);
    expect(tester.state(face), same(state));
  });

  testWidgets('a face opens the follow-up card instead of booking',
      (tester) async {
    final patient = testPatient(id: 'card-patient', name: 'Card Patient');
    patients.set(patient);
    FollowUpDue? booked;

    await pumpApexoApp(
      tester,
      Center(
        child: SizedBox(
          width: 700,
          child: FollowUpBand(
            followUps: [
              FollowUpDue(patient: patient, date: DateTime(2026, 3, 20)),
            ],
            onBook: (followUp, {at}) => booked = followUp,
          ),
        ),
      ),
    );

    expect(find.byKey(WK.followUpAvatar('card-patient')), findsOneWidget);
    expect(find.text('Card Patient'), findsNothing,
        reason: 'the folded band is faces, not names');

    await tester.tap(find.byKey(WK.followUpAvatar('card-patient')));
    await tester.pumpAndSettle();

    expect(find.byType(FollowUpCard), findsOneWidget);
    expect(booked, isNull, reason: 'a peek at the card books nothing');
    expect(find.byKey(WK.followUpPatientLink), findsOneWidget,
        reason: 'the name in the card is a link to the record');
    expect(find.byIcon(WindowsIcons.subscription_add), findsOneWidget,
        reason: 'booking wears the "new subscription" glyph');

    await tester.tap(find.byKey(WK.bookFollowUp));
    await tester.pumpAndSettle();

    expect(booked?.patient.id, 'card-patient');
  });

  testWidgets('the history heads with the follow-up card', (tester) async {
    patients.set(testPatient(id: 'history-patient', name: 'History Patient'));
    appointments.set(testAppointment(
      id: 'history-visit',
      patientID: 'history-patient',
      date: DateTime(2026, 1, 10),
      isDone: true,
    ));

    await pumpApexoApp(
      tester,
      Center(
        child: SizedBox(
          width: 620,
          height: 600,
          child: SingleChildScrollView(
            child: PatientAppointments(patients.get('history-patient')!),
          ),
        ),
      ),
    );

    expect(find.byKey(WK.followUpSummaryCard), findsOneWidget,
        reason: 'the one thing in the history that has not happened yet');
    expect(find.byKey(WK.followUpSummarySet), findsOneWidget);

    await tester.tap(find.byKey(WK.followUpSummarySet));
    await tester.pumpAndSettle();

    expect(patients.get('history-patient')!.followUpDay,
        kFollowUpPresets.first.from(DateTime.now()));
    expect(find.byKey(WK.followUpRemove), findsOneWidget);

    await tester.tap(find.byKey(WK.followUpRemove));
    await tester.pumpAndSettle();

    expect(patients.get('history-patient')!.followUpDay, isNull);
    expect(find.byKey(WK.followUpSummarySet), findsOneWidget);
  });

  testWidgets('the band unfolds into the day\'s list of patients',
      (tester) async {
    final patient = testPatient(id: 'sheet-patient', name: 'Sheet Patient');
    patients.set(patient);
    setFollowUp(patient.id, DateTime(2026, 3, 20));

    await pumpApexoApp(
      tester,
      Center(
        child: SizedBox(
          width: 700,
          child: FollowUpBand(
            followUps: [
              FollowUpDue(patient: patient, date: DateTime(2026, 3, 20)),
            ],
            onBook: (_, {at}) {},
          ),
        ),
      ),
    );

    expect(find.text('Sheet Patient'), findsNothing);

    final foldedWidth = tester.getSize(find.byKey(WK.followUpBand)).width;

    await tester.tap(find.byKey(WK.followUpsBandToggle));
    await tester.pumpAndSettle();

    expect(find.text('Sheet Patient'), findsOneWidget,
        reason: 'the sheet is for calling, so it names who to call');
    expect(tester.getSize(find.byKey(WK.followUpBand)).width, foldedWidth,
        reason: 'the sheet keeps the band\'s width');
    // The two acts of a promise: keep it with a visit, or take it back.
    expect(find.byIcon(WindowsIcons.subscription_add), findsOneWidget);
    expect(find.byIcon(WindowsIcons.delete), findsOneWidget);

    await tester.tap(find.byKey(WK.followUpRemove));
    await tester.pumpAndSettle();
    expect(patients.get('sheet-patient')!.followUpDay, isNull,
        reason: 'the trash takes the promise back');

    // The band's own handle folds the sheet away again.
    await tester.tap(find.byKey(WK.followUpsBandToggle));
    await tester.pumpAndSettle();

    expect(find.text('Sheet Patient'), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('the agenda floats the day\'s follow-ups over the list',
      (tester) async {
    final patient = testPatient(id: 'agenda-patient', name: 'Agenda Patient');
    patients.set(patient);

    await pumpApexoApp(
      tester,
      Center(
        child: SizedBox(
          width: 700,
          height: 400,
          child: AgendaListView<Appointment>(
            items: [
              testAppointment(
                id: 'agenda-visit',
                patientID: 'someone-else',
                date: DateTime(2026, 3, 20, 9),
              ),
            ],
            showPayments: false,
            onSelect: (_, __) {},
            onSetTime: (_) {},
            followUps: [
              FollowUpDue(patient: patient, date: DateTime(2026, 3, 20)),
            ],
            onBookFollowUp: (_, {at}) {},
          ),
        ),
      ),
    );

    expect(find.byKey(WK.followUpBand), findsOneWidget);
    final list = tester.getRect(find.byType(AgendaListView<Appointment>));
    final band = tester.getRect(find.byKey(WK.followUpBand));
    expect(band.bottom, closeTo(list.bottom - 10, 2));
  });

  testWidgets(
      'a face dragged onto the timeline books the hour it is dropped on',
      (tester) async {
    final patient = testPatient(id: 'drop-patient', name: 'Drop Patient');
    patients.set(patient);
    final day = DateTime(2026, 3, 20);
    FollowUpDue? booked;
    DateTime? bookedAt;

    await pumpApexoApp(
      tester,
      Center(
        child: SizedBox(
          width: 760,
          height: 560,
          child: CalendarTimelineView(
            items: const [],
            showPayments: false,
            selectedDate: day,
            onSelect: (_, __) {},
            onSetTime: (_) {},
            onAddNew: (_) {},
            followUps: [
              FollowUpDue(patient: patient, date: day),
            ],
            onBookFollowUp: (followUp, {at}) {
              booked = followUp;
              bookedAt = at;
            },
          ),
        ),
      ),
    );

    final face = find.byKey(WK.followUpAvatar('drop-patient'));
    expect(face, findsOneWidget);

    await tester.drag(face, const Offset(0, -220));
    await tester.pumpAndSettle();

    expect(booked?.patient.id, 'drop-patient');
    expect(bookedAt, isNotNull, reason: 'the grid answered with an hour');
    expect(sameCalendarDay(bookedAt!, day), isTrue);
    expect(tester.takeException(), isNull);
  });

  testWidgets('nothing of the feature is drawn while it is switched off',
      (tester) async {
    final patient = testPatient(id: 'off-patient', name: 'Off Patient')
      ..followUpDate = DateTime(2026, 3, 24);
    patients.set(patient);
    appointments.set(testAppointment(
      id: 'off-visit',
      patientID: 'off-patient',
      date: DateTime(2026, 3, 1),
      isDone: true,
    ));
    globalSettings.followUpsEnabled = false;

    // The visit's field.
    await pumpField(tester, 'off-patient', anchor: DateTime(2026, 3, 10));
    expect(find.byKey(WK.fieldAppointmentFollowUp), findsNothing);

    // The patient's row, their history card and the day's band.
    await pumpApexoApp(
      tester,
      const Center(
        child: SizedBox(
          width: 620,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              PatientFollowUpBar(patientID: 'off-patient'),
              FollowUpSummaryCard(patientID: 'off-patient'),
            ],
          ),
        ),
      ),
    );
    expect(find.byKey(WK.patientFollowUpBar), findsNothing);
    expect(find.byKey(WK.followUpSummaryCard), findsNothing);

    // A band handed a promise anyway draws nothing, and a day's inbox is empty.
    expect(followUpsOn(DateTime(2026, 3, 24)), isEmpty);
    await pumpApexoApp(
      tester,
      Center(
        child: SizedBox(
          width: 700,
          child: FollowUpBand(
            followUps: [
              FollowUpDue(patient: patient, date: DateTime(2026, 3, 24))
            ],
            onBook: (_, {at}) {},
          ),
        ),
      ),
    );
    expect(find.byKey(WK.followUpBand), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('the note is what the band says, in place of the day',
      (tester) async {
    patients.set(testPatient(id: 'note-patient', name: 'Note Patient'));

    await pumpField(tester, 'note-patient', anchor: DateTime.now());
    expect(find.byKey(WK.fieldFollowUpNote), findsNothing,
        reason: 'a note is what the visit is for; there is no visit yet');

    await tester.tap(find.byKey(WK.followUpPreset('1w')));
    await tester.pumpAndSettle();
    await tester.enterText(
        find.byKey(WK.fieldFollowUpNote), ' Bring the X-ray ');
    await tester.pumpAndSettle();

    expect(patients.get('note-patient')!.followUpNote, isEmpty,
        reason: 'the note is a draft with the day');

    await tester.tap(find.byKey(WK.followUpSave));
    await tester.pumpAndSettle();

    final saved = patients.get('note-patient')!;
    expect(saved.followUpNote, 'Bring the X-ray',
        reason: 'stored trimmed, with the day it belongs to');
    final day = saved.followUpDay!;

    await pumpApexoApp(
      tester,
      Center(
        child: SizedBox(
          width: 700,
          child: FollowUpBand(
            followUps: [FollowUpDue(patient: saved, date: day)],
            onBook: (_, {at}) {},
          ),
        ),
      ),
    );
    await tester.tap(find.byKey(WK.followUpsBandToggle));
    await tester.pumpAndSettle();

    expect(find.text('Bring the X-ray'), findsOneWidget,
        reason: 'the clinic calls about the note, not about the date');
    expect(find.text(followUpRelativeLabel(day)), findsNothing,
        reason: 'the note stands where the day used to be said');
  });

  testWidgets('a late promise still says it is late, beside the note',
      (tester) async {
    final late = dayOnly(DateTime.now()).subtract(const Duration(days: 9));
    final patient = testPatient(id: 'late-patient', name: 'Late Patient')
      ..followUpDate = late
      ..followUpNote = 'Review the crown';
    patients.set(patient);

    await pumpApexoApp(
      tester,
      Center(
        child: SizedBox(
          width: 700,
          child: FollowUpBand(
            followUps: [FollowUpDue(patient: patient, date: late)],
          ),
        ),
      ),
    );
    await tester.tap(find.byKey(WK.followUpsBandToggle));
    await tester.pumpAndSettle();

    expect(find.text('Review the crown'), findsOneWidget);
    expect(
        find.descendant(
          of: find.byKey(WK.followUpRow(patient.id)),
          matching: find.text(txt('overdue')),
        ),
        findsOneWidget,
        reason: 'late is still said, next to what is late');
  });

  testWidgets('Cancel drops the draft and leaves the promise as it was',
      (tester) async {
    patients.set(testPatient(id: 'cancel-patient')
      ..followUpDate = DateTime(2026, 3, 24)
      ..followUpNote = 'Review the crown');

    await pumpField(tester, 'cancel-patient', anchor: DateTime(2026, 3, 10));
    await tester.enterText(find.byKey(WK.fieldFollowUpNote), 'Something else');
    await tester.pumpAndSettle();

    expect(find.byKey(WK.followUpSave), findsOneWidget,
        reason: 'an unsaved note is a draft, and can be kept or dropped');

    await tester.tap(find.byKey(WK.followUpCancel));
    await tester.pumpAndSettle();

    expect(patients.get('cancel-patient')!.followUpNote, 'Review the crown');
    expect(find.byKey(WK.followUpSave), findsNothing);
    expect(find.text('Something else'), findsNothing,
        reason: 'the row goes back to the promise the store holds');
    expect(find.text('Review the crown'), findsOneWidget);
  });
}
