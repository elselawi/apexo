import 'package:apexo/features/booking/booking_labels.dart';
import 'package:apexo/features/booking/booking_models.dart';
import 'package:apexo/features/booking/opening_hours_editor.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group("weekday display order", () {
    test("starts on Monday by default and for an unknown value", () {
      expect(bookingWeekdaysForDisplay("monday"), bookingWeekdays);
      expect(bookingWeekdaysForDisplay(""), bookingWeekdays);
      expect(bookingWeekdaysForDisplay("nonsense"), bookingWeekdays);
      // The setting is read from the app's own settings store.
      expect(bookingWeekdaysForDisplay(), bookingWeekdays);
    });

    test("rotates to the configured starting day without losing keys", () {
      expect(bookingWeekdaysForDisplay("sunday"), [
        "sun",
        "mon",
        "tue",
        "wed",
        "thu",
        "fri",
        "sat",
      ]);
      expect(bookingWeekdaysForDisplay("saturday"), [
        "sat",
        "sun",
        "mon",
        "tue",
        "wed",
        "thu",
        "fri",
      ]);
      expect(bookingWeekdaysForDisplay("thursday"), [
        "thu",
        "fri",
        "sat",
        "sun",
        "mon",
        "tue",
        "wed",
      ]);
      for (final start in [
        "monday",
        "tuesday",
        "wednesday",
        "thursday",
        "friday",
        "saturday",
        "sunday",
      ]) {
        final order = bookingWeekdaysForDisplay(start);
        expect(order.length, 7, reason: start);
        expect(order.toSet(), bookingWeekdays.toSet(), reason: start);
      }
    });

    test("keeps the label number attached to the day, not its position", () {
      expect(bookingWeekdayNumber("mon"), 1);
      expect(bookingWeekdayNumber("sun"), 7);
      final order = bookingWeekdaysForDisplay("sunday");
      expect(order.map(bookingWeekdayNumber).toList(), [7, 1, 2, 3, 4, 5, 6]);
    });

    test("the summary follows the same order as the editor", () {
      final hours = BookingWeeklyHours({
        ...BookingWeeklyHours.empty().days,
        "sat": [
          ["09:00", "12:00"],
        ],
      });
      // Saturday comes first when the week starts on Saturday.
      expect(
        bookingHoursSummary(hours, startDay: "saturday"),
        startsWith("Saturday 09:00–12:00"),
      );
    });
  });
}
