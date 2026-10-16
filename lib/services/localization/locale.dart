import "dart:async";
import "package:apexo/features/settings/settings_stores.dart";
import "package:apexo/services/localization/ar.dart";
import "package:apexo/services/localization/el.dart";
import "package:apexo/services/localization/en.dart";
import "package:apexo/services/localization/es.dart";
import "package:apexo/services/localization/fa.dart";
import "package:apexo/services/localization/fr.dart";
import "package:apexo/services/localization/it.dart";
import "package:apexo/services/localization/ku.dart";
import "package:apexo/services/localization/tr.dart";
import "package:apexo/services/localization/ur.dart";
import "package:fluent_ui/fluent_ui.dart";
import "package:intl/date_symbol_data_custom.dart";
import "package:intl/date_symbol_data_local.dart";
import "package:intl/date_symbols.dart";
import "package:intl/date_time_patterns.dart";
import "package:intl/number_symbols.dart";
import "package:intl/number_symbols_data.dart";

bool _kuIntlRegistered = false;

void ensureCustomIntlLocalesInitialized() {
  if (_kuIntlRegistered) return;
  _kuIntlRegistered = true;

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
      DATEFORMATS: const [
        "EEEE، d MMMM y",
        "d MMMM y",
        "dd/MM/y",
        "d/M/y"
      ],
      TIMEFORMATS: const [
        "h:mm:ss a zzzz",
        "h:mm:ss a z",
        "h:mm:ss a",
        "h:mm a"
      ],
      DATETIMEFORMATS: const [
        "{1}، {0}",
        "{1}، {0}",
        "{1}، {0}",
        "{1}، {0}"
      ],
      FIRSTDAYOFWEEK: 5,
      WEEKENDRANGE: const [4, 5],
      FIRSTWEEKCUTOFFDAY: 4,
    ),
    patterns: dateTimePatternMap()["ar"]!,
  );
}

class _Localization {
  _Localization() {
    unawaited(initializeDateFormatting());
    ensureCustomIntlLocalesInitialized();
  }

  List<En> list = [En(), Ar(), Es(), El(), Fa(), Ku(), Fr(), Tr(), It(), Ur()];
  En get s => list[localSettings.selectedLocale];
  bool get isRtl => s.$direction == Direction.rtl;
}

final locale = _Localization();

String txt(String input) {
  final term = locale.s.dictionary[input];
  if (term != null) {
    return term;
  }
  return input;
}

class Txt extends Text {
  const Txt(
    super.data, {
    super.key,
    super.style,
    super.strutStyle,
    super.textAlign,
    super.textDirection,
    super.locale,
    super.softWrap,
    super.overflow,
    super.textScaler,
    super.maxLines,
    super.semanticsLabel,
    super.textWidthBasis,
    super.textHeightBehavior,
    super.selectionColor,
  });

  @override
  Widget build(BuildContext context) {
    return StreamBuilder(
        stream: localSettings.stream,
        builder: (context, snapshot) {
          return Text(
            data ?? "",
            key: key,
            style: style,
            locale: this.locale,
            textScaler: textScaler,
            semanticsLabel: semanticsLabel,
            textAlign: textAlign,
            textDirection: textDirection,
            softWrap: softWrap,
            overflow: overflow,
            maxLines: maxLines,
            strutStyle: strutStyle,
            textWidthBasis: textWidthBasis,
            textHeightBehavior: textHeightBehavior,
            selectionColor: selectionColor,
          );
        });
  }
}
