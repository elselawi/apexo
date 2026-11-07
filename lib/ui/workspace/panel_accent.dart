import 'package:fluent_ui/fluent_ui.dart';

/// The accent for each kind of record: panels share chrome and labels, so colour
/// is what tells record kinds apart.
abstract final class PanelAccents {
  static const Color patient = Color(0xFF2A7FD4);
  static const Color appointment = Color(0xFF7A5AF8);
  static const Color orders = Color(0xFF0E8A78);
  static const Color labwork = Color(0xFFB26A00);
  static const Color account = Color(0xFF5C6B7A);

  /// The accent a scope (`patient:`, `appointment:`, `supplier:`) names; null
  /// when it names no record, which keeps the theme accent.
  static Color? ofScope(String scope) {
    if (scope.startsWith('patient:')) return patient;
    if (scope.startsWith('appointment:')) return appointment;
    if (scope.startsWith('supplier:')) return orders;
    return null;
  }
}
