import 'package:apexo/common_widgets/appointment_card.dart';
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
