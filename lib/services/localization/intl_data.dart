// `intl` ships no `ku` data and silently falls back to `en_US`.

import "package:intl/date_symbol_data_custom.dart";
import "package:intl/date_symbols.dart";
import "package:intl/date_time_patterns.dart";
import "package:intl/number_symbols.dart";
import "package:intl/number_symbols_data.dart";

bool _registered = false;

/// Registers number and date symbols for locales `intl` does not ship.
///
/// Safe to call repeatedly.
void ensureCustomIntlLocalesInitialized() {
  if (_registered) return;
  _registered = true;

  _registerKu();
}

void _registerKu() {
  numberFormatSymbols["ku"] = const NumberSymbols(
    NAME: "ku",
    DECIMAL_SEP: ".",
    GROUP_SEP: ",",
    PERCENT: "%",
    ZERO_DIGIT: "0",
    PLUS_SIGN: "+",
    MINUS_SIGN: "-",
    EXP_SYMBOL: "E",
    PERMILL: "\u2030",
    INFINITY: "\u221E",
    NAN: "NaN",
    DECIMAL_PATTERN: "#,##0.###",
    SCIENTIFIC_PATTERN: "#E0",
    PERCENT_PATTERN: "#,##0%",
    CURRENCY_PATTERN: "\u00A4#,##0.00",
    DEF_CURRENCY_CODE: "IQD",
  );

  initializeDateFormattingCustom(
    locale: "ku",
    symbols: DateSymbols(
      NAME: "ku",
      ERAS: const ["پ.ز", "ز"],
      ERANAMES: const ["پێش زایین", "زایینی"],
      NARROWMONTHS: const [
        "ک٢",
        "ش",
        "ئ",
        "ن",
        "ئ",
        "ح",
        "ت",
        "ئ",
        "ئ",
        "ت١",
        "ت٢",
        "ک١"
      ],
      STANDALONENARROWMONTHS: const [
        "ک٢",
        "ش",
        "ئ",
        "ن",
        "ئ",
        "ح",
        "ت",
        "ئ",
        "ئ",
        "ت١",
        "ت٢",
        "ک١"
      ],
      MONTHS: const [
        "کانوونی دووەم",
        "شوبات",
        "ئازار",
        "نیسان",
        "ئایار",
        "حوزەیران",
        "تەممووز",
        "ئاب",
        "ئەیلوول",
        "تشرینی یەکەم",
        "تشرینی دووەم",
        "کانوونی یەکەم"
      ],
      STANDALONEMONTHS: const [
        "کانوونی دووەم",
        "شوبات",
        "ئازار",
        "نیسان",
        "ئایار",
        "حوزەیران",
        "تەممووز",
        "ئاب",
        "ئەیلوول",
        "تشرینی یەکەم",
        "تشرینی دووەم",
        "کانوونی یەکەم"
      ],
      SHORTMONTHS: const [
        "کانوونی دووەم",
        "شوبات",
        "ئازار",
        "نیسان",
        "ئایار",
        "حوزەیران",
        "تەممووز",
        "ئاب",
        "ئەیلوول",
        "تشرینی یەکەم",
        "تشرینی دووەم",
        "کانوونی یەکەم"
      ],
      STANDALONESHORTMONTHS: const [
        "کانوونی دووەم",
        "شوبات",
        "ئازار",
        "نیسان",
        "ئایار",
        "حوزەیران",
        "تەممووز",
        "ئاب",
        "ئەیلوول",
        "تشرینی یەکەم",
        "تشرینی دووەم",
        "کانوونی یەکەم"
      ],
      WEEKDAYS: const [
        "یەکشەممە",
        "دووشەممە",
        "سێشەممە",
        "چوارشەممە",
        "پێنجشەممە",
        "هەینی",
        "شەممە"
      ],
      STANDALONEWEEKDAYS: const [
        "یەکشەممە",
        "دووشەممە",
        "سێشەممە",
        "چوارشەممە",
        "پێنجشەممە",
        "هەینی",
        "شەممە"
      ],
      SHORTWEEKDAYS: const [
        "یەکشەممە",
        "دووشەممە",
        "سێشەممە",
        "چوارشەممە",
        "پێنجشەممە",
        "هەینی",
        "شەممە"
      ],
      STANDALONESHORTWEEKDAYS: const [
        "یەکشەممە",
        "دووشەممە",
        "سێشەممە",
        "چوارشەممە",
        "پێنجشەممە",
        "هەینی",
        "شەممە"
      ],
      NARROWWEEKDAYS: const ["ی", "د", "س", "چ", "پ", "هـ", "ش"],
      STANDALONENARROWWEEKDAYS: const ["ی", "د", "س", "چ", "پ", "هـ", "ش"],
      SHORTQUARTERS: const ["چ١", "چ٢", "چ٣", "چ٤"],
      QUARTERS: const [
        "چارەکی یەکەم",
        "چارەکی دووەم",
        "چارەکی سێیەم",
        "چارەکی چوارەم"
      ],
      AMPMS: const ["پ.ن", "د.ن"],
      DATEFORMATS: const ["EEEE، d MMMM y", "d MMMM y", "dd/MM/y", "d/M/y"],
      TIMEFORMATS: const [
        "h:mm:ss a zzzz",
        "h:mm:ss a z",
        "h:mm:ss a",
        "h:mm a"
      ],
      DATETIMEFORMATS: const ["{1}، {0}", "{1}، {0}", "{1}، {0}", "{1}، {0}"],
      FIRSTDAYOFWEEK: 5,
      WEEKENDRANGE: const [4, 5],
      FIRSTWEEKCUTOFFDAY: 4,
    ),
    patterns: dateTimePatternMap()["ar"]!,
  );
}
