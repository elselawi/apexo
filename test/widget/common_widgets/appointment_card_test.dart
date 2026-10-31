@Tags(['serial'])
library;

import 'dart:convert';

import 'package:apexo/common_widgets/appointment_card.dart';
import 'package:apexo/common_widgets/grid_gallery.dart';
import 'package:apexo/features/appointments/open_appointment.dart';
import 'package:apexo/features/patients/patients_store.dart';
import 'package:apexo/services/localization/locale.dart';
import 'package:apexo/utils/imgs.dart';
import 'package:apexo/services/login.dart';
import 'package:apexo/services/perm.dart';
import 'package:apexo/widget_keys.dart';
import 'package:fluent_ui/fluent_ui.dart';
import 'package:flutter_test/flutter_test.dart';
import '../../helpers/model_factory.dart';
import '../../helpers/pump_app.dart';

void main() {
  late List<int> originalPerms;

  setUp(() {
    originalPerms = login.savedPermissions;
    login.savedPermissions = Perm.full;
  });

  tearDown(() {
    login.savedPermissions = originalPerms;
  });

  testWidgets(
      'section taps open the matching window through the supplied opener',
      (tester) async {
    const photo = 'card-section-preview.gif';
    final previous = imgMemoryCache[photo];
    imgMemoryCache[photo] = MemoryImage(base64Decode(
        'R0lGODlhAQABAIAAAAAAAP///yH5BAEAAAAALAAAAAABAAEAAAIBRAA7'));
    addTearDown(() {
      if (previous == null) {
        imgMemoryCache.remove(photo);
      } else {
        imgMemoryCache[photo] = previous;
      }
    });
    final appointment = testAppointment(
      id: 'card-section-actions',
      date: DateTime(2026, 1, 15),
      teeth: {'11': 'filling'},
      imgs: [photo],
      preOpNotes: 'Before treatment',
      postOpNotes: 'After treatment',
      price: 0,
      paid: 0,
    );
    final opened = <AppointmentWindow>[];
    await tester.pumpWidget(
      FluentApp(
        home: SingleChildScrollView(
          child: SizedBox(
            width: 500,
            child: AppointmentCard(
              appointment: appointment,
              number: 1,
              readOnly: true,
              onOpen: (item, window) {
                expect(item, same(appointment));
                opened.add(window);
              },
            ),
          ),
        ),
      ),
    );
    // Image-loading indicators need bounded pumps rather than pumpAndSettle.
    await tester.pump(const Duration(seconds: 1));

    for (final key in [
      'dentalNotes',
      'photos',
      'pre-opNotes',
      'post-opNotes'
    ]) {
      final section = find.text(txt(key)).first;
      await tester.ensureVisible(section);
      await tester.tapAt(tester.getCenter(section));
      await tester.pump(const Duration(milliseconds: 200));
    }
    final photos = find.byType(GridGallery);
    await tester.ensureVisible(photos);
    await tester.tapAt(tester.getCenter(photos));
    await tester.pump(const Duration(milliseconds: 200));
    final go = find.byIcon(FluentIcons.go);
    await tester.ensureVisible(go);
    await tester.tap(go);
    await tester.pump(const Duration(milliseconds: 200));

    expect(opened, [
      AppointmentWindow.dentalChart,
      AppointmentWindow.gallery,
      AppointmentWindow.details,
      AppointmentWindow.details,
      AppointmentWindow.gallery,
      AppointmentWindow.details,
    ]);
    expect(tester.takeException(), isNull);
  });

  testWidgets('patient, doctors, labwork, prescription and pay sections open their editors',
      (tester) async {
    final previousPatients = patients.docs.values.toList();
    addTearDown(() {
      patients.observableMap.clear();
      patients.setAll(previousPatients);
    });
    final patient = testPatient(id: 'card-section-patient');
    patients.set(patient);
    final appointment = testAppointment(
      id: 'card-other-sections',
      patientID: patient.id,
      operatorsIDs: ['card-operator'],
      date: DateTime(2026, 1, 15),
      hasLabwork: true,
      labworkNotes: 'Lab order',
      prescriptions: ['Prescription preview'],
    );
    final opened = <AppointmentWindow>[];
    await pumpApexoApp(
      tester,
      SingleChildScrollView(
        child: AppointmentCard(
          appointment: appointment,
          number: 1,
          readOnly: true,
          onOpen: (item, window) {
            expect(item, same(appointment));
            opened.add(window);
          },
        ),
      ),
    );

    for (final key in ['patient', 'doctors', 'labwork', 'prescription', 'price']) {
      final section = find.text(txt(key)).first;
      await tester.ensureVisible(section);
      await tester.tapAt(tester.getCenter(section));
      await tester.pumpAndSettle();
    }

    expect(opened, [
      AppointmentWindow.details,
      AppointmentWindow.details,
      AppointmentWindow.labwork,
      AppointmentWindow.operative,
      AppointmentWindow.operative,
    ]);
    expect(tester.takeException(), isNull);
  });

  testWidgets('operative shortcuts respect window permissions while labwork stays available',
      (tester) async {
    login.savedPermissions = Perm.full..[Perm.postOp] = 0;
    final appointment = testAppointment(
      id: 'card-restricted-sections',
      date: DateTime(2026, 1, 15),
      hasLabwork: true,
      prescriptions: ['Restricted prescription'],
    );
    expect(canViewPostOp(appointment), isFalse);
    final opened = <AppointmentWindow>[];
    await pumpApexoApp(
      tester,
      SingleChildScrollView(
        child: AppointmentCard(
          appointment: appointment,
          number: 1,
          readOnly: true,
          onOpen: (_, window) => opened.add(window),
        ),
      ),
    );

    for (final key in ['prescription', 'price']) {
      final section = find.text(txt(key)).first;
      expect(find.ancestor(of: section, matching: find.byType(Button)), findsNothing);
      await tester.ensureVisible(section);
      await tester.tap(section);
      await tester.pumpAndSettle();
    }
    expect(opened, isEmpty);
    final labwork = find.text(txt('labwork')).first;
    await tester.ensureVisible(labwork);
    await tester.tapAt(tester.getCenter(labwork));
    await tester.pumpAndSettle();
    expect(opened, [AppointmentWindow.labwork]);
    expect(tester.takeException(), isNull);
  });

  testWidgets('hiding visit navigation also hides section shortcuts',
      (tester) async {
    var opened = 0;
    await pumpApexoApp(
      tester,
      AppointmentCard(
        appointment: testAppointment(preOpNotes: 'Preview only'),
        number: 1,
        readOnly: true,
        hide: const [AppointmentSections.openAppointmentButton],
        onOpen: (_, __) => opened++,
      ),
    );

    await tester.tap(find.text('Preview only').first);
    await tester.pumpAndSettle();

    expect(opened, 0);
    expect(find.byIcon(FluentIcons.go), findsNothing);
  });

  testWidgets('AppointmentCard renders without crashing', (tester) async {
    final appt = testAppointment(
      id: 'widget-test-1',
      date: DateTime(2026, 1, 15, 10, 30),
      price: 150.0,
      paid: 100.0,
      preOpNotes: 'Fixed pre-op note',
    );

    await pumpApexoApp(
      tester,
      SizedBox(
        width: 400,
        child: AppointmentCard(
          appointment: appt,
          number: 1,
          readOnly: true,
        ),
      ),
    );

    expect(find.byType(AppointmentCard), findsOneWidget);
    expect(find.text('Fixed pre-op note'), findsAtLeastNWidgets(1));
    expect(find.text('150'), findsAtLeastNWidgets(1));
    expect(find.text('100'), findsAtLeastNWidgets(1));
  });

  testWidgets('AppointmentCard with readOnly=true hides side icons',
      (tester) async {
    final appt = testAppointment(
        id: 'widget-test-3', patientID: 'return null when null');

    await pumpApexoApp(
      tester,
      SizedBox(
        width: 400,
        child: AppointmentCard(
          appointment: appt,
          number: 3,
          readOnly: true,
        ),
      ),
    );

    // Read-only should not have done checkbox or delete button
    expect(find.byIcon(FluentIcons.check_mark), findsNothing);
    expect(find.byKey(WK.acSideIcons), findsNothing);
  });

  testWidgets('AppointmentCard shows editable controls when readOnly is false',
      (tester) async {
    final appt = testAppointment(
      id: 'widget-test-editable',
      date: DateTime(2026, 1, 15, 10, 30),
      price: 0,
      paid: 0,
    );

    await pumpApexoApp(
      tester,
      SizedBox(
        width: 400,
        child: AppointmentCard(
          appointment: appt,
          number: 1,
        ),
      ),
    );

    expect(find.byKey(WK.acSideIcons), findsOneWidget);
    expect(find.byKey(WK.acCheckBox), findsOneWidget);
  });
}
