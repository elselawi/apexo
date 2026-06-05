import 'package:apexo/services/localization/locale.dart';
import 'package:fluent_ui/fluent_ui.dart';
import 'package:intl/intl.dart' hide TextDirection;

String formatMoneyInText(String text) {
  // RegExp to find integers or decimals (e.g., 1250 or 1250.5)
  final RegExp numberRegex = RegExp(r'\d+(\.\d+)?');

  // Create a formatter for currency/standard numbers with 2 decimal places
  final NumberFormat formatter = NumberFormat('#,##0.00', locale.s.$code);

  // Replace the found numbers with their formatted versions
  return text.replaceAllMapped(numberRegex, (Match match) {
    // Get the matched string (the raw number)
    String rawNumber = match.group(0)!;

    // Parse it to a double
    double? parsedNumber = double.tryParse(rawNumber);

    // If it's a valid number, format it. Otherwise, leave it alone.
    if (parsedNumber != null) {
      return formatter.format(parsedNumber);
    }
    return rawNumber;
  });
}

class MoneyDisplay extends StatelessWidget {
  const MoneyDisplay(this.string, {super.key, this.style});
  final String string;
  final TextStyle? style;

  @override
  Widget build(BuildContext context) {
    final amountFinal = formatMoneyInText(string);

    final integerPart = amountFinal.split('.')[0];
    final decimalPart =
        amountFinal.contains(".") ? amountFinal.split('.')[1] : "";

    final fStyle = (style ?? const TextStyle());
    final fontSize = fStyle.fontSize ?? 14;

    final decimalStyle = fStyle.copyWith(
      fontSize: fontSize * 0.8,
      color: fStyle.color?.withValues(alpha: 0.8),
      fontWeight: FontWeight.w400,
    );

    final integerStyle = fStyle.copyWith(
      fontSize: fontSize * 1.05,
      fontWeight: FontWeight.w500,
    );

    return Row(
      mainAxisSize: MainAxisSize.min,
      textDirection: TextDirection.ltr,
      children: [
        Text(integerPart, style: integerStyle),
        if (decimalPart.isNotEmpty)
          Text(
            ".",
            style: decimalStyle,
            textDirection: TextDirection.ltr,
          ),
        if (decimalPart.isNotEmpty)
          Text(
            decimalPart,
            style: decimalStyle,
            textDirection: TextDirection.ltr,
          ),
      ],
    );
  }
}
