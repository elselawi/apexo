import 'package:apexo/services/localization/locale.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';

/// Formats money as it is typed, in the clinic's own number format: the integer
/// part carries the locale's thousands separators and an optional fraction
/// follows the locale's decimal separator.
///
/// Both directions agree on those two separators — the text a field shows is
/// exactly what [formatDouble] writes in and what [parse] reads back — so an
/// amount is never mistaken for a fraction of itself in the locales that group
/// with a dot (Greek, Spanish), and it survives the locales that write the
/// digits themselves in another script (Persian).
class MoneyInputFormatter extends TextInputFormatter {
  MoneyInputFormatter([NumberFormat? nf]) : _fixedNf = nf;
  final NumberFormat? _fixedNf;

  static String? _cachedCode;
  static NumberFormat? _cachedNf;

  NumberFormat get _nf {
    if (_fixedNf != null) return _fixedNf;
    final code = locale.s.$code;
    if (_cachedNf == null || _cachedCode != code) {
      _cachedCode = code;
      _cachedNf = NumberFormat.decimalPattern(code);
    }
    return _cachedNf!;
  }

  String get _groupSeparator => _nf.symbols.GROUP_SEP;

  /// The character the fields show, and accept, before a fractional part.
  String get decimalSeparator => _nf.symbols.DECIMAL_SEP;

  /// The amount [text] stands for, whatever grouping, locale digits or stray
  /// characters the field is carrying.
  double parse(String text) {
    return double.tryParse(_plain(text)) ?? 0;
  }

  /// The text that shows [value] in a field.
  String formatDouble(double value) {
    return _nf.format(value);
  }

  @override
  TextEditingValue formatEditUpdate(
      TextEditingValue oldValue, TextEditingValue newValue) {
    if (newValue.text.isEmpty) return newValue;

    final String text = _plain(newValue.text);
    if (text.isEmpty) return newValue;

    // Split integer and fractional parts
    final parts = text.split('.');
    final String integerPart = parts[0];
    final String? fractionalPart = parts.length > 1 ? parts[1] : null;

    // Format the integer part with thousands separators
    final double? intVal = double.tryParse(integerPart);
    if (intVal == null && integerPart.isNotEmpty) return oldValue;

    String formattedInt =
        intVal == null ? "" : _nf.format(intVal).split(decimalSeparator)[0];

    // Handle the case where integerPart is empty but we have a decimal (e.g. ".5")
    if (integerPart.isEmpty && text.startsWith('.')) {
      formattedInt = _nf.symbols.ZERO_DIGIT;
    }

    String result = formattedInt;
    if (fractionalPart != null) {
      result += "$decimalSeparator${_inLocaleDigits(fractionalPart)}";
    }

    return TextEditingValue(
      text: result,
      selection: TextSelection.collapsed(offset: result.length),
    );
  }

  /// `digits` or `digits.digits`: [text] with the grouping, the locale digits
  /// and everything else that is not part of the amount taken out. A second
  /// fraction is where the number ends.
  ///
  /// When the locale uses its own script's decimal mark (such as Persian `٫`)
  /// rather than `.` for grouping, an ASCII `.` from a numeric keypad is also
  /// accepted as the decimal mark.
  String _plain(String text) {
    final ascii = _inAsciiDigits(text);
    final plain = StringBuffer();
    var hasFraction = false;
    for (final code in ascii.codeUnits) {
      final char = String.fromCharCode(code);
      if (char == _groupSeparator) continue;
      if (char == decimalSeparator ||
          (_groupSeparator != '.' && char == '.')) {
        if (hasFraction) break;
        hasFraction = true;
        plain.write('.');
        continue;
      }
      if (code >= 0x30 && code <= 0x39) plain.write(char);
    }
    return plain.toString();
  }

  String _inAsciiDigits(String text) => _digits(text, toLocale: false);

  String _inLocaleDigits(String text) => _digits(text, toLocale: true);

  /// Persian fields hand back the digits they were shown, so the two scripts are
  /// translated into each other rather than dropped.
  String _digits(String text, {required bool toLocale}) {
    final zeroCode = _nf.symbols.ZERO_DIGIT.codeUnitAt(0);
    return String.fromCharCodes(text.codeUnits.map((code) {
      if (toLocale) {
        return code >= 0x30 && code <= 0x39 ? zeroCode + code - 0x30 : code;
      }
      return code >= zeroCode && code <= zeroCode + 9
          ? 0x30 + code - zeroCode
          : code;
    }));
  }
}

/// The formatter of the locale the clinic is currently using.
final moneyInputFormatter = MoneyInputFormatter();
