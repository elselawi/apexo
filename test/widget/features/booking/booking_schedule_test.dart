import 'dart:convert';

import 'package:apexo/features/booking/booking_api.dart';
import 'package:apexo/features/booking/booking_clinic_service.dart';
import 'package:apexo/features/booking/booking_schedule.dart';
import 'package:apexo/features/booking/booking_session.dart';
import 'package:apexo/services/localization/locale.dart';
import 'package:apexo/services/login.dart';
import 'package:apexo/services/perm.dart';
import 'package:fluent_ui/fluent_ui.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

import '../../../helpers/pump_app.dart';
import '../../../unit/features/booking/booking_requests_controller_test.dart'
    show clinic, item, page;

void main() {
  late List<int> originalPermissions;
  setUp(() {
    originalPermissions = login.savedPermissions;
    login.savedPermissions = Perm.full;
  });
  tearDown(() {
    booking.reset();
    login.savedPermissions = originalPermissions;
  });

  Future<void> open(WidgetTester tester, {required bool exists,
      bool unconfirmed = false}) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(1000, 900);
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final request = item('request000001');
    final api = BookingApi(origin: 'https://book.test', client: MockClient((_) async =>
      http.Response(jsonEncode(page(exists ? [request] : [])), 200,
        headers: {'content-type': 'application/json'})));
    booking.service = BookingClinicService(api: api);
    booking.clinic(clinic());
    booking.requests.attach(api: api, clinic: clinic(), accountId: 'account');
    booking.ready(true);
    if (unconfirmed) {
      expect(login.pb, isNull);
      booking.requests.rememberPendingLink(request, 'savedappointment', confirmed: false);
    }
    await pumpApexoApp(tester, Builder(builder: (context) => FilledButton(
      onPressed: () => scheduleBookingRequest(context, request),
      child: const Text('schedule'),
    )));
    await tester.tap(find.text('schedule'));
    await tester.pumpAndSettle();
  }

  testWidgets('a removed pending request never falls back to an old dialog copy', (tester) async {
    await open(tester, exists: false);
    expect(find.text(txt('bookingRequestGone')), findsOneWidget);
    expect(find.text(txt('bookingSchedulePatientTitle')), findsNothing);
    Navigator.of(tester.element(find.byType(ContentDialog))).pop();
    booking.reset();
    await tester.pumpAndSettle();
  });

  testWidgets('an unconfirmed saved visit cannot start another patient/appointment flow', (tester) async {
    await open(tester, exists: true, unconfirmed: true);
    expect(find.text(txt('bookingSaveNotConfirmed')), findsOneWidget);
    expect(find.text(txt('bookingSchedulePatientTitle')), findsNothing);
    expect(booking.requests.pendingLinks().single.appointmentId, 'savedappointment');
    Navigator.of(tester.element(find.byType(ContentDialog))).pop();
    booking.reset();
    await tester.pumpAndSettle();
  });
}
