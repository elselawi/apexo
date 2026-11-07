@Tags(['serial'])
library;

import 'package:apexo/features/accounts/accounts_controller.dart';
import 'package:apexo/features/appointments/appointment_model.dart';
import 'package:apexo/features/appointments/appointment_operators_widgets.dart';
import 'package:apexo/features/appointments/appointment_sessions.dart';
import 'package:apexo/features/appointments/appointments_store.dart';
import 'package:apexo/features/appointments/events_timeline_widget.dart';
import 'package:apexo/services/localization/locale.dart';
import 'package:apexo/services/login.dart';
import 'package:apexo/services/perm.dart';
import 'package:fluent_ui/fluent_ui.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pocketbase/pocketbase.dart';

import '../../../helpers/model_factory.dart';
import '../../../helpers/pump_app.dart';

void main() {
  late List<Appointment> previousAppointments;
  late List<RecordModel> previousAccounts;
  late List<int> previousPermissions;

  setUp(() {
    previousAppointments = appointments.docs.values.toList();
    previousAccounts = accounts.list();
    previousPermissions = login.savedPermissions;
    appointments.observableMap.clear();
    login.savedPermissions = Perm.full;
    accounts.list([
      RecordModel.fromJson({
        'id': 'op-1',
        'operate': 1,
        'name': 'Dr. One',
        'email': 'one@example.com',
      }),
      RecordModel.fromJson({
        'id': 'op-2',
        'operate': 1,
        'name': 'Dr. Two',
        'email': 'two@example.com',
      }),
    ]);
  });

  tearDown(() {
    appointmentSessions.clear();
    appointments.observableMap.clear();
    appointments.setAll(previousAppointments);
    accounts.list(previousAccounts);
    login.savedPermissions = previousPermissions;
  });

  bool checkedAt(WidgetTester tester, String name) {
    final row = find.ancestor(
      of: find.text(name),
      matching: find.byType(Row),
    );
    return tester
        .widget<Checkbox>(
            find.descendant(of: row.first, matching: find.byType(Checkbox)))
        .checked!;
  }

  testWidgets('a tick repaints the box and writes the stored visit',
      (tester) async {
    final visit = testAppointment(id: 'operators-stored');
    appointments.set(visit);
    await pumpApexoApp(
      tester,
      const Center(
        child: AppointmentOperatorsFlyout(appointmentId: 'operators-stored'),
      ),
    );

    expect(checkedAt(tester, 'Dr. One'), isFalse);
    await tester.tap(find.text('Dr. One'));
    await tester.pumpAndSettle();

    expect(checkedAt(tester, 'Dr. One'), isTrue,
        reason: 'the box says what the visit says, without reopening the list');
    expect(checkedAt(tester, 'Dr. Two'), isFalse);
    expect(appointments.get('operators-stored')!.operatorsIDs, ['op-1']);
  });

  testWidgets('a tick untick leaves the visit with no operator on it',
      (tester) async {
    final visit = testAppointment(
      id: 'operators-untick',
      operatorsIDs: const ['op-1'],
    );
    appointments.set(visit);
    await pumpApexoApp(
      tester,
      const Center(
        child: AppointmentOperatorsFlyout(appointmentId: 'operators-untick'),
      ),
    );

    expect(checkedAt(tester, 'Dr. One'), isTrue);
    await tester.tap(find.text('Dr. One'));
    await tester.pumpAndSettle();

    expect(checkedAt(tester, 'Dr. One'), isFalse);
    expect(appointments.get('operators-untick')!.operatorsIDs, isEmpty);
  });

  testWidgets('a tick reaches the open draft, not only the stored visit',
      (tester) async {
    final visit = testAppointment(id: 'operators-draft');
    appointments.set(visit);
    // An open visit: the band edits this draft, so the list must edit it too.
    final session =
        appointmentSessions.getOrCreate(appointments.get('operators-draft')!);
    await pumpApexoApp(
      tester,
      const Center(
        child: AppointmentOperatorsFlyout(appointmentId: 'operators-draft'),
      ),
    );

    await tester.tap(find.text('Dr. One'));
    await tester.pumpAndSettle();

    expect(session.item.operatorsIDs, ['op-1'],
        reason: 'the visit on screen takes the tick');
    expect(checkedAt(tester, 'Dr. One'), isTrue);
  });

  testWidgets('the timeline pill names the operator while the list is open',
      (tester) async {
    final visit = testAppointment(id: 'operators-pill');
    appointments.set(visit);
    await pumpApexoApp(
      tester,
      Center(
        child: SizedBox(
          width: 500,
          height: 80,
          child: TimelineChip(
            item: appointments.get('operators-pill')!,
            color: Colors.blue,
            showPayments: false,
            onTap: () {},
            onSelect: (_) {},
            onLongPressStart: (_) {},
            onLongPressMove: (_) {},
            onLongPressEnd: () {},
          ),
        ),
      ),
    );

    // The flyout draws in the overlay, so its rows are not inside the chip.
    Finder inChip(String text) => find.descendant(
          of: find.byType(TimelineChip),
          matching: find.text(text),
        );

    expect(inChip(txt('unassigned')), findsWidgets);
    await tester.tap(inChip(txt('unassigned')).first);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Dr. One'));
    await tester.pumpAndSettle();

    expect(inChip('Dr. One'), findsWidgets,
        reason: 'the pill behind the list names who is now on the visit');
    expect(inChip(txt('unassigned')), findsNothing);
    expect(appointments.get('operators-pill')!.operatorsIDs, ['op-1']);
  });
}
