import 'package:apexo/features/appointments/appointment_indicators.dart';
import 'package:apexo/features/appointments/appointment_model.dart';
import 'package:apexo/features/appointments/events_agenda_widget.dart';
import 'package:apexo/features/appointments/events_timeline_widget.dart';
import 'package:apexo/features/patients/patients_store.dart';
import 'package:apexo/services/localization/locale.dart';
import 'package:apexo/widget_keys.dart';
import 'package:fluent_ui/fluent_ui.dart';
import 'package:flutter/gestures.dart' show PointerDeviceKind;
import 'package:flutter_test/flutter_test.dart';

import '../../../helpers/model_factory.dart';
import '../../../helpers/pump_app.dart';

void main() {
  /// A visit that carries one of everything the chip stands for.
  Appointment loaded() => testAppointment(
        id: 'indicators-test',
        date: DateTime(2026, 1, 15, 10),
        teeth: const {'11': 'filling'},
        teethExtraNotes: const {'11': 'Watches sweets'},
        prescriptions: const ['Amoxicillin 500mg'],
        hasLabwork: true,
        labName: 'Smile Lab',
        labworkNotes: 'Zirconia crown',
        imgs: const ['photo.jpg'],
        dcmImgs: const ['xray.dcm'],
      );

  Finder slot(AppointmentIndicator kind) =>
      find.byKey(WK.appointmentIndicator(kind.name));

  /// The card every icon in the chip opens.
  String card(WidgetTester tester) {
    final tooltip = tester.widget<Tooltip>(
      find.ancestor(
        of: find.byKey(WK.appointmentInfoBadges),
        matching: find.byType(Tooltip),
      ),
    );
    return tooltip.richMessage!.toPlainText();
  }

  testWidgets('the pile draws every kind the visit carries, in order',
      (tester) async {
    await pumpApexoApp(
      tester,
      SizedBox(width: 300, child: AppointmentIndicators(item: loaded())),
    );

    expect(find.byKey(WK.appointmentInfoBadges), findsOneWidget);
    for (final kind in AppointmentIndicator.values) {
      expect(slot(kind), findsOneWidget, reason: 'missing $kind');
    }
    expect(tester.takeException(), isNull);
  });

  testWidgets('the card holds the whole of what the pile stands for',
      (tester) async {
    await pumpApexoApp(
      tester,
      SizedBox(width: 300, child: AppointmentIndicators(item: loaded())),
    );

    final text = card(tester);
    for (final kind in AppointmentIndicator.values) {
      expect(text, contains(txt(kind.labelKey)), reason: 'card: $kind');
    }
    expect(text, contains('Watches sweets'));
    expect(text, contains('Amoxicillin 500mg'));
    expect(text, contains('Smile Lab'));
    expect(text, contains('Zirconia crown'));
    expect(text, contains('${txt('photos')}: 1'));
    expect(text, contains('${txt('dcm')}: 1'));
  });

  testWidgets('a visit with nothing extra draws no pile', (tester) async {
    final plain = testAppointment(id: 'plain-test');
    expect(AppointmentIndicators.hasAny(plain), isFalse);

    await pumpApexoApp(
      tester,
      SizedBox(width: 300, child: AppointmentIndicators(item: plain)),
    );
    expect(find.byKey(WK.appointmentInfoBadges), findsNothing);
  });

  testWidgets('the agenda leaves the teeth to its chips', (tester) async {
    final appointment = loaded();
    expect(
      AppointmentIndicators.hasAny(appointment, showDentalNotes: false),
      isTrue,
    );

    await pumpApexoApp(
      tester,
      SizedBox(
        width: 300,
        child: AppointmentIndicators(
          item: appointment,
          showDentalNotes: false,
        ),
      ),
    );
    expect(slot(AppointmentIndicator.dentalNotes), findsNothing);
    expect(slot(AppointmentIndicator.prescriptions), findsOneWidget);
  });

  testWidgets('a narrow line scales the pile rather than overflowing',
      (tester) async {
    // 120 is less than the pile and a note would like: the pile gives way.
    await pumpApexoApp(
      tester,
      Center(
        child: SizedBox(
          width: 120,
          height: 60,
          child: AppointmentInfoLine(
            item: loaded(),
            note: 'Sensitive to cold on the upper right',
          ),
        ),
      ),
    );

    expect(find.byKey(WK.appointmentInfoBadges), findsOneWidget);
    // Nothing is lost: every kind is still in the pile's card.
    expect(card(tester), contains(txt('gallery')));
    expect(tester.takeException(), isNull);
  });

  testWidgets('hovering the pile opens one card with everything',
      (tester) async {
    await pumpApexoApp(
      tester,
      Center(
        child: SizedBox(
          width: 300,
          child: AppointmentIndicators(item: loaded()),
        ),
      ),
    );

    final mouse = await tester.createGesture(kind: PointerDeviceKind.mouse);
    await mouse.addPointer(location: Offset.zero);
    addTearDown(mouse.removePointer);
    await tester.pump();

    await mouse.moveTo(tester.getCenter(find.byKey(WK.appointmentInfoBadges)));
    await tester.pump();
    await tester.pump(const Duration(seconds: 1));

    // One card: the prescription and the labwork are both in it.
    expect(find.textContaining('Amoxicillin 500mg'), findsOneWidget);
    expect(find.textContaining('Smile Lab'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('the agenda row and the timeline chip both show the pile',
      (tester) async {
    final appointment = loaded();

    await pumpApexoApp(
      tester,
      SizedBox(
        width: 900,
        height: 300,
        child: AgendaListView<Appointment>(
          items: [appointment],
          showPayments: false,
          onSelect: (_, __) {},
          onSetTime: (_) {},
        ),
      ),
    );
    expect(find.byKey(WK.appointmentInfoBadges), findsOneWidget);
    expect(slot(AppointmentIndicator.dentalNotes), findsNothing);

    await pumpApexoApp(
      tester,
      MediaQuery(
        data: const MediaQueryData(textScaler: TextScaler.linear(0.6)),
        child: SizedBox(
          width: 1200,
          height: 800,
          child: CalendarTimelineView(
            items: [appointment],
            showPayments: false,
            selectedDate: appointment.date,
            onSelect: (_, __) {},
            onSetTime: (_) {},
            onAddNew: (_) {},
          ),
        ),
      ),
    );
    expect(find.byKey(WK.appointmentInfoBadges), findsOneWidget);
    expect(slot(AppointmentIndicator.dentalNotes), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('a short card at a large text size keeps its title',
      (tester) async {
    final crowded = testAppointment(
      id: 'squeezed-chip',
      date: DateTime(2026, 1, 15, 10),
      // The shortest slot, at the largest text the app is likely to be given:
      // the chip has to give way somewhere, and it gives way by folding.
      duration: 15,
      preOpNotes: 'Sensitive to cold on the upper right',
      paid: 120,
      teeth: const {'11': 'filling', '21': 'crown'},
      teethExtraNotes: const {'11': 'Watches sweets'},
      prescriptions: const ['Amoxicillin 500mg', 'Ibuprofen 400mg'],
      hasLabwork: true,
      labName: 'Smile Lab',
      labworkNotes: 'Zirconia crown',
      imgs: const ['photo.jpg'],
    );

    await pumpApexoApp(
      tester,
      MediaQuery(
        data: const MediaQueryData(textScaler: TextScaler.linear(1.6)),
        child: SizedBox(
          width: 1200,
          height: 800,
          child: CalendarTimelineView(
            items: [crowded],
            showPayments: false,
            selectedDate: crowded.date,
            onSelect: (_, __) {},
            onSetTime: (_) {},
            onAddNew: (_) {},
          ),
        ),
      ),
    );

    expect(find.byType(TimelineChip), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('a narrow agenda row keeps its patient visible', (tester) async {
    final patient = testPatient(id: 'narrow-patient');
    patients.set(patient);
    // The record is taken away, not archived: an archived patient is still in
    // the store, and the next test would find it there.
    addTearDown(() => patients.observableMap.remove(patient.id));
    final appointment = loaded()..patientID = patient.id;

    await pumpApexoApp(
      tester,
      // About the narrowest a phone keeps the agenda: the chip rides on the
      // note's line, so it takes nothing from the patient's name.
      SizedBox(
        width: 360,
        height: 400,
        child: AgendaListView<Appointment>(
          items: [appointment],
          showPayments: false,
          onSelect: (_, __) {},
          onSetTime: (_) {},
        ),
      ),
    );

    expect(find.byKey(WK.calendarAppointmentTile), findsOneWidget);
    // `Txt` and the `Text` it builds both carry the name.
    expect(find.text(patient.title), findsWidgets);
    expect(tester.takeException(), isNull);
  });

  testWidgets('a loaded card and an empty card keep a short slot unbroken',
      (tester) async {
    final crowded = testAppointment(
      id: 'crowded-chip',
      date: DateTime(2026, 1, 15, 10),
      duration: 15,
      preOpNotes: 'Sensitive to cold on the upper right',
      paid: 120,
      teeth: const {'11': 'filling', '21': 'crown'},
      teethExtraNotes: const {'11': 'Watches sweets'},
      prescriptions: const ['Amoxicillin 500mg', 'Ibuprofen 400mg'],
      hasLabwork: true,
      labName: 'Smile Lab',
      labworkNotes: 'Zirconia crown',
      imgs: const ['photo.jpg'],
    );
    final empty = testAppointment(
      id: 'empty-chip',
      date: DateTime(2026, 1, 15, 11),
      duration: 15,
    );

    await pumpApexoApp(
      tester,
      SizedBox(
        width: 1200,
        height: 800,
        child: CalendarTimelineView(
          items: [crowded, empty],
          showPayments: true,
          selectedDate: crowded.date,
          onSelect: (_, __) {},
          onSetTime: (_) {},
          onAddNew: (_) {},
        ),
      ),
    );

    expect(find.byType(TimelineChip), findsNWidgets(2));
    // One chip's worth, not two: the empty visit draws none.
    expect(find.byKey(WK.appointmentInfoBadges), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
