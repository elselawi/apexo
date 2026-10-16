/// Represents a date in the Hijri (Islamic) calendar.
class HijriDate {
  const HijriDate(this.year, this.month, this.day);

  /// Converts a Gregorian [DateTime] to a [HijriDate] using the standard
  /// Civil (Kuwaiti / Tabular Islamic) arithmetic algorithm.
  factory HijriDate.fromDateTime(DateTime date) {
    final jd = _gregorianToJulianDay(date.year, date.month, date.day);
    return _julianDayToHijri(jd);
  }

  /// Current local date in the Hijri calendar.
  factory HijriDate.now() => HijriDate.fromDateTime(DateTime.now());

  final int year;
  final int month;
  final int day;

  /// Converts this [HijriDate] to a Gregorian [DateTime].
  DateTime toDateTime() {
    final jd = _hijriToJulianDay(year, month, day);
    return _julianDayToGregorian(jd);
  }

  /// Whether this Hijri year is a leap year in the 30-year cycle
  /// (years 2, 5, 7, 10, 13, 16, 18, 21, 24, 26, 29).
  bool isLeapYear() => HijriUtils.isLeapYear(year);

  /// Number of days in this Hijri month (29 or 30).
  int get monthLength => HijriUtils.daysInMonth(year, month);

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is HijriDate &&
          other.year == year &&
          other.month == month &&
          other.day == day;

  @override
  int get hashCode => Object.hash(year, month, day);

  @override
  String toString() =>
      '$year/${month.toString().padLeft(2, '0')}/${day.toString().padLeft(2, '0')}';
}

const int _islamicEpoch = 1948438;
const List<int> _leapYearsInCycle = [2, 5, 7, 10, 13, 16, 18, 21, 24, 26, 29];

int _gregorianToJulianDay(int year, int month, int day) {
  final a = (14 - month) ~/ 12;
  final y = year + 4800 - a;
  final m = month + 12 * a - 3;
  return day +
      ((153 * m + 2) ~/ 5) +
      365 * y +
      (y ~/ 4) -
      (y ~/ 100) +
      (y ~/ 400) -
      32045;
}

DateTime _julianDayToGregorian(int jd) {
  final l1 = jd + 68569;
  final n = (4 * l1) ~/ 146097;
  final l2 = l1 - ((146097 * n + 3) ~/ 4);
  final i = (4000 * (l2 + 1)) ~/ 1461001;
  final l3 = l2 - ((1461 * i) ~/ 4) + 31;
  final j = (80 * l3) ~/ 2447;
  final day = l3 - ((2447 * j) ~/ 80);
  final l4 = j ~/ 11;
  final month = j + 2 - 12 * l4;
  final year = 100 * (n - 49) + i + l4;
  return DateTime(year, month, day);
}

int _hijriToJulianDay(int year, int month, int day) {
  return day +
      ((29.5 * (month - 1) + 0.5).floor()) +
      (year - 1) * 354 +
      ((3 + 11 * year) ~/ 30) +
      _islamicEpoch;
}

HijriDate _julianDayToHijri(int jd) {
  var year = ((30 * (jd - _islamicEpoch) + 10646) ~/ 10631);
  if (_hijriToJulianDay(year, 1, 1) > jd) {
    year--;
  } else if (_hijriToJulianDay(year + 1, 1, 1) <= jd) {
    year++;
  }
  final firstOfYear = _hijriToJulianDay(year, 1, 1);
  var month = (((jd - 29 - firstOfYear) / 29.5).ceil() + 1);
  if (month < 1) month = 1;
  if (month > 12) month = 12;
  if (_hijriToJulianDay(year, month, 1) > jd && month > 1) {
    month--;
  } else if (month < 12 && _hijriToJulianDay(year, month + 1, 1) <= jd) {
    month++;
  }
  final day = jd - _hijriToJulianDay(year, month, 1) + 1;
  return HijriDate(year, month, day);
}

/// Utility class for converting between Gregorian and Hijri (Islamic) dates.
class HijriUtils {
  /// Convert a DateTime (Gregorian) to HijriDate
  static HijriDate fromGregorian(DateTime date) {
    return HijriDate.fromDateTime(date);
  }

  /// Convert a Hijri date to DateTime (Gregorian)
  static DateTime toGregorian(int year, int month, int day) {
    return HijriDate(year, month, day).toDateTime();
  }

  /// Get Hijri month name in Arabic
  static String monthName(int month) {
    const names = [
      'محرم',
      'صفر',
      'ربيع الأول',
      'ربيع الثاني',
      'جمادى الأولى',
      'جمادى الآخرة',
      'رجب',
      'شعبان',
      'رمضان',
      'شوال',
      'ذو القعدة',
      'ذو الحجة',
    ];
    if (month < 1 || month > 12) return '';
    return names[month - 1];
  }

  /// Get Hijri day of week name in Arabic
  static String dayOfWeekName(int weekday) {
    const names = [
      'السبت',
      'الأحد',
      'الإثنين',
      'الثلاثاء',
      'الأربعاء',
      'الخميس',
      'الجمعة',
    ];
    return names[_arabicWeekdayIndex(weekday)];
  }

  /// Short day-of-week abbreviation (single Arabic character)
  static String dayOfWeekAbbr(int weekday) {
    const abbrs = ['س', 'ح', 'ن', 'ث', 'ر', 'خ', 'ج'];
    return abbrs[_arabicWeekdayIndex(weekday)];
  }

  static int _arabicWeekdayIndex(int weekday) {
    switch (weekday) {
      case DateTime.monday:
        return 2;
      case DateTime.tuesday:
        return 3;
      case DateTime.wednesday:
        return 4;
      case DateTime.thursday:
        return 5;
      case DateTime.friday:
        return 6;
      case DateTime.saturday:
        return 0;
      case DateTime.sunday:
        return 1;
      default:
        return 2;
    }
  }

  /// Format a DateTime as Hijri date string
  static String formatHijri(DateTime date, {String pattern = 'yyyy/MM/dd'}) {
    final h = HijriDate.fromDateTime(date);
    return pattern
        .replaceAll('MMMM', monthName(h.month))
        .replaceAll('EE', dayOfWeekAbbr(date.weekday))
        .replaceAll('yyyy', h.year.toString())
        .replaceAll('MM', h.month.toString().padLeft(2, '0'))
        .replaceAll('dd', h.day.toString().padLeft(2, '0'));
  }

  /// Check if given Hijri year is a leap year
  static bool isLeapYear(int year) {
    final mod = ((year % 30) + 30) % 30;
    return _leapYearsInCycle.contains(mod == 0 ? 30 : mod);
  }

  /// Get number of days in a Hijri month
  static int daysInMonth(int year, int month) {
    if (month < 1 || month > 12) return 0;
    if (month.isOdd) return 30;
    if (month == 12 && isLeapYear(year)) return 30;
    return 29;
  }

  /// Get today's Hijri date
  static HijriDate today() {
    return HijriDate.now();
  }

  /// Format day number only as Hijri
  static String formatDay(DateTime date) {
    final h = HijriDate.fromDateTime(date);
    return h.day.toString();
  }

  /// Format month/year as Hijri (e.g. "رمضان 1445")
  static String formatMonthYear(DateTime date) {
    final h = HijriDate.fromDateTime(date);
    return '${monthName(h.month)} ${h.year}';
  }

  /// Format year/month/day as Hijri
  static String formatHijriDMY(DateTime date) {
    final h = HijriDate.fromDateTime(date);
    return '${h.year}/${h.month.toString().padLeft(2, '0')}/${h.day.toString().padLeft(2, '0')}';
  }
}
