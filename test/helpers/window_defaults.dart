import 'package:apexo/ui/workspace/window_defaults.dart';

/// Forgets the windows each kind of panel was left with, and gives the suite a
/// store of its own.
///
/// The app binds the device's settings store at the root; a test builds the
/// layer directly, so it binds an in-memory one here. Nothing is written to
/// Hive, and one test cannot open a panel with the windows another left — the
/// reason the reset used to be needed at all.
Future<void> resetWindowDefaults() async {
  String stored = '';
  windowDefaults = WindowDefaults(
    read: () => stored,
    write: (value) => stored = value,
  );
}
