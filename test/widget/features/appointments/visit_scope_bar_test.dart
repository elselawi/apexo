@Tags(['serial'])
library;

import 'package:apexo/common_widgets/teeth_selector/tx_options.dart';
import 'package:apexo/features/appointments/appointment_model.dart';
import 'package:apexo/features/appointments/appointments_store.dart';
import 'package:apexo/features/appointments/visit_scope_bar.dart';
import 'package:apexo/features/patients/patient_model.dart';
import 'package:apexo/features/patients/patients_store.dart';
import 'package:apexo/services/login.dart';
import 'package:apexo/services/localization/locale.dart';
import 'package:apexo/services/perm.dart';
import 'package:apexo/shared/dental_chart/dental_chart_session.dart';
import 'package:apexo/widget_keys.dart';
import 'package:fluent_ui/fluent_ui.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../../helpers/model_factory.dart';
import '../../../helpers/pump_app.dart';

void main() {
  late Map<String, Patient> originalPatients;
  late Map<String, Appointment> originalAppointments;
  late List<int> originalPermissions;

  setUp(() {
    originalPatients = {...patients.observableMap.docs};
    originalAppointments = {...appointments.observableMap.docs};
    originalPermissions = login.savedPermissions;
    patients.observableMap.clear();
    appointments.observableMap.clear();
    login.savedPermissions = Perm.full;
  });

  tearDown(() {
    patients.observableMap
      ..clear()
      ..setAll(originalPatients.values.toList());
    appointments.observableMap
      ..clear()
      ..setAll(originalAppointments.values.toList());
    login.savedPermissions = originalPermissions;
  });

  for (var language = 0; language < locale.list.length; language++) {
    testWidgets('timeline units follow ${locale.list[language].$code}',
        (tester) async {
      final previous = locale.selected();
      addTearDown(() => locale.select(previous));
      locale.select(language);
      final patient = testPatient(id: 'localized-interval');
      patients.set(patient);
      final from = DateTime(2026, 1, 1);
      appointments.setAll([
        testAppointment(id: 'interval-start', patientID: patient.id, date: from),
        testAppointment(id: 'interval-end', patientID: patient.id,
            date: from.add(const Duration(days: 7))),
      ]);
      final session = DentalChartSession(
        id: 'patient:${patient.id}', titleKey: 'dentalChart',
        subtitle: () => patient.title, type: StateType.state,
        teeth: {}, extraNotes: {}, history: () => [], oldNotes: () => {},
        historyTitle: 'toothHistory',
      );
      await pumpApexoApp(tester, Directionality(
        textDirection: locale.s.$direction,
        child: SizedBox(width: 700, child: VisitScopeBar(patient: patient, session: session)),
      ));
      expect(find.text('7${txt('timelineDayUnit')}'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });
  }

  for (final direction in TextDirection.values) {
    for (final visitCount in [0, 1, 4, 30]) {
      testWidgets(
          'initial exam joins the timeline: $visitCount visits, $direction',
          (tester) async {
        final patient = testPatient(id: 'scope-patient');
        patients.set(patient);
        for (var i = 0; i < visitCount; i++) {
          appointments.set(testAppointment(
            id: 'scope-visit-$i',
            patientID: patient.id,
            date: DateTime(2026, 1, i + 1),
          ));
        }
        final session = DentalChartSession(
          id: 'patient:${patient.id}',
          titleKey: 'dentalChart',
          subtitle: () => patient.title,
          type: StateType.state,
          teeth: {},
          extraNotes: {},
          history: () => [],
          oldNotes: () => {},
          historyTitle: 'toothHistory',
        );
        await pumpApexoApp(
          tester,
          Center(
            child: Directionality(
              textDirection: direction,
              child: SizedBox(
                width: 300,
                child: VisitScopeBar(patient: patient, session: session),
              ),
            ),
          ),
          theme:
              direction == TextDirection.rtl ? ThemeMode.dark : ThemeMode.light,
        );

        final origin = find.byKey(ValueKey('scope-patient:${patient.id}'));
        final marker = find.byKey(const ValueKey('scope-initial-exam-marker'));
        expect(origin, findsOneWidget);
        expect(marker, findsOneWidget);
        expect(find.byKey(WK.chartAddAppointment), findsOneWidget);
        expect(tester.getSize(origin).height, 40);
        expect(tester.getCenter(marker).dy - tester.getTopLeft(origin).dy, 14);
        final markerDecoration = tester
            .widget<AnimatedContainer>(marker)
            .decoration! as BoxDecoration;
        expect(markerDecoration.borderRadius, BorderRadius.circular(12));
        expect(tester.getSize(marker).width, greaterThan(24));
        expect(find.descendant(of: marker, matching: find.byType(Text)),
            findsOneWidget);
        expect(find.descendant(of: marker, matching: find.byType(Icon)),
            findsNothing);
        final zoom = find.descendant(
            of: origin, matching: find.byIcon(WindowsIcons.zoom));
        expect(zoom, findsOneWidget);
        expect(tester.getTopLeft(zoom).dy,
            greaterThan(tester.getBottomLeft(marker).dy));
        final semantics = tester.widget<Semantics>(find
            .descendant(of: origin, matching: find.byType(Semantics))
            .first);
        expect(semantics.properties.selected, isTrue);
        expect(semantics.properties.button, isTrue);

        final track = find.byKey(const ValueKey('scope-timeline-track'));
        expect(track, visitCount == 0 ? findsNothing : findsOneWidget);
        final emptyTrack = find.byKey(const ValueKey('scope-empty-track'));
        expect(emptyTrack, visitCount == 0 ? findsOneWidget : findsNothing);
        if (visitCount == 0) {
          expect(tester.getSize(emptyTrack).width, greaterThan(0));
          expect(
              tester.getTopLeft(emptyTrack).dy, tester.getTopLeft(origin).dy);
        }
        if (visitCount > 0) {
          final scroll = tester.widget<SingleChildScrollView>(
              find.byKey(const ValueKey('scope-visit-scroll')));
          expect(scroll.controller!.hasClients, isTrue);
          expect(scroll.controller!.position.maxScrollExtent > 0,
              visitCount == 30);
          expect(tester.getTopLeft(track).dy, tester.getTopLeft(origin).dy);
        }
        await tester.tap(origin);
        await tester.pumpAndSettle();
        expect(session.id, 'patient:${patient.id}');
        expect(tester.takeException(), isNull);
      });
    }
  }

  /// The chart the scope bar draws: a visit's chart names the visit, a
  /// patient's chart names the patient.
  DentalChartSession chartFor(Patient patient, String scope) =>
      DentalChartSession(
        id: scope,
        titleKey: 'dentalChart',
        subtitle: () => patient.title,
        type: StateType.state,
        teeth: {},
        extraNotes: {},
        history: () => [],
        oldNotes: () => {},
        historyTitle: 'toothHistory',
      );

  Finder ring(String id) =>
      find.byKey(ValueKey('scope-appointment-ripple:$id'));
  Finder painted(Finder ripple) =>
      find.descendant(of: ripple, matching: find.byType(CustomPaint));

  testWidgets('the open visit radiates, the rest of the timeline stays still',
      (tester) async {
    final patient = testPatient(id: 'ripple-patient');
    patients.set(patient);
    final older = testAppointment(
      id: 'ripple-older',
      patientID: patient.id,
      date: DateTime(2026, 1, 1),
    );
    final open = testAppointment(
      id: 'ripple-open',
      patientID: patient.id,
      date: DateTime(2026, 2, 1),
    );
    appointments.set(older);
    appointments.set(open);

    await pumpApexoApp(
      tester,
      Center(
        child: SizedBox(
          width: 400,
          child: VisitScopeBar(
            patient: patient,
            session: chartFor(patient, 'appointment:${open.id}'),
          ),
        ),
      ),
      scopeRipple: true,
    );

    expect(painted(ring(open.id)), findsOneWidget);
    expect(ring(older.id), findsNothing,
        reason: 'a visit nobody opened has nothing to say with motion');
    expect(
        find.byKey(const ValueKey('scope-initial-exam-ripple')), findsNothing,
        reason: 'the chart is on a visit, not on the patient');

    // The ring keeps travelling frame after frame rather than drawing once.
    await tester.pump(const Duration(milliseconds: 900));
    expect(painted(ring(open.id)), findsOneWidget);
    await tester.pump(const Duration(milliseconds: 900));
    expect(painted(ring(open.id)), findsOneWidget);
    expect(tester.takeException(), isNull);

    // Leave no ticker running behind the test.
    debugPauseScopeRipple = true;
    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets(
      'the initial exam radiates only while the chart is on the patient',
      (tester) async {
    final patient = testPatient(id: 'ripple-origin-patient');
    patients.set(patient);
    appointments.set(testAppointment(
      id: 'ripple-origin-visit',
      patientID: patient.id,
      date: DateTime(2026, 1, 5),
    ));

    await pumpApexoApp(
      tester,
      Center(
        child: SizedBox(
          width: 400,
          child: VisitScopeBar(
            patient: patient,
            session: chartFor(patient, 'patient:${patient.id}'),
          ),
        ),
      ),
      scopeRipple: true,
    );

    final originRipple =
        find.byKey(const ValueKey('scope-initial-exam-ripple'));
    expect(painted(originRipple), findsOneWidget);
    expect(ring('ripple-origin-visit'), findsNothing);

    // Reduced motion stills the ring without losing the selected pill.
    tester.platformDispatcher.accessibilityFeaturesTestValue =
        const FakeAccessibilityFeatures(disableAnimations: true);
    addTearDown(tester.platformDispatcher.clearAccessibilityFeaturesTestValue);
    await tester.pump();
    expect(painted(originRipple), findsNothing);
    expect(find.byKey(const ValueKey('scope-initial-exam-marker')),
        findsOneWidget);
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
  });
}
