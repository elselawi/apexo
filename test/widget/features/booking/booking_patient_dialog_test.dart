import 'package:apexo/features/booking/booking_models.dart';
import 'package:apexo/features/booking/booking_schedule.dart';
import 'package:apexo/features/patients/patients_store.dart';
import 'package:apexo/services/localization/locale.dart';
import 'package:fluent_ui/fluent_ui.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../../helpers/model_factory.dart';
import '../../../helpers/pump_app.dart';

BookingRequest request({String phone = "+9647518096323"}) => BookingRequest(
      seq: 1,
      requestId: "r1",
      reference: "1106-01",
      name: "Amina Hassan",
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
      createdAt: DateTime.now().millisecondsSinceEpoch,
      expiresAt:
          DateTime.now().add(const Duration(days: 30)).millisecondsSinceEpoch,
      version: 1,
      status: "pending",
    );

FilledButton continueButton(WidgetTester tester) => tester.widget<FilledButton>(
      find
          .ancestor(
            of: find.text(txt("bookingContinue")).first,
            matching: find.byType(FilledButton),
          )
          .first,
    );

void main() {
  late List<dynamic> originalPatients;

  setUp(() {
    originalPatients = patients.docs.values.toList();
    patients.observableMap.clear();
    patients.set(testPatient(
      id: "known",
      name: "Amina H.",
      phone: "+9647518096323",
    ));
    patients.set(testPatient(
      id: "other",
      name: "Unrelated Person",
      phone: "+9647700000000",
    ));
  });

  tearDown(() {
    patients.observableMap.clear();
    patients.setAll(originalPatients.cast());
  });

  /// Opens the patient step and returns once the dialog is on screen.
  Future<void> open(WidgetTester tester) async {
    await pumpApexoApp(
      tester,
      Builder(
        builder: (context) => FilledButton(
          onPressed: () => chooseBookingPatient(context, request()),
          child: const Text("open"),
        ),
      ),
    );
    await tester.tap(find.text("open"));
    await tester.pumpAndSettle();
  }

  testWidgets("offers the patient with the matching number", (tester) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(900, 900);
    // The test font is wider than real glyphs, so scale down to fit the row.
    tester.platformDispatcher.textScaleFactorTestValue = 0.7;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
    await open(tester);

    expect(find.text(txt("bookingSuggestedPatient")), findsOneWidget);
    expect(find.text("Amina H."), findsOneWidget);
    expect(find.text("Unrelated Person"), findsNothing);
  });

  testWidgets("keeps Continue disabled until a patient is chosen",
      (tester) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(900, 900);
    // The test font is wider than real glyphs, so scale down to fit the row.
    tester.platformDispatcher.textScaleFactorTestValue = 0.7;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
    await open(tester);

    expect(continueButton(tester).onPressed, isNull);

    await tester.tap(find.text("Amina H."));
    await tester.pumpAndSettle();
    expect(continueButton(tester).onPressed, isNotNull);

    await tester.tap(find.text(txt("bookingContinue")).first);
    await tester.pumpAndSettle();
    expect(find.text(txt("bookingSchedulePatientTitle")), findsNothing);
  });

  testWidgets("never preselects a suggested patient", (tester) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(900, 900);
    // The test font is wider than real glyphs, so scale down to fit the row.
    tester.platformDispatcher.textScaleFactorTestValue = 0.7;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
    await open(tester);

    // The suggestion is visible, but the answer stays empty.
    expect(find.text("Amina H."), findsOneWidget);
    expect(continueButton(tester).onPressed, isNull);
  });
}
