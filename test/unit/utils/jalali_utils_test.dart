import 'package:apexo/utils/jalali_utils.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shamsi_date/shamsi_date.dart';

void main() {
  group('JalaliUtils.fromGregorian', () {
    test('returns a Jalali instance', () {
      final j = JalaliUtils.fromGregorian(DateTime(2024, 3, 20));
      expect(j, isA<Jalali>());
    });

    test('converts known date: 2024-03-20 → 1403/01/01 (Nowruz)', () {
      final j = JalaliUtils.fromGregorian(DateTime(2024, 3, 20));
      expect(j.year, 1403);
      expect(j.month, 1);
      expect(j.day, 1);
    });

    test('converts known date: 2024-01-01 → 1402/10/11', () {
      final j = JalaliUtils.fromGregorian(DateTime(2024, 1, 1));
      expect(j.year, 1402);
      expect(j.month, 10);
      expect(j.day, 11);
    });
  });

  group('JalaliUtils.toGregorian', () {
    test('returns a DateTime instance', () {
      final dt = JalaliUtils.toGregorian(1403, 1, 1);
      expect(dt, isA<DateTime>());
    });

    test('converts known Jalali date: 1403/01/01 → 2024-03-20', () {
      final dt = JalaliUtils.toGregorian(1403, 1, 1);
      expect(dt.year, 2024);
      expect(dt.month, 3);
      expect(dt.day, 20);
    });

    test('round-trip fromGregorian→toGregorian preserves date', () {
      final original = DateTime(2024, 6, 15);
      final j = JalaliUtils.fromGregorian(original);
      final back = JalaliUtils.toGregorian(j.year, j.month, j.day);
      expect(back.year, original.year);
      expect(back.month, original.month);
      expect(back.day, original.day);
    });
  });

  group('JalaliUtils.monthName', () {
    test('returns Persian name for valid month numbers', () {
      expect(JalaliUtils.monthName(1), 'فروردین');
      expect(JalaliUtils.monthName(2), 'اردیبهشت');
      expect(JalaliUtils.monthName(3), 'خرداد');
      expect(JalaliUtils.monthName(4), 'تیر');
      expect(JalaliUtils.monthName(5), 'مرداد');
      expect(JalaliUtils.monthName(6), 'شهریور');
      expect(JalaliUtils.monthName(7), 'مهر');
      expect(JalaliUtils.monthName(8), 'آبان');
      expect(JalaliUtils.monthName(9), 'آذر');
      expect(JalaliUtils.monthName(10), 'دی');
      expect(JalaliUtils.monthName(11), 'بهمن');
      expect(JalaliUtils.monthName(12), 'اسفند');
    });

    test('returns empty string for out-of-range month 0', () {
      expect(JalaliUtils.monthName(0), '');
    });

    test('returns empty string for out-of-range month 13', () {
      expect(JalaliUtils.monthName(13), '');
    });

    test('returns empty string for negative month', () {
      expect(JalaliUtils.monthName(-1), '');
    });
  });

  group('JalaliUtils.dayOfWeekName', () {
    test('returns Persian name for each DateTime weekday', () {
      expect(JalaliUtils.dayOfWeekName(DateTime.monday), 'دوشنبه');
      expect(JalaliUtils.dayOfWeekName(DateTime.tuesday), 'سه\u200cشنبه');
      expect(JalaliUtils.dayOfWeekName(DateTime.wednesday), 'چهارشنبه');
      expect(JalaliUtils.dayOfWeekName(DateTime.thursday), 'پنج\u200cشنبه');
      expect(JalaliUtils.dayOfWeekName(DateTime.friday), 'جمعه');
      expect(JalaliUtils.dayOfWeekName(DateTime.saturday), 'شنبه');
      expect(JalaliUtils.dayOfWeekName(DateTime.sunday), 'یک\u200cشنبه');
    });

    test('returns a non-empty string for any weekday', () {
      for (var w = 1; w <= 7; w++) {
        expect(JalaliUtils.dayOfWeekName(w), isNotEmpty);
      }
    });

    test('maps invalid weekdays through the documented Monday fallback', () {
      expect(JalaliUtils.dayOfWeekName(0), 'دوشنبه');
      expect(JalaliUtils.dayOfWeekName(-1), 'دوشنبه');
      expect(JalaliUtils.dayOfWeekName(8), 'دوشنبه');
      expect(JalaliUtils.dayOfWeekAbbr(0), 'د');
    });
  });

  group('JalaliUtils.dayOfWeekAbbr', () {
    test('returns a single-character abbreviation', () {
      // shamsi order: Sat=0 ('ش'), Sun=1 ('ی'), Mon=2 ('د'), ...
      expect(JalaliUtils.dayOfWeekAbbr(DateTime.saturday), 'ش');
      expect(JalaliUtils.dayOfWeekAbbr(DateTime.sunday), 'ی');
      expect(JalaliUtils.dayOfWeekAbbr(DateTime.monday), 'د');
      expect(JalaliUtils.dayOfWeekAbbr(DateTime.tuesday), 'س');
      expect(JalaliUtils.dayOfWeekAbbr(DateTime.wednesday), 'چ');
      expect(JalaliUtils.dayOfWeekAbbr(DateTime.thursday), 'پ');
      expect(JalaliUtils.dayOfWeekAbbr(DateTime.friday), 'ج');
    });
  });

  group('JalaliUtils.formatJalali', () {
    test('formats default yyyy/MM/dd pattern', () {
      final s = JalaliUtils.formatJalali(DateTime(2024, 3, 20));
      expect(s, '1403/01/01');
    });

    test('formats custom pattern with MM and dd', () {
      final s = JalaliUtils.formatJalali(DateTime(2024, 6, 15),
          pattern: 'yyyy-MM-dd');
      final j = JalaliUtils.fromGregorian(DateTime(2024, 6, 15));
      expect(s,
          '${j.year}-${j.month.toString().padLeft(2, '0')}-${j.day.toString().padLeft(2, '0')}');
    });

    test('supports MMMM pattern with month name', () {
      final s =
          JalaliUtils.formatJalali(DateTime(2024, 3, 20), pattern: 'MMMM');
      expect(s, 'فروردین');
    });

    test('supports EE pattern with weekday abbreviation', () {
      final s = JalaliUtils.formatJalali(DateTime(2024, 3, 20), pattern: 'EE');
      expect(s, isNotEmpty);
      // Wednesday March 20 2024 → abb (Thu in shamsi) = 'پ'
      final wednesdayAbbr =
          JalaliUtils.dayOfWeekAbbr(DateTime(2024, 3, 20).weekday);
      expect(s, wednesdayAbbr);
    });

    test('replaces longer tokens before shorter token-like sequences', () {
      final s = JalaliUtils.formatJalali(DateTime(2024, 3, 20),
          pattern: 'yyyy MMMM dd (EE)');
      expect(s, '1403 فروردین 01 (چ)');
    });
  });

  group('JalaliUtils.formatJalaliDMY', () {
    test('returns YYYY/MM/DD format with zero-padded month/day', () {
      final s = JalaliUtils.formatJalaliDMY(DateTime(2024, 3, 20));
      expect(s, '1403/01/01');
    });

    test('round-trips via fromGregorian', () {
      final dt = DateTime(2024, 8, 22);
      final j = JalaliUtils.fromGregorian(dt);
      final s = JalaliUtils.formatJalaliDMY(dt);
      expect(s,
          '${j.year}/${j.month.toString().padLeft(2, '0')}/${j.day.toString().padLeft(2, '0')}');
    });
  });

  group('JalaliUtils.formatDay / formatMonthYear', () {
    test('formatDay returns the day number as string', () {
      final s = JalaliUtils.formatDay(DateTime(2024, 3, 20));
      expect(s, '1');
    });

    test('formatMonthYear returns <monthName> <year>', () {
      final s = JalaliUtils.formatMonthYear(DateTime(2024, 3, 20));
      expect(s, 'فروردین 1403');
    });
  });

  group('JalaliUtils.isLeapYear', () {
    test('identifies known leap and non-leap Jalali years', () {
      expect(JalaliUtils.isLeapYear(1403), isTrue);
      expect(JalaliUtils.isLeapYear(1402), isFalse);
    });
  });

  group('JalaliUtils.daysInMonth', () {
    test('returns 31 for first 6 months', () {
      expect(JalaliUtils.daysInMonth(1403, 1), 31);
      expect(JalaliUtils.daysInMonth(1403, 2), 31);
      expect(JalaliUtils.daysInMonth(1403, 3), 31);
      expect(JalaliUtils.daysInMonth(1403, 4), 31);
      expect(JalaliUtils.daysInMonth(1403, 5), 31);
      expect(JalaliUtils.daysInMonth(1403, 6), 31);
    });

    test('returns 30 for months 7-11', () {
      expect(JalaliUtils.daysInMonth(1403, 7), 30);
      expect(JalaliUtils.daysInMonth(1403, 8), 30);
      expect(JalaliUtils.daysInMonth(1403, 9), 30);
      expect(JalaliUtils.daysInMonth(1403, 10), 30);
      expect(JalaliUtils.daysInMonth(1403, 11), 30);
    });

    test('returns 30 in a leap year for Esfand (month 12)', () {
      // 1403 is leap — so Esfand has 30 days
      expect(JalaliUtils.daysInMonth(1403, 12), 30);
    });

    test('returns 29 in a non-leap year for Esfand (month 12)', () {
      // 1402 is not leap — Esfand has 29 days
      expect(JalaliUtils.daysInMonth(1402, 12), 29);
    });
  });

  group('JalaliUtils.today', () {
    test('returns a Jalali representing today', () {
      final t = JalaliUtils.today();
      expect(t, isA<Jalali>());
      // Should be approximately now
      expect(t.year, greaterThan(1400));
    });
  });
}
