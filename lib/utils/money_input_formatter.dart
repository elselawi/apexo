import 'package:apexo/services/localization/locale.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';

class _NaturalCurrencyInputFormatter extends TextInputFormatter {
  final NumberFormat _nf;
  _NaturalCurrencyInputFormatter(this._nf);

  double parse(String text) {
    return double.tryParse(text.replaceAll(RegExp(r'[^\d.]'), '')) ?? 0;
  }

  String formatDouble(double value) {
    return _nf.format(value);
  }

  @override
  TextEditingValue formatEditUpdate(
      TextEditingValue oldValue, TextEditingValue newValue) {
    if (newValue.text.isEmpty) return newValue;

    // Get raw digits and decimal point
    String text = newValue.text.replaceAll(RegExp(r'[^\d.]'), '');
    if (text.isEmpty) return newValue;

    // Split integer and fractional parts
    final parts = text.split('.');
    String integerPart = parts[0];
    String? fractionalPart = parts.length > 1 ? parts[1] : null;

    // Format the integer part with thousands separators
    double? intVal = double.tryParse(integerPart);
    if (intVal == null && integerPart.isNotEmpty) return oldValue;

    String formattedInt = intVal == null
        ? ""
        : _nf.format(intVal).split(_nf.symbols.DECIMAL_SEP)[0];

    // Handle the case where integerPart is empty but we have a decimal (e.g. ".5")
    if (integerPart.isEmpty && text.startsWith('.')) {
      formattedInt = "0";
    }

    String result = formattedInt;
    if (text.contains('.')) {
      result += ".${fractionalPart ?? ""}";
    }

    return TextEditingValue(
      text: result,
      selection: TextSelection.collapsed(offset: result.length),
    );
  }
}

final moneyInputFormatter =
    _NaturalCurrencyInputFormatter(NumberFormat.decimalPattern(locale.s.$code));
