import 'package:fluent_ui/fluent_ui.dart';

Color? colorBasedOnPayments(double paid, double price) {
  final bool isOOverPaid = paid > price;
  final bool isUnderpaid = paid < price;
  return isOOverPaid
      ? Colors.blue
      : isUnderpaid
          ? Colors.warningPrimaryColor
          : null;
}
