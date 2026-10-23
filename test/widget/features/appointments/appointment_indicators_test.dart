import 'dart:convert';

import 'package:apexo/common_widgets/money_display.dart';
import 'package:apexo/utils/imgs.dart' show imgMemoryCache;
import 'package:apexo/features/appointments/appointment_indicators.dart';
import 'package:apexo/features/appointments/appointment_model.dart';
import 'package:apexo/features/appointments/events_agenda_widget.dart';
import 'package:apexo/features/appointments/events_timeline_widget.dart';
import 'package:apexo/features/appointments/open_appointment_panel.dart';
import 'package:apexo/services/login.dart';
import 'package:apexo/services/perm.dart';
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

  void allowWindows() {
    final previous = login.savedPermissions;
    login.savedPermissions = Perm.full;
    addTearDown(() => login.savedPermissions = previous);
  }

  testWidgets(
      'timeline indicators use a deeper chip fill and open only their window',
      (tester) async {
    allowWindows();
    final selected = <AppointmentWindow>[];
    var tappedChip = false;
    const color = Color(0xFF7851A9);
    await pumpApexoApp(
        tester,
        Center(
            child: SizedBox(
          width: 500,
          height: 80,
          child: TimelineChip(
            item: loaded(),
            color: color,
            showPayments: false,
            onTap: () => tappedChip = true,
            onSelect: selected.add,
            onLongPressStart: (_) {},
            onLongPressMove: (_) {},
            onLongPressEnd: () {},
          ),
        )));

    final rail =
        tester.widget<AnimatedContainer>(find.byKey(WK.appointmentInfoBadges));
    final fill = rail.decoration! as BoxDecoration;
    expect(fill.color, color.withValues(alpha: 0.18));
    expect(rail.foregroundDecoration, isNull);
    final ink = Color.lerp(color, Colors.black, 0.28);
    for (final kind in AppointmentIndicator.values) {
      final icon =
          find.descendant(of: slot(kind), matching: find.byIcon(kind.icon));
      expect(tester.widget<Icon>(icon).color, ink);
      await tester.tap(slot(kind));
      await tester.pump();
    }
    expect(selected, [
      AppointmentWindow.dentalChart,
      AppointmentWindow.operative,
      AppointmentWindow.labwork,
      AppointmentWindow.gallery,
    ]);
    expect(tappedChip, isFalse);

    final mouse = await tester.createGesture(kind: PointerDeviceKind.mouse);
    await mouse.addPointer(location: Offset.zero);
    addTearDown(mouse.removePointer);
    await mouse.moveTo(tester.getCenter(slot(AppointmentIndicator.labwork)));
    await tester.pumpAndSettle();
    final icon = find.descendant(
      of: slot(AppointmentIndicator.labwork),
      matching: find.byIcon(AppointmentIndicator.labwork.icon),
    );
    expect(tester.widget<Icon>(icon).color, ink);
    final hoveredRail =
        tester.widget<AnimatedContainer>(find.byKey(WK.appointmentInfoBadges));
    expect((hoveredRail.decoration! as BoxDecoration).color,
        color.withValues(alpha: 0.25));
    expect(tester.takeException(), isNull);
  });

  testWidgets('agenda indicator clicks select the relevant standalone window',
      (tester) async {
    allowWindows();
    final selected = <AppointmentWindow?>[];
    final appointment = loaded();
    await pumpApexoApp(
        tester,
        SizedBox(
          width: 900,
          height: 300,
          child: AgendaListView<Appointment>(
            items: [appointment],
            showPayments: false,
            onSelect: (item, window) {
              expect(item.id, appointment.id);
              selected.add(window);
            },
            onSetTime: (_) {},
          ),
        ));
    await tester.tap(slot(AppointmentIndicator.prescriptions));
    await tester.pump();
    await tester.tap(slot(AppointmentIndicator.labwork));
    await tester.pump();
    await tester.tap(slot(AppointmentIndicator.gallery));
    await tester.pump(const Duration(milliseconds: 200));
    await tester.pumpAndSettle();
    expect(selected, [
      AppointmentWindow.operative,
      AppointmentWindow.labwork,
      AppointmentWindow.gallery
    ]);
    expect(tester.takeException(), isNull);
  });

  testWidgets('all compact indicators remain visible and directly clickable',
      (tester) async {
    allowWindows();
    final selected = <AppointmentWindow>[];
    await pumpApexoApp(
      tester,
      Center(
          child: SizedBox(
        width: 60,
        child:
            AppointmentIndicators(item: loaded(), onOpenWindow: selected.add),
      )),
    );
    final bounds = tester.getRect(find.byKey(WK.appointmentInfoBadges));
    for (final kind in AppointmentIndicator.values) {
      expect(slot(kind), findsOneWidget);
      final rect = tester.getRect(slot(kind));
      expect(rect.width, greaterThan(0));
      expect(bounds.contains(rect.center), isTrue);
      await tester.tap(slot(kind));
      await tester.pump(const Duration(milliseconds: 200));
    }
    expect(selected, [
      AppointmentWindow.dentalChart,
      AppointmentWindow.operative,
      AppointmentWindow.labwork,
      AppointmentWindow.gallery,
    ]);
    expect(find.text('+3'), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('prescription shortcut respects operative-window permissions',
      (tester) async {
    final previous = login.savedPermissions;
    login.savedPermissions = Perm.zeroes;
    addTearDown(() => login.savedPermissions = previous);
    await pumpApexoApp(
        tester,
        Center(
            child: SizedBox(
          width: 180,
          child: AppointmentIndicators(
              item: loaded(),
              onOpenWindow: (_) => fail('Restricted window opened')),
        )));
    final button = tester.widget<Button>(find.descendant(
      of: slot(AppointmentIndicator.prescriptions),
      matching: find.byType(Button),
    ));
    expect(button.onPressed, isNull);
  });

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

  testWidgets('embedded indicators keep every category in a narrow strip',
      (tester) async {
    await pumpApexoApp(
      tester,
      Center(
        child: SizedBox(
          width: 60,
          child: AppointmentIndicators(
            item: loaded(),
            embedded: true,
            showGalleryThumbnail: false,
          ),
        ),
      ),
    );

    for (final kind in AppointmentIndicator.values) {
      expect(slot(kind), findsOneWidget);
    }
    expect(find.text('+3'), findsNothing);
    expect(card(tester), contains('Amoxicillin 500mg'));
    expect(card(tester), contains(txt('gallery')));
    expect(tester.getSize(find.byKey(WK.appointmentInfoBadges)).width,
        lessThanOrEqualTo(60));
    expect(tester.takeException(), isNull);
  });

  for (final xray in [false, true]) {
    testWidgets('compact strip keeps the ${xray ? "X-ray" : "photo"} preview',
        (tester) async {
      final name = xray ? 'indicator-preview.dcm' : 'indicator-preview.png';
      final cacheKey = xray ? '$name.png' : name;
      final image = MemoryImage(base64Decode(
        'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAACklEQVR4nGMAAQAABQABDQottAAAAABJRU5ErkJggg==',
      ));
      imgMemoryCache[cacheKey] = image;
      addTearDown(() => imgMemoryCache.remove(cacheKey));
      final appointment = testAppointment(
        id: 'preview-${xray ? "xray" : "photo"}',
        prescriptions: const ['Amoxicillin'],
        imgs: xray ? const [] : [name],
        dcmImgs: xray ? [name] : const [],
      );

      final selected = <AppointmentWindow>[];
      await pumpApexoApp(
        tester,
        Center(
            child: SizedBox(
          width: 32,
          child: AppointmentIndicators(
              item: appointment, onOpenWindow: selected.add),
        )),
      );
      final preview = find.descendant(
        of: slot(AppointmentIndicator.gallery),
        matching: find.byType(Image),
      );
      expect(preview, findsOneWidget);
      expect(tester.widget<Image>(preview).image, same(image));
      await tester.tap(preview);
      await tester.pump(const Duration(milliseconds: 200));
      await tester.pumpAndSettle();
      expect(selected, [AppointmentWindow.gallery]);
      expect(tester.takeException(), isNull);
    });
  }

  testWidgets('an extremely narrow strip constrains its preview fallback',
      (tester) async {
    await pumpApexoApp(
      tester,
      Center(
          child: SizedBox(
        width: 12,
        child: AppointmentIndicators(item: loaded()),
      )),
    );
    expect(slot(AppointmentIndicator.gallery), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('embedded indicators stay stationary on hover', (tester) async {
    await pumpApexoApp(
      tester,
      Center(
        child: SizedBox(
          width: 180,
          child: AppointmentIndicators(
            item: loaded(),
            embedded: true,
            showGalleryThumbnail: false,
          ),
        ),
      ),
    );
    final strip = find.byKey(WK.appointmentInfoBadges);
    final before = tester.getRect(strip);
    final mouse = await tester.createGesture(kind: PointerDeviceKind.mouse);
    await mouse.addPointer(location: Offset.zero);
    addTearDown(mouse.removePointer);
    await mouse.moveTo(tester.getCenter(strip));
    await tester.pump();
    await tester.pump(const Duration(seconds: 1));
    await tester.pumpAndSettle();
    expect(tester.getRect(strip), before);
    expect(find.textContaining('Amoxicillin 500mg'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  for (final direction in TextDirection.values) {
    for (final scale in [1.0, 1.6, 2.0]) {
      testWidgets('timeline contains its accessories at $direction / $scale',
          (tester) async {
        await pumpApexoApp(
          tester,
          Directionality(
            textDirection: direction,
            child: MediaQuery(
              data: MediaQueryData(textScaler: TextScaler.linear(scale)),
              child: Center(
                child: SizedBox(
                  width: 340,
                  height: 58,
                  child: TimelineChip(
                    item: loaded()
                      ..paid = 120
                      ..postOpNotes = 'Review healing in two weeks',
                    color: Colors.blue,
                    showPayments: true,
                    onTap: () {},
                    onSelect: (_) {},
                    onLongPressStart: (_) {},
                    onLongPressMove: (_) {},
                    onLongPressEnd: () {},
                  ),
                ),
              ),
            ),
          ),
          theme: ThemeMode.dark,
        );

        final rail = tester
            .widget<AnimatedContainer>(find.byKey(WK.appointmentInfoBadges));
        expect((rail.decoration! as BoxDecoration).color,
            Colors.blue.withValues(alpha: 0.24));
        expect(rail.foregroundDecoration, isNull);
        final chip = tester.getRect(find.byType(TimelineChip));
        final strip = tester.getRect(find.byKey(WK.appointmentInfoBadges));
        final money = tester.getRect(find.byType(MoneyDisplay));
        for (final accessory in [strip, money]) {
          expect(chip.contains(accessory.topLeft), isTrue);
          expect(chip.contains(accessory.bottomRight), isTrue);
        }
        expect(strip.overlaps(money), isFalse);
        for (final kind in AppointmentIndicator.values) {
          expect(slot(kind), findsOneWidget);
          expect(strip.contains(tester.getCenter(slot(kind))), isTrue);
        }
        final note =
            tester.getRect(find.text('Review healing in two weeks').last);
        expect(note.width, greaterThan(0));
        expect(note.height, greaterThan(0));
        expect(note.overlaps(strip), isFalse);
        expect(chip.contains(note.topLeft), isTrue);
        expect(chip.contains(note.bottomRight), isTrue);
        expect(tester.takeException(), isNull);
      });
    }
  }

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

  testWidgets(
      'agenda and timeline share the strip without hiding post-op notes',
      (tester) async {
    final appointment = loaded()..postOpNotes = 'Check the crown margins';

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
    expect(
        tester
            .widget<AppointmentIndicators>(find.byType(AppointmentIndicators))
            .embedded,
        isTrue);
    expect(find.text('Check the crown margins'), findsWidgets);
    expect(
        tester
            .widget<AppointmentIndicators>(find.byType(AppointmentIndicators))
            .showGalleryThumbnail,
        isTrue);

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
    expect(card(tester), contains(txt('dentalNotes')));
    expect(slot(AppointmentIndicator.gallery), findsOneWidget);
    expect(
        tester
            .widget<AppointmentIndicators>(find.byType(AppointmentIndicators))
            .embedded,
        isTrue);
    expect(find.text('Check the crown margins'), findsWidgets);
    expect(
        tester
            .widget<AppointmentIndicators>(find.byType(AppointmentIndicators))
            .showGalleryThumbnail,
        isTrue);
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

  testWidgets('a short card keeps its payment beside the pile', (tester) async {
    // The card the bug was reported on: the shortest slot, every badge, and
    // money taken — at a text size the OS scales up. The money is the one
    // thing the card never drops.
    final paid = testAppointment(
      id: 'paid-chip',
      date: DateTime(2026, 1, 15, 10),
      duration: 15,
      paid: 120,
      teeth: const {'11': 'filling'},
      teethExtraNotes: const {'11': 'Watches sweets'},
      prescriptions: const ['Amoxicillin 500mg'],
      hasLabwork: true,
      imgs: const ['photo.jpg'],
    );

    Future<void> pump({required bool showPayments}) => pumpApexoApp(
          tester,
          MediaQuery(
            data: const MediaQueryData(textScaler: TextScaler.linear(1.5)),
            child: SizedBox(
              width: 1200,
              height: 800,
              child: CalendarTimelineView(
                items: [paid],
                showPayments: showPayments,
                selectedDate: paid.date,
                onSelect: (_, __) {},
                onSetTime: (_) {},
                onAddNew: (_) {},
              ),
            ),
          ),
        );

    await pump(showPayments: true);
    expect(find.byKey(WK.appointmentInfoBadges), findsOneWidget);
    expect(find.byType(MoneyDisplay), findsOneWidget);
    expect(tester.takeException(), isNull);

    // The toggle still owns it: no money when the payments are off.
    await pump(showPayments: false);
    expect(find.byType(MoneyDisplay), findsNothing);
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
