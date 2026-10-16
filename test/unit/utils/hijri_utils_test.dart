import 'package:apexo/utils/hijri_utils.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('HijriUtils.fromGregorian', () {
    test('returns a HijriDate instance', () {
      final h = HijriUtils.fromGregorian(DateTime(2024, 7, 7));
      expect(h, isA<HijriDate>());
    });

    test('converts known date: 2024-07-07 → 1446/01/01 (Islamic New Year)', () {
      final h = HijriUtils.fromGregorian(DateTime(2024, 7, 7));
      expect(h.year, 1446);
      expect(h.month, 1);
      expect(h.day, 1);
    });

    test('converts known date: 2024-03-10 → 1445/09/01 (1 Ramadan 1445)', () {
      final h = HijriUtils.fromGregorian(DateTime(2024, 3, 10));
      expect(h.year, 1445);
      expect(h.month, 9);
      expect(h.day, 1);
    });
  });

  group('HijriUtils.toGregorian', () {
    test('returns a DateTime instance', () {
      final dt = HijriUtils.toGregorian(1446, 1, 1);
      expect(dt, isA<DateTime>());
    });

    test('converts known Hijri date: 1446/01/01 → 2024-07-07', () {
      final dt = HijriUtils.toGregorian(1446, 1, 1);
      expect(dt.year, 2024);
      expect(dt.month, 7);
      expect(dt.day, 7);
    });

    test('round-trip fromGregorian→toGregorian preserves date across years', () {
      final start = DateTime(2020, 1, 1);
      for (var offset = 0; offset < 2500; offset++) {
        final original = start.add(Duration(days: offset));
        final h = HijriUtils.fromGregorian(original);
        final back = HijriUtils.toGregorian(h.year, h.month, h.day);
        expect(back.year, original.year);
        expect(back.month, original.month);
        expect(back.day, original.day);
      }
    });
  });

  group('HijriUtils.monthName', () {
    test('returns Arabic name for valid month numbers', () {
      expect(HijriUtils.monthName(1), 'محرم');
      expect(HijriUtils.monthName(2), 'صفر');
      expect(HijriUtils.monthName(3), 'ربيع الأول');
      expect(HijriUtils.monthName(4), 'ربيع الثاني');
      expect(HijriUtils.monthName(5), 'جمادى الأولى');
      expect(HijriUtils.monthName(6), 'جمادى الآخرة');
      expect(HijriUtils.monthName(7), 'رجب');
      expect(HijriUtils.monthName(8), 'شعبان');
      expect(HijriUtils.monthName(9), 'رمضان');
      expect(HijriUtils.monthName(10), 'شوال');
      expect(HijriUtils.monthName(11), 'ذو القعدة');
      expect(HijriUtils.monthName(12), 'ذو الحجة');
    });

    test('returns empty string for out-of-range months', () {
      expect(HijriUtils.monthName(0), '');
      expect(HijriUtils.monthName(13), '');
      expect(HijriUtils.monthName(-1), '');
    });
  });

  group('HijriUtils.dayOfWeekName & dayOfWeekAbbr', () {
    test('returns Arabic name for each DateTime weekday', () {
      expect(HijriUtils.dayOfWeekName(DateTime.saturday), 'السبت');
      expect(HijriUtils.dayOfWeekName(DateTime.sunday), 'الأحد');
      expect(HijriUtils.dayOfWeekName(DateTime.monday), 'الإثنين');
      expect(HijriUtils.dayOfWeekName(DateTime.tuesday), 'الثلاثاء');
      expect(HijriUtils.dayOfWeekName(DateTime.wednesday), 'الأربعاء');
      expect(HijriUtils.dayOfWeekName(DateTime.thursday), 'الخميس');
      expect(HijriUtils.dayOfWeekName(DateTime.friday), 'الجمعة');
    });

    test('returns single-character abbreviation for each weekday', () {
      expect(HijriUtils.dayOfWeekAbbr(DateTime.saturday), 'س');
      expect(HijriUtils.dayOfWeekAbbr(DateTime.sunday), 'ح');
      expect(HijriUtils.dayOfWeekAbbr(DateTime.monday), 'ن');
      expect(HijriUtils.dayOfWeekAbbr(DateTime.tuesday), 'ث');
      expect(HijriUtils.dayOfWeekAbbr(DateTime.wednesday), 'ر');
      expect(HijriUtils.dayOfWeekAbbr(DateTime.thursday), 'خ');
      expect(HijriUtils.dayOfWeekAbbr(DateTime.friday), 'ج');
    });

    test('maps invalid weekdays through Monday fallback', () {
      expect(HijriUtils.dayOfWeekName(0), 'الإثنين');
      expect(HijriUtils.dayOfWeekName(8), 'الإثنين');
      expect(HijriUtils.dayOfWeekAbbr(0), 'ن');
    });
  });

  group('HijriUtils formatting', () {
    test('formatHijri formats default yyyy/MM/dd pattern', () {
      expect(HijriUtils.formatHijri(DateTime(2024, 7, 7)), '1446/01/01');
    });

    test('formatHijri supports MMMM and EE tokens', () {
      final s = HijriUtils.formatHijri(
        DateTime(2024, 7, 7),
        pattern: 'yyyy MMMM dd (EE)',
      );
      expect(s, '1446 محرم 01 (ح)');
    });

    test('formatHijriDMY, formatDay, and formatMonthYear', () {
      final dt = DateTime(2024, 7, 7);
      expect(HijriUtils.formatHijriDMY(dt), '1446/01/01');
      expect(HijriUtils.formatDay(dt), '1');
      expect(HijriUtils.formatMonthYear(dt), 'محرم 1446');
    });
  });

  group('HijriUtils.isLeapYear & daysInMonth', () {
    test('identifies leap and non-leap years in 30-year cycle', () {
      // 1442 % 30 = 2 (leap), 1445 % 30 = 5 (leap), 1446 % 30 = 6 (non-leap)
      expect(HijriUtils.isLeapYear(1442), isTrue);
      expect(HijriUtils.isLeapYear(1445), isTrue);
      expect(HijriUtils.isLeapYear(1446), isFalse);
    });

    test('returns 30 for odd months and 29 for even months 2..10', () {
      for (final m in [1, 3, 5, 7, 9, 11]) {
        expect(HijriUtils.daysInMonth(1446, m), 30);
      }
      for (final m in [2, 4, 6, 8, 10]) {
        expect(HijriUtils.daysInMonth(1446, m), 29);
      }
    });

    test('returns 30 for Dhu al-Hijjah (month 12) in leap year and 29 in common year', () {
      expect(HijriUtils.daysInMonth(1445, 12), 30);
      expect(HijriUtils.daysInMonth(1446, 12), 29);
    });
  });
}
