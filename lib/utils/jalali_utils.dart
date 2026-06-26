import 'package:shamsi_date/shamsi_date.dart';

/// Utility class for converting between Gregorian and Jalali (Persian/Shamsi) dates.
class JalaliUtils {
  /// Convert a DateTime (Gregorian) to Jalali
  static Jalali fromGregorian(DateTime date) {
    return Jalali.fromDateTime(date);
  }

  /// Convert a Jalali date to DateTime (Gregorian)
  static DateTime toGregorian(int year, int month, int day) {
    return Jalali(year, month, day).toDateTime();
  }

  /// Get Jalali month name in Persian
  static String monthName(int month) {
    const names = [
      'فروردین',
      'اردیبهشت',
      'خرداد',
      'تیر',
      'مرداد',
      'شهریور',
      'مهر',
      'آبان',
      'آذر',
      'دی',
      'بهمن',
      'اسفند',
    ];
    if (month < 1 || month > 12) return '';
    return names[month - 1];
  }

  /// Get Jalali day of week name in Persian
  static String dayOfWeekName(int weekday) {
    // In shamsi_date, weekdays are: Saturday=0, Sunday=1, ..., Friday=6
    // In DateTime, weekdays are: Monday=1, ..., Sunday=7
    // Convert DateTime.weekday to shamsi weekday
    // DateTime Monday(1) -> shamsi Sunday(1)? No.
    // DateTime: Mon=1, Tue=2, Wed=3, Thu=4, Fri=5, Sat=6, Sun=7
    // shamsi:   Sat=0, Sun=1, Mon=2, Tue=3, Wed=4, Thu=5, Fri=6
    const names = [
      'شنبه',
      'یک\u200cشنبه',
      'دوشنبه',
      'سه\u200cشنبه',
      'چهارشنبه',
      'پنج\u200cشنبه',
      'جمعه',
    ];
    // Convert DateTime weekday (Mon=1..Sun=7) to shamsi weekday (Sat=0..Fri=6)
    // DateTime Mon(1) -> shamsi Mon(2)
    // DateTime Sun(7) -> shamsi Sun(1)
    int shamsiWeekday;
    switch (weekday) {
      case DateTime.monday: // 1
        shamsiWeekday = 2;
        break;
      case DateTime.tuesday: // 2
        shamsiWeekday = 3;
        break;
      case DateTime.wednesday: // 3
        shamsiWeekday = 4;
        break;
      case DateTime.thursday: // 4
        shamsiWeekday = 5;
        break;
      case DateTime.friday: // 5
        shamsiWeekday = 6;
        break;
      case DateTime.saturday: // 6
        shamsiWeekday = 0;
        break;
      case DateTime.sunday: // 7
        shamsiWeekday = 1;
        break;
      default:
        shamsiWeekday = 2;
    }
    return names[shamsiWeekday];
  }

  /// Short day-of-week abbreviation (single Persian character)
  static String dayOfWeekAbbr(int weekday) {
    const abbrs = ['ش', 'ی', 'د', 'س', 'چ', 'پ', 'ج'];
    int shamsiWeekday;
    switch (weekday) {
      case DateTime.monday:
        shamsiWeekday = 2;
        break;
      case DateTime.tuesday:
        shamsiWeekday = 3;
        break;
      case DateTime.wednesday:
        shamsiWeekday = 4;
        break;
      case DateTime.thursday:
        shamsiWeekday = 5;
        break;
      case DateTime.friday:
        shamsiWeekday = 6;
        break;
      case DateTime.saturday:
        shamsiWeekday = 0;
        break;
      case DateTime.sunday:
        shamsiWeekday = 1;
        break;
      default:
        shamsiWeekday = 2;
    }
    return abbrs[shamsiWeekday];
  }

  /// Format a DateTime as Jalali date string
  /// e.g., "۱۴۰۳/۰۳/۱۵" or "۱۵ خرداد ۱۴۰۳"
  static String formatJalali(DateTime date, {String pattern = 'yyyy/MM/dd'}) {
    final j = Jalali.fromDateTime(date);
    // Replace longer patterns first to avoid partial matches
    return pattern
        .replaceAll('MMMM', monthName(j.month))
        .replaceAll('EE', dayOfWeekAbbr(date.weekday))
        .replaceAll('yyyy', j.year.toString())
        .replaceAll('MM', j.month.toString().padLeft(2, '0'))
        .replaceAll('dd', j.day.toString().padLeft(2, '0'));
  }

  /// Check if given Jalali year is a leap year
  static bool isLeapYear(int year) {
    return Jalali(year).isLeapYear();
  }

  /// Get number of days in a Jalali month
  static int daysInMonth(int year, int month) {
    return Jalali(year, month, 1).monthLength;
  }

  /// Get today's Jalali date
  static Jalali today() {
    return Jalali.now();
  }

  /// Format day number only as Jalali
  static String formatDay(DateTime date) {
    final j = Jalali.fromDateTime(date);
    return j.day.toString();
  }

  /// Format month/year as Jalali (e.g. "خرداد ۱۴۰۳" or "Mehr 1403")
  static String formatMonthYear(DateTime date) {
    final j = Jalali.fromDateTime(date);
    return '${monthName(j.month)} ${j.year}';
  }

  /// Format day/month/year as Jalali (Persian numerals optional)
  static String formatJalaliDMY(DateTime date) {
    final j = Jalali.fromDateTime(date);
    return '${j.year}/${j.month.toString().padLeft(2, '0')}/${j.day.toString().padLeft(2, '0')}';
  }
}
