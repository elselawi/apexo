import 'package:fluent_ui/fluent_ui.dart';

/// The colour each kind of record is known by.
///
/// A patient and a visit open the same panel chrome, and several of their
/// windows carry the same labels ("Details", "Appointments"), so the colour is
/// what says at a glance *which kind of record* is in front of you — on the
/// panel's header, on its dock, and on the icon of every window that belongs to
/// it.
///
/// One palette in one place: a record kind shown in two places must look the
/// same in both.
abstract final class PanelAccents {
  static const Color patient = Color(0xFF2A7FD4);
  static const Color appointment = Color(0xFF7A5AF8);
  static const Color orders = Color(0xFF0E8A78);
  static const Color labwork = Color(0xFFB26A00);
  static const Color account = Color(0xFF5C6B7A);

  /// The accent a standalone window's [scope] names — `patient:<id>`,
  /// `appointment:<id>`, `supplier:<id>`. Null for a window that belongs to no
  /// record (a photo, a scan from a file), which then keeps the theme's accent.
  static Color? ofScope(String scope) {
    if (scope.startsWith('patient:')) return patient;
    if (scope.startsWith('appointment:')) return appointment;
    if (scope.startsWith('supplier:')) return orders;
    return null;
  }
}
