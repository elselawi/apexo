@Tags(['serial'])
library;

import 'package:apexo/features/booking/booking_models.dart';
import 'package:apexo/features/booking/booking_requests_screen.dart';
import 'package:apexo/features/booking/booking_session.dart';
import 'package:apexo/services/localization/locale.dart';
import 'package:fluent_ui/fluent_ui.dart';
import 'package:flutter/cupertino.dart' show CupertinoTextField;
import 'package:flutter_test/flutter_test.dart';

import '../../../helpers/pump_app.dart';

BookingRequest request({
  String id = "r1",
  String name = "Amina Hassan",
  String phone = "+9647518096323",
  String status = "pending",
  String reference = "1106-01",
}) {
  final now = DateTime.now().millisecondsSinceEpoch;
  return BookingRequest(
    seq: 1,
    requestId: id,
    reference: reference,
    name: name,
    phone: phone,
    preference: BookingPreference(
      kind: "exact",
      date: "2026-11-10",
      from: "09:00",
      to: "12:00",
    ),
    candidateDates: const [],
    configRevision: 1,
    fromDate: "2026-11-10",
    toDate: "2026-11-10",
    windowFrom: "09:00",
    windowTo: "12:00",
    timeZone: "Asia/Baghdad",
    language: "en",
    createdAt: now,
    expiresAt: now + const Duration(days: 30).inMilliseconds,
    version: 1,
    status: status,
  );
}

void main() {
  setUp(() {
    booking.ready(true);
    booking.clinic(BookingClinicRecord(
      handle: "clinic",
      clinicId: "0" * 32,
      publicUrl: "https://book.test/clinic",
      inboxKey: "k" * 43,
      keyRevision: 1,
    ));
    booking.requests.filter("pending");
    booking.requests.items([request(), request(id: "r2", name: "Omar Saleh")]);
    booking.requests.pending(2);
    booking.requests.refreshing(false);
    booking.requests.connected(true);
    booking.requests.revoked(false);
    booking.requests.stale(false);
    booking.requests.lastSuccessfulAt(null);
  });

  tearDown(() {
    booking.reset();
    booking.requests.items(const []);
    booking.requests.pending(0);
  });

  Future<void> size(WidgetTester tester, Size value) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = value;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpAndSettle();
  }

  testWidgets("renders the inbox table with one row per request",
      (tester) async {
    await size(tester, const Size(1400, 900));
    await pumpApexoApp(tester, const BookingRequestsScreen());

    expect(find.text(txt("refresh")), findsWidgets);
    expect(find.text("2 ${txt("bookingPendingCount")}"), findsWidgets);
    expect(find.text("Amina Hassan"), findsOneWidget);
    expect(find.text("Omar Saleh"), findsOneWidget);
    // Column captions, as on the patients table.
    expect(find.text(txt("phone")), findsWidgets);
    expect(find.text(txt("bookingPreference")), findsWidgets);
    expect(find.text(txt("bookingSubmitted")), findsWidgets);
    expect(find.text("+9647518096323"), findsWidgets);
    expect(tester.takeException(), isNull);
  });

  testWidgets("fits a phone-width screen without overflowing", (tester) async {
    await size(tester, const Size(360, 720));
    await pumpApexoApp(tester, const BookingRequestsScreen());

    expect(find.text("Amina Hassan"), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets("points its row chevron along the reading order", (tester) async {
    await size(tester, const Size(1200, 800));
    await pumpApexoApp(tester, const BookingRequestsScreen());
    expect(find.byIcon(WindowsIcons.chevron_right), findsWidgets);
    expect(find.byIcon(WindowsIcons.chevron_left), findsNothing);

    await tester.pumpWidget(const SizedBox());
    await pumpApexoApp(tester, const BookingRequestsScreen(),
        direction: TextDirection.rtl);
    expect(find.byIcon(WindowsIcons.chevron_left), findsWidgets);
    expect(find.byIcon(WindowsIcons.chevron_right), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets("pins the row actions to the end at every width", (tester) async {
    booking.requests.items([
      request(name: "Al"),
      request(id: "r2", name: "Omar Saleh"),
    ]);
    // Wide (full table) and phone (compact) layouts must both end at the
    // tile edge instead of leaving slack after the chevron.
    for (final width in [1400.0, 360.0]) {
      await tester.pumpWidget(const SizedBox());
      await size(tester, Size(width, 800));
      await pumpApexoApp(tester, const BookingRequestsScreen());

      final rows = find.byType(ListTile);
      expect(rows, findsNWidgets(2));
      for (var index = 0; index < 2; index++) {
        final tile = tester.getRect(rows.at(index));
        final chevron = tester.getRect(
          find.descendant(
            of: rows.at(index),
            matching: find.byIcon(WindowsIcons.chevron_right),
          ),
        );
        expect(chevron.right, moreOrLessEquals(tile.right - 10, epsilon: 0.5));
      }
      expect(tester.takeException(), isNull);
    }
  });

  testWidgets("gives the patient name a fixed width and ellipsizes it",
      (tester) async {
    const longName = "Abdulrahman Mohammed Al-Samarrai";
    booking.requests.items([
      request(name: "Al"),
      request(id: "r2", name: longName),
    ]);
    await size(tester, const Size(1400, 900));
    await pumpApexoApp(tester, const BookingRequestsScreen());

    expect(tester.getSize(find.text("Al")).width, 190);
    expect(tester.getSize(find.text(longName)).width, 190);
    final label = tester.widget<Text>(find.text(longName));
    expect(label.maxLines, 1);
    expect(label.overflow, TextOverflow.ellipsis);
    expect(tester.takeException(), isNull);
  });

  testWidgets("shows the empty state when nothing matches the filter",
      (tester) async {
    booking.requests.items(const []);
    await size(tester, const Size(1000, 800));
    await pumpApexoApp(tester, const BookingRequestsScreen());

    expect(find.text(txt("noResultsFound")), findsWidgets);
    expect(tester.takeException(), isNull);
  });

  testWidgets("finds a request by the reference the patient was given",
      (tester) async {
    booking.requests.items([
      request(reference: "1106-01"),
      request(id: "r2", name: "Omar Saleh", reference: "1106-02"),
    ]);
    await size(tester, const Size(1000, 800));
    await pumpApexoApp(tester, const BookingRequestsScreen());

    await tester.enterText(find.byType(CupertinoTextField).first, "1106-02");
    await tester.pumpAndSettle();
    expect(find.text("Omar Saleh"), findsOneWidget);
    expect(find.text("Amina Hassan"), findsNothing);

    // Typed without the dash, the way a patient would say it.
    await tester.enterText(find.byType(CupertinoTextField).first, "110601");
    await tester.pumpAndSettle();
    expect(find.text("Amina Hassan"), findsOneWidget);
    expect(find.text("Omar Saleh"), findsNothing);
  });

  testWidgets("warns when the inbox is disconnected", (tester) async {
    booking.requests.connected(false);
    await size(tester, const Size(1000, 800));
    await pumpApexoApp(tester, const BookingRequestsScreen());

    expect(find.text(txt("bookingDisconnected")), findsWidgets);
  });
}
